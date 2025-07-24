#!/usr/bin/env bash

# repomix-autotune installer script
# Usage: curl -fsSL https://raw.githubusercontent.com/clintrorick/repomix-autotune/main/install.sh | bash

set -euo pipefail

readonly REPO_URL="https://raw.githubusercontent.com/clintrorick/repomix-autotune/main"
readonly SCRIPT_NAME="repomix-autotune"
readonly INSTALL_DIR="/usr/local/bin"

# Colors for output
if [[ -t 1 ]] && command -v tput >/dev/null 2>&1; then
    readonly RED=$(tput setaf 1)
    readonly GREEN=$(tput setaf 2)
    readonly YELLOW=$(tput setaf 3)
    readonly BLUE=$(tput setaf 4)
    readonly BOLD=$(tput bold)
    readonly RESET=$(tput sgr0)
else
    readonly RED="" GREEN="" YELLOW="" BLUE="" BOLD="" RESET=""
fi

log_info() { echo "${BLUE}[INFO]${RESET} $*"; }
log_success() { echo "${GREEN}[SUCCESS]${RESET} $*"; }
log_warn() { echo "${YELLOW}[WARN]${RESET} $*"; }
log_error() { echo "${RED}[ERROR]${RESET} $*" >&2; }

check_dependencies() {
    local missing_deps=()
    
    for cmd in curl chmod; do
        if ! command -v "$cmd" >/dev/null 2>&1; then
            missing_deps+=("$cmd")
        fi
    done
    
    if [[ ${#missing_deps[@]} -gt 0 ]]; then
        log_error "Missing required dependencies: ${missing_deps[*]}"
        exit 1
    fi
}

check_permissions() {
    if [[ ! -w "$INSTALL_DIR" ]]; then
        log_error "Cannot write to $INSTALL_DIR"
        log_info "Try running with sudo: curl -fsSL $REPO_URL/install.sh | sudo bash"
        exit 1
    fi
}

install_script() {
    local temp_file
    temp_file=$(mktemp)
    
    log_info "Downloading repomix-autotune..."
    if curl -fsSL "$REPO_URL/repomix-autotune.sh" -o "$temp_file"; then
        log_success "Downloaded successfully"
    else
        log_error "Failed to download script"
        rm -f "$temp_file"
        exit 1
    fi
    
    log_info "Installing to $INSTALL_DIR/$SCRIPT_NAME..."
    if mv "$temp_file" "$INSTALL_DIR/$SCRIPT_NAME" && chmod +x "$INSTALL_DIR/$SCRIPT_NAME"; then
        log_success "Installed successfully"
    else
        log_error "Failed to install script"
        rm -f "$temp_file"
        exit 1
    fi
}

verify_installation() {
    if command -v "$SCRIPT_NAME" >/dev/null 2>&1; then
        log_success "Installation verified: $SCRIPT_NAME is available in PATH"
        log_info "Run '$SCRIPT_NAME --help' to get started"
    else
        log_warn "Installation completed but $SCRIPT_NAME not found in PATH"
        log_info "You may need to add $INSTALL_DIR to your PATH or restart your shell"
    fi
}

main() {
    echo "${BOLD}repomix-autotune installer${RESET}"
    echo "Installing to $INSTALL_DIR/$SCRIPT_NAME"
    echo
    
    check_dependencies
    check_permissions
    install_script
    verify_installation
    
    echo
    log_success "Installation complete! 🎉"
    echo
    echo "${BOLD}Next steps:${RESET}"
    echo "  1. Ensure repomix is installed: ${BLUE}npm install -g repomix${RESET}"
    echo "  2. Ensure claude CLI is installed: ${BLUE}curl -fsSL https://claude.ai/install.sh | sh${RESET}"
    echo "  3. Run: ${BLUE}$SCRIPT_NAME --help${RESET}"
}

main "$@"