#!/usr/bin/env bash
# Sets up the Herdr Menu Bar auto-start and auto-stop shell integration.
# Whenever you run `herdr` in the terminal, Herdr Menu Bar will start automatically in the background.
# Whenever you run `herdr server stop`, Herdr Menu Bar will close automatically.

set -euo pipefail

BUNDLE_ID="io.github.aditya24sharma.herdr-menubar"
START_MARKER="# Herdr Menu Bar integration"
END_MARKER="# End Herdr Menu Bar integration"
LEGACY_MARKER="# Herdr Menu Bar auto-start"

# Determine default shell config file
detect_config_file() {
    local shell_name
    shell_name="$(basename "${SHELL:-zsh}")"

    if [[ "$shell_name" == "zsh" ]]; then
        echo "${HOME}/.zshrc"
    elif [[ "$shell_name" == "bash" ]]; then
        if [[ -f "${HOME}/.bashrc" ]]; then
            echo "${HOME}/.bashrc"
        else
            echo "${HOME}/.bash_profile"
        fi
    else
        if [[ -f "${HOME}/.zshrc" ]]; then
            echo "${HOME}/.zshrc"
        elif [[ -f "${HOME}/.bashrc" ]]; then
            echo "${HOME}/.bashrc"
        else
            echo "${HOME}/.zshrc"
        fi
    fi
}

CONFIG_FILE="${HERDR_CONFIG_FILE:-$(detect_config_file)}"
ACTION="install"

usage() {
    cat <<EOF
Usage: $0 [options]

Options:
  --install     Add the herdr shell integration to your shell configuration (default)
  --uninstall   Remove the shell integration from your shell configuration
  --status      Check if the integration is currently configured
  --help, -h    Show this help message

Shell configuration file targeted: ${CONFIG_FILE}
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --install)
            ACTION="install"
            shift
            ;;
        --uninstall)
            ACTION="uninstall"
            shift
            ;;
        --status)
            ACTION="status"
            shift
            ;;
        --help|-h)
            usage
            exit 0
            ;;
        *)
            echo "Unknown option: $1" >&2
            usage
            exit 1
            ;;
    esac
done

is_installed() {
    if [[ ! -f "$CONFIG_FILE" ]]; then
        return 1
    fi
    grep -q "${BUNDLE_ID}" "$CONFIG_FILE" || grep -q "${START_MARKER}" "$CONFIG_FILE" || grep -q "${LEGACY_MARKER}" "$CONFIG_FILE"
}

remove_integration() {
    if [[ ! -f "$CONFIG_FILE" ]]; then
        return 0
    fi
    local tmp_file
    tmp_file="$(mktemp)"
    # Strip everything between START_MARKER and END_MARKER, plus any legacy lines
    awk -v start="$START_MARKER" -v end="$END_MARKER" -v legacy="$LEGACY_MARKER" -v bid="$BUNDLE_ID" '
        $0 ~ start { in_block=1; next }
        $0 ~ end { in_block=0; next }
        in_block { next }
        $0 ~ legacy { next }
        $0 ~ bid && $0 ~ /alias herdr=/ { next }
        { print }
    ' "$CONFIG_FILE" > "$tmp_file"
    mv "$tmp_file" "$CONFIG_FILE"
}

case "$ACTION" in
    status)
        echo "Target shell config: $CONFIG_FILE"
        if is_installed; then
            echo "Status: Installed"
        else
            echo "Status: Not installed"
        fi
        ;;
    uninstall)
        if ! is_installed; then
            echo "Herdr shell integration is not installed in $CONFIG_FILE"
            exit 0
        fi
        remove_integration
        echo "Successfully removed Herdr shell integration from $CONFIG_FILE"
        ;;
    install)
        if is_installed; then
            # Clean previous version to update in place
            remove_integration
        fi
        touch "$CONFIG_FILE"
        cat <<EOF >> "$CONFIG_FILE"

${START_MARKER}
herdr() {
    if [[ "\$1" == "server" && "\$2" == "stop" ]]; then
        command herdr "\$@"
        osascript -e 'quit app id "${BUNDLE_ID}"' 2>/dev/null || true
    else
        open -b ${BUNDLE_ID} --background 2>/dev/null || true
        command herdr "\$@"
    fi
}
${END_MARKER}
EOF
        echo "Successfully added Herdr shell integration to $CONFIG_FILE"
        echo ""
        echo "To apply changes in your current terminal session, run:"
        echo "  source $CONFIG_FILE"
        ;;
esac
