#!/usr/bin/env bash
# Check ~/.local/bin is in PATH. Exits 1 with fix instructions if not.
set -euo pipefail

bin="$HOME/.local/bin"
case ":$PATH:" in
    *":$bin:"*) exit 0 ;;
esac

echo
echo "Warning: $bin is not in your PATH"
echo
echo "To fix, add this line to your shell config:"
echo
echo '    export PATH="$HOME/.local/bin:$PATH"'
echo

# Detect shell and suggest the right config file
shell_name="$(basename "${SHELL:-bash}")"
case "$shell_name" in
    bash)
        if [ -f "$HOME/.bash_profile" ]; then
            config_file="~/.bash_profile"
        else
            config_file="~/.bashrc"
        fi
        ;;
    zsh)  config_file="~/.zshrc" ;;
    fish)
        echo "For fish, add to ~/.config/fish/config.fish:"
        echo
        echo "    set -U fish_user_paths \$HOME/.local/bin \$fish_user_paths"
        echo
        echo "Then reload: fish"
        exit 1
        ;;
    *)    config_file="~/.${shell_name}rc" ;;
esac

echo "Edit: $config_file"
echo
echo "Then reload your shell:"
echo "    source $config_file"
echo "  or start a new terminal"
echo

exit 1
