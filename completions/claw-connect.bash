# bash/zsh completions for claw-connect
# Sourced automatically by install.sh

_claw_connect_profiles() {
    local config_dir="$HOME/.config/claw-connect/profiles"
    if [[ -d "$config_dir" ]]; then
        for dir in "$config_dir"/*/; do
            [[ -f "$dir/config" ]] && basename "$dir"
        done
    fi
}

_claw_connect_completions() {
    local cur prev words cword
    if type _init_completion &>/dev/null; then
        _init_completion || return
    else
        cur="${COMP_WORDS[COMP_CWORD]}"
        prev="${COMP_WORDS[COMP_CWORD-1]}"
    fi

    local commands="setup profiles"
    local flags="-p --profile -t --tunnel --legacy-vnc -v --vnc -r --resume -l --list -k --kill -u --user --init-tmux --version -h --help"

    case "$prev" in
        -p|--profile|setup)
            COMPREPLY=( $(compgen -W "$(_claw_connect_profiles)" -- "$cur") )
            return
            ;;
        -u|--user|-k|--kill|-r|--resume)
            return
            ;;
    esac

    if [[ "$cur" == -* ]]; then
        COMPREPLY=( $(compgen -W "$flags" -- "$cur") )
        return
    fi

    COMPREPLY=( $(compgen -W "$commands $flags" -- "$cur") )
}

complete -F _claw_connect_completions claw-connect
