#!/usr/bin/env bash

# Team deployment script for repomix-autotune
# Run this on team machines to bulk install repomix-autotune

set -euo pipefail

readonly TOOL_NAME="repomix-autotune"
readonly INSTALL_URL="https://raw.githubusercontent.com/clintrorick/repomix-autotune/main/install.sh"

# Configuration
SILENT=false
CHECK_ONLY=false
FORCE_REINSTALL=false

usage() {
    cat << EOF
Team deployment script for $TOOL_NAME

Usage: $0 [OPTIONS]

Options:
    -s, --silent        Silent installation (no prompts)
    -c, --check         Check installation status only
    -f, --force         Force reinstall even if already installed
    -h, --help          Show this help message

Examples:
    $0                  # Interactive installation
    $0 --silent         # Silent installation
    $0 --check          # Check if already installed
    $0 --force          # Force reinstall
EOF
}

parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -s|--silent)
                SILENT=true
                shift
                ;;
            -c|--check)
                CHECK_ONLY=true
                shift
                ;;
            -f|--force)
                FORCE_REINSTALL=true
                shift
                ;;
            -h|--help)
                usage
                exit 0
                ;;
            *)
                echo "Unknown option: $1" >&2
                usage >&2
                exit 1
                ;;
        esac
    done
}

check_installation() {
    if command -v "$TOOL_NAME" >/dev/null 2>&1; then
        local version
        version=$("$TOOL_NAME" --help 2>/dev/null | grep -o "repomix-autotune.*" | head -1 || echo "unknown version")
        echo "✅ $TOOL_NAME is installed ($version)"
        return 0
    else
        echo "❌ $TOOL_NAME is not installed"
        return 1
    fi
}

check_prerequisites() {
    local missing=()
    
    # Check for required tools
    for tool in curl repomix claude jq git; do
        if ! command -v "$tool" >/dev/null 2>&1; then
            missing+=("$tool")
        fi
    done
    
    if [[ ${#missing[@]} -gt 0 ]]; then
        echo "⚠️  Missing prerequisites: ${missing[*]}"
        echo "Please install missing tools before continuing."
        return 1
    fi
    
    echo "✅ All prerequisites found"
    return 0
}

install_tool() {
    echo "🚀 Installing $TOOL_NAME..."
    
    if [[ "$SILENT" == true ]]; then
        curl -fsSL "$INSTALL_URL" | bash >/dev/null 2>&1
    else
        curl -fsSL "$INSTALL_URL" | bash
    fi
    
    if check_installation >/dev/null 2>&1; then
        echo "✅ Installation successful!"
        return 0
    else
        echo "❌ Installation failed"
        return 1
    fi
}

prompt_user() {
    local message="$1"
    local default="$2"
    
    if [[ "$SILENT" == true ]]; then
        return 0
    fi
    
    echo -n "$message [y/N]: "
    read -r response
    response=${response:-$default}
    
    case "$response" in
        [yY]|[yY][eE][sS])
            return 0
            ;;
        *)
            return 1
            ;;
    esac
}

main() {
    parse_args "$@"
    
    echo "🔧 Team deployment for $TOOL_NAME"
    echo
    
    # Check-only mode
    if [[ "$CHECK_ONLY" == true ]]; then
        check_installation
        check_prerequisites
        exit $?
    fi
    
    # Check current installation
    if check_installation >/dev/null 2>&1; then
        if [[ "$FORCE_REINSTALL" == true ]]; then
            echo "🔄 Forcing reinstallation..."
        elif ! prompt_user "Tool is already installed. Reinstall?" "n"; then
            echo "✅ No action needed"
            exit 0
        fi
    fi
    
    # Check prerequisites
    if ! check_prerequisites; then
        echo
        echo "Please install missing prerequisites and try again."
        echo "Common installation commands:"
        echo "  repomix: npm install -g repomix"
        echo "  claude:  curl -fsSL https://claude.ai/install.sh | sh"
        echo "  jq:      brew install jq (macOS) or apt install jq (Linux)"
        exit 1
    fi
    
    # Install the tool
    echo
    if install_tool; then
        echo
        echo "🎉 Team deployment complete!"
        echo
        echo "Next steps:"
        echo "  1. Verify: $TOOL_NAME --help"
        echo "  2. Test:   $TOOL_NAME --dry-run"
        echo "  3. Use:    $TOOL_NAME"
    else
        echo
        echo "❌ Team deployment failed"
        echo "Please check the error messages above and try again."
        exit 1
    fi
}

main "$@"