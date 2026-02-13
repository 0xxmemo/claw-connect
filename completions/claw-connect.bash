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
    local flags="-p --profile -t --tunnel -v --vnc -d --deploy -r --resume -l --list -k --kill -u --user --init-tmux -h --help"

    # Complete profile name after -p / --profile / setup
    case "$prev" in
        -p|--profile|setup)
            COMPREPLY=( $(compgen -W "$(_claw_connect_profiles)" -- "$cur") )
            return
            ;;
        -u|--user)
            return  # user provides their own value
            ;;
        -k|--kill|-r|--resume)
            return  # session name, no completions
            ;;
    esac

    # If current word starts with -, complete flags
    if [[ "$cur" == -* ]]; then
        COMPREPLY=( $(compgen -W "$flags" -- "$cur") )
        return
    fi

    # Default: complete commands and flags
    COMPREPLY=( $(compgen -W "$commands $flags" -- "$cur") )
}

complete -F _claw_connect_completions claw-connect
