#!/usr/bin/env bun
/**
 * Enhanced authenticated noVNC + CDP proxy (Bun runtime).
 *
 * - Serves a custom viewer.html at /
 * - Serves noVNC static assets from NOVNC_DIR
 * - Proxies VNC WebSocket to upstream websockify
 * - Exposes CDP REST API endpoints (tabs, activate, screenshot)
 * - Auth: first request with ?token= sets an HttpOnly cookie;
 *   subsequent requests (module imports, assets, WS) use the cookie.
 *
 * Env vars:
 *   OPENCLAW_GATEWAY_TOKEN  - required auth token
 *   NOVNC_PORT              - websockify port (default 6080)
 *   AUTH_PORT               - this proxy's listen port (default 6090)
 *   CDP_PORT                - Chrome DevTools Protocol port (default 18800)
 *   NOVNC_DIR               - noVNC static files directory
 */
import { join, normalize } from 'node:path';

const TOKEN = process.env.OPENCLAW_GATEWAY_TOKEN;
if (!TOKEN) {
  console.error('OPENCLAW_GATEWAY_TOKEN not set');
  process.exit(1);
}

const NOVNC_PORT = parseInt(process.env.NOVNC_PORT || '6080');
const AUTH_PORT = parseInt(process.env.AUTH_PORT || '6090');
const CDP_PORT = parseInt(process.env.CDP_PORT || '18800');
const NOVNC_DIR = process.env.NOVNC_DIR || '/usr/share/novnc';
const SCRIPT_DIR = import.meta.dir; // Bun-native: directory of this file

const AUTH_COOKIE = '__vnc_auth';

// ── Auth ────────────────────────────────────────────────────────

/** Returns 'param' | 'cookie' | null */
function checkAuth(req) {
  const url = new URL(req.url);
  if (url.searchParams.get('token') === TOKEN) return 'param';

  const cookies = req.headers.get('cookie') || '';
  const m = cookies.match(new RegExp(`(?:^|;\\s*)${AUTH_COOKIE}=([^;]+)`));
  if (m?.[1] === TOKEN) return 'cookie';

  return null;
}

/** If authed via ?token= param, return Set-Cookie header to persist session */
function authCookieHeaders(authSource) {
  if (authSource === 'param') {
    return {
      'Set-Cookie': `${AUTH_COOKIE}=${TOKEN}; HttpOnly; SameSite=Strict; Path=/; Max-Age=86400`,
    };
  }
  return {};
}

// ── CDP helpers ─────────────────────────────────────────────────

async function cdpFetch(path) {
  const res = await fetch(`http://127.0.0.1:${CDP_PORT}${path}`);
  return res.json();
}

function cdpCommand(wsUrl, method, params = {}) {
  return new Promise((resolve, reject) => {
    const ws = new WebSocket(wsUrl);
    const id = 1;
    const timer = setTimeout(() => {
      ws.close();
      reject(new Error('CDP command timeout'));
    }, 8000);

    ws.onopen = () => ws.send(JSON.stringify({ id, method, params }));
    ws.onmessage = (e) => {
      try {
        const msg = JSON.parse(typeof e.data === 'string' ? e.data : new TextDecoder().decode(e.data));
        if (msg.id === id) {
          clearTimeout(timer);
          ws.close();
          msg.error ? reject(new Error(msg.error.message)) : resolve(msg.result);
        }
      } catch { /* ignore non-matching frames */ }
    };
    ws.onerror = () => {
      clearTimeout(timer);
      reject(new Error('CDP WebSocket error'));
    };
  });
}

// ── Server ──────────────────────────────────────────────────────

const server = Bun.serve({
  port: AUTH_PORT,
  hostname: '0.0.0.0',

  async fetch(req, server) {
    const url = new URL(req.url);
    const pathname = url.pathname;

    // ── WebSocket upgrade (VNC stream) ──
    if (req.headers.get('upgrade')?.toLowerCase() === 'websocket') {
      const auth = checkAuth(req);
      if (!auth) return new Response('Unauthorized', { status: 401 });
      const ok = server.upgrade(req, { data: {} });
      return ok ? undefined : new Response('WebSocket upgrade failed', { status: 500 });
    }

    // ── Auth gate ──
    const auth = checkAuth(req);
    if (!auth) {
      return new Response('Unauthorized — append ?token=YOUR_GATEWAY_TOKEN', {
        status: 401,
        headers: { 'Content-Type': 'text/plain' },
      });
    }
    const extra = authCookieHeaders(auth);

    // ── Viewer page ──
    if (pathname === '/' || pathname === '/index.html' || pathname === '/viewer.html') {
      return new Response(Bun.file(join(SCRIPT_DIR, 'viewer.html')), {
        headers: { ...extra, 'Content-Type': 'text/html; charset=utf-8' },
      });
    }

    // ── API: list browser tabs ──
    if (pathname === '/api/tabs') {
      try {
        return Response.json(await cdpFetch('/json'), { headers: extra });
      } catch (err) {
        return Response.json(
          { error: 'CDP unavailable', details: String(err) },
          { status: 502 },
        );
      }
    }

    // ── API: activate tab ──
    const actMatch = pathname.match(/^\/api\/activate\/(.+)$/);
    if (actMatch && req.method === 'POST') {
      try {
        await cdpFetch(`/json/activate/${actMatch[1]}`);
        return Response.json({ ok: true });
      } catch (err) {
        return Response.json(
          { error: 'Activate failed', details: String(err) },
          { status: 502 },
        );
      }
    }

    // ── API: screenshot ──
    const ssMatch = pathname.match(/^\/api\/screenshot\/(.+)$/);
    if (ssMatch) {
      try {
        const allTabs = await cdpFetch('/json');
        const tab = allTabs.find((t) => t.id === ssMatch[1]);
        if (!tab) return Response.json({ error: 'Tab not found' }, { status: 404 });
        const result = await cdpCommand(
          tab.webSocketDebuggerUrl,
          'Page.captureScreenshot',
          { format: 'png', quality: 80 },
        );
        return Response.json(result);
      } catch (err) {
        return Response.json(
          { error: 'Screenshot failed', details: String(err) },
          { status: 502 },
        );
      }
    }

    // ── noVNC static files ──
    const filePath = normalize(join(NOVNC_DIR, pathname));
    if (filePath.startsWith(NOVNC_DIR)) {
      const file = Bun.file(filePath);
      if (await file.exists()) {
        return new Response(file, {
          headers: { ...extra, 'Cache-Control': 'public, max-age=3600' },
        });
      }
    }

    return new Response('Not found', { status: 404 });
  },

  // ── WebSocket handler (VNC relay) ─────────────────────────────
  websocket: {
    open(ws) {
      const upstream = new WebSocket(`ws://127.0.0.1:${NOVNC_PORT}`);
      upstream.binaryType = 'arraybuffer';

      const queue = [];
      ws.data.upstream = upstream;
      ws.data.queue = queue;
      ws.data.ready = false;

      upstream.onopen = () => {
        ws.data.ready = true;
        for (const msg of queue) upstream.send(msg);
        queue.length = 0;
      };
      upstream.onmessage = (e) => {
        try { ws.send(e.data); } catch { /* client gone */ }
      };
      upstream.onclose = () => {
        try { ws.close(); } catch { /* already closed */ }
      };
      upstream.onerror = () => {
        try { ws.close(); } catch { /* already closed */ }
      };
    },

    message(ws, message) {
      if (ws.data.ready) {
        try { ws.data.upstream.send(message); } catch { /* upstream gone */ }
      } else {
        ws.data.queue.push(message);
      }
    },

    close(ws) {
      try { ws.data.upstream?.close(); } catch { /* ok */ }
    },

    perMessageDeflate: false,
  },
});

console.log(`✅ Enhanced VNC proxy (Bun) on :${server.port}`);
console.log(`   noVNC → :${NOVNC_PORT} | CDP → :${CDP_PORT}`);
console.log(`   Viewer: http://YOUR_IP:${server.port}/?token=${TOKEN.slice(0, 4)}...`);
