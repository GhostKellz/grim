#!/usr/bin/env bash
# Grim Editor - Installation Script
# Version: 0.1.0
# Author: Ghost Ecosystem
# License: MIT

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
GRIM_VERSION="0.1.0"
INSTALL_PREFIX="${PREFIX:-$HOME/.local}"
BUILD_TYPE="${BUILD_TYPE:-ReleaseSafe}"

# Print colored output
print_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Banner
print_banner() {
    cat << "EOF"
   ____       _
  / ___|_ __ (_)_ __ ___
 | |  _| '__|| | '_ ` _ \
 | |_| | |   | | | | | | |
  \____|_|   |_|_| |_| |_|

  The Zig-Powered Modal Editor
  Version 0.1.0

EOF
}

# Check prerequisites
check_prerequisites() {
    print_info "Checking prerequisites..."

    # Check Zig
    if ! command -v zig &> /dev/null; then
        print_error "Zig is not installed!"
        print_info "Please install Zig 0.16.0+ from https://ziglang.org/download/"
        exit 1
    fi

    ZIG_VERSION=$(zig version)
    print_success "Found Zig $ZIG_VERSION"

    # Check Git
    if ! command -v git &> /dev/null; then
        print_error "Git is not installed!"
        exit 1
    fi
    print_success "Found Git"

    # Check build essentials
    if ! command -v make &> /dev/null; then
        print_warning "Make not found (optional)"
    fi
}

# Build Grim
build_grim() {
    print_info "Building Grim..."

    # Clean previous build
    if [ -d ".zig-cache" ]; then
        print_info "Cleaning previous build..."
        rm -rf .zig-cache zig-out
    fi

    # Build with optimizations
    print_info "Compiling (this may take a few minutes)..."
    zig build -Doptimize="$BUILD_TYPE" 2>&1 | tee build.log

    if [ ! -f "zig-out/bin/grim" ]; then
        print_error "Build failed! Check build.log for details."
        exit 1
    fi

    print_success "Build complete!"
}

# Install Grim
install_grim() {
    print_info "Installing Grim to $INSTALL_PREFIX..."

    # Create directories
    mkdir -p "$INSTALL_PREFIX/bin"
    mkdir -p "$INSTALL_PREFIX/share/grim"
    mkdir -p "$INSTALL_PREFIX/share/man/man1"
    mkdir -p "$HOME/.config/grim"
    mkdir -p "$HOME/.local/share/grim/plugins"

    # Install binary
    print_info "Installing binary..."
    cp zig-out/bin/grim "$INSTALL_PREFIX/bin/grim"
    chmod +x "$INSTALL_PREFIX/bin/grim"

    # Install runtime files
    print_info "Installing runtime files..."
    if [ -d "runtime" ]; then
        cp -r runtime/* "$INSTALL_PREFIX/share/grim/"
    fi

    # Install themes
    if [ -d "themes" ]; then
        mkdir -p "$INSTALL_PREFIX/share/grim/themes"
        cp -r themes/* "$INSTALL_PREFIX/share/grim/themes/"
    fi

    # Install syntax files
    if [ -d "syntax" ]; then
        mkdir -p "$INSTALL_PREFIX/share/grim/syntax"
        cp -r syntax/* "$INSTALL_PREFIX/share/grim/syntax/"
    fi

    # Create default config if it doesn't exist
    if [ ! -f "$HOME/.config/grim/init.gza" ]; then
        print_info "Creating default configuration..."
        cat > "$HOME/.config/grim/init.gza" << 'EOFCONFIG'
-- Grim Editor Configuration
-- Edit this file to customize your Grim setup

-- Basic settings
vim.opt.number = true
vim.opt.relativenumber = true
vim.opt.tabstop = 4
vim.opt.shiftwidth = 4
vim.opt.expandtab = true

-- Leader key
vim.g.mapleader = " "

-- Keybindings
vim.keymap.set("n", "<leader>w", ":write<CR>", { desc = "Save file" })
vim.keymap.set("n", "<leader>q", ":quit<CR>", { desc = "Quit" })

print("Grim configuration loaded!")
EOFCONFIG
        print_success "Created default config at ~/.config/grim/init.gza"
    fi

    print_success "Installation complete!"
}

# Setup PATH
setup_path() {
    print_info "Setting up PATH..."

    # Detect shell
    SHELL_RC=""
    if [ -n "$BASH_VERSION" ]; then
        SHELL_RC="$HOME/.bashrc"
    elif [ -n "$ZSH_VERSION" ]; then
        SHELL_RC="$HOME/.zshrc"
    fi

    # Check if PATH is already set
    if echo "$PATH" | grep -q "$INSTALL_PREFIX/bin"; then
        print_success "PATH already configured"
        return
    fi

    # Add to shell config
    if [ -n "$SHELL_RC" ]; then
        print_info "Adding Grim to PATH in $SHELL_RC..."
        echo "" >> "$SHELL_RC"
        echo "# Grim Editor" >> "$SHELL_RC"
        echo "export PATH=\"$INSTALL_PREFIX/bin:\$PATH\"" >> "$SHELL_RC"
        print_success "Added to $SHELL_RC"
        print_warning "Please run: source $SHELL_RC"
    else
        print_warning "Unknown shell. Please add $INSTALL_PREFIX/bin to your PATH manually."
    fi
}

# Install dependencies (optional)
install_dependencies() {
    print_info "Checking optional dependencies..."

    # Tree-sitter (for syntax highlighting)
    if ! command -v tree-sitter &> /dev/null; then
        print_warning "tree-sitter not found (optional for advanced syntax highlighting)"
        print_info "Install with: npm install -g tree-sitter-cli"
    fi

    # Ripgrep (for fast search)
    if ! command -v rg &> /dev/null; then
        print_warning "ripgrep not found (optional for fast search)"
        print_info "Install with your package manager: apt install ripgrep"
    fi

    # fd (for fast file finding)
    if ! command -v fd &> /dev/null; then
        print_warning "fd not found (optional for fast file finding)"
        print_info "Install with your package manager: apt install fd-find"
    fi
}

# Post-install message
post_install() {
    cat << EOF

${GREEN}╔════════════════════════════════════════════════════════════╗
║                                                            ║
║   🎉  Grim Editor Installed Successfully!  🎉             ║
║                                                            ║
╚════════════════════════════════════════════════════════════╝${NC}

${BLUE}Installation Summary:${NC}
  • Binary:        $INSTALL_PREFIX/bin/grim
  • Runtime files: $INSTALL_PREFIX/share/grim/
  • Config:        $HOME/.config/grim/
  • Plugins:       $HOME/.local/share/grim/plugins/

${BLUE}Quick Start:${NC}
  1. Run: ${GREEN}grim${NC}
  2. Edit config: ${GREEN}grim ~/.config/grim/init.gza${NC}
  3. Install plugins in: ${GREEN}~/.local/share/grim/plugins/${NC}

${BLUE}Next Steps:${NC}
  • Install Phantom.grim (LazyVim-like distro):
    ${GREEN}git clone https://github.com/ghostkellz/phantom.grim ~/.config/grim${NC}

  • Install Thanos AI plugin:
    ${GREEN}git clone https://github.com/ghostkellz/thanos.grim ~/.local/share/grim/plugins/thanos${NC}

${BLUE}Documentation:${NC}
  • Docs:  https://github.com/ghostkellz/grim/docs
  • Wiki:  https://github.com/ghostkellz/grim/wiki
  • Help:  ${GREEN}:help${NC} (inside Grim)

${BLUE}Get Help:${NC}
  • Issues:      https://github.com/ghostkellz/grim/issues
  • Discussions: https://github.com/ghostkellz/grim/discussions
  • Discord:     https://discord.gg/grim-editor

${YELLOW}Note:${NC} Run 'source ~/.bashrc' (or ~/.zshrc) to update your PATH

Happy editing! 🚀

EOF
}

# Uninstall function
uninstall() {
    print_info "Uninstalling Grim..."

    rm -f "$INSTALL_PREFIX/bin/grim"
    rm -rf "$INSTALL_PREFIX/share/grim"

    print_warning "Config preserved at: $HOME/.config/grim/"
    print_warning "To remove config: rm -rf ~/.config/grim ~/.local/share/grim"

    print_success "Grim uninstalled!"
}

# Main installation flow
main() {
    print_banner

    # Parse arguments
    case "${1:-}" in
        uninstall)
            uninstall
            exit 0
            ;;
        --prefix=*)
            INSTALL_PREFIX="${1#*=}"
            ;;
        --help|-h)
            cat << EOF
Grim Editor Installation Script

Usage:
  ./install.sh [OPTIONS]

Options:
  --prefix=PATH     Install to custom prefix (default: ~/.local)
  --help, -h        Show this help message
  uninstall         Remove Grim from system

Environment Variables:
  PREFIX            Installation prefix (default: ~/.local)
  BUILD_TYPE        Build type: Debug, ReleaseSafe, ReleaseFast (default: ReleaseSafe)

Examples:
  ./install.sh                        # Install to ~/.local
  PREFIX=/usr/local ./install.sh      # Install system-wide
  BUILD_TYPE=ReleaseFast ./install.sh # Optimized build
  ./install.sh uninstall              # Remove Grim

EOF
            exit 0
            ;;
    esac

    # Run installation steps
    check_prerequisites
    build_grim
    install_grim
    setup_path
    install_dependencies
    post_install
}

# Run main function
main "$@"
