_claw_connect() {
  local cur prev opts commands
  COMPREPLY=()
  cur="${COMP_WORDS[COMP_CWORD]}"
  prev="${COMP_WORDS[COMP_CWORD-1]}"

  commands="setup profiles sessions clean-sessions"
  opts="-p --profile -t --tunnel -v --vnc -r --resume -s --session -l --list -k --kill -u --user --update --init-tmux --version -h --help"

  case "$prev" in
    -p|--profile)
      local config_dir="$HOME/.config/claw-connect/profiles"
      if [[ -d "$config_dir" ]]; then
        COMPREPLY=($(compgen -W "$(ls "$config_dir" 2>/dev/null)" -- "$cur"))
      fi
      return
      ;;
    -k|--kill|-r|--resume|-s|--session|-u|--user)
      return
      ;;
  esac

  if [[ "$cur" == -* ]]; then
    COMPREPLY=($(compgen -W "$opts" -- "$cur"))
  else
    COMPREPLY=($(compgen -W "$commands" -- "$cur"))
  fi
}

complete -F _claw_connect claw-connect
