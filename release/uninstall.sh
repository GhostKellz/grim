#!/bin/bash

# Grim Editor Uninstaller
# Use for testing/development - clean removal of Grim

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_header() {
    echo -e "${BLUE}"
    echo "╔═══════════════════════════════════════════════════╗"
    echo "║            Grim Uninstaller                       ║"
    echo "╚═══════════════════════════════════════════════════╝"
    echo -e "${NC}"
}

print_step() { echo -e "${BLUE}==>${NC} $1"; }
print_success() { echo -e "${GREEN}✓${NC} $1"; }
print_warning() { echo -e "${YELLOW}⚠${NC} $1"; }

uninstall_grim() {
    print_step "Removing Grim installation..."

    # Remove binary
    if [ -f "/usr/local/bin/grim" ]; then
        sudo rm -f /usr/local/bin/grim
        print_success "Removed /usr/local/bin/grim"
    fi

    if [ -f "$HOME/.local/bin/grim" ]; then
        rm -f "$HOME/.local/bin/grim"
        print_success "Removed ~/.local/bin/grim"
    fi

    # Backup and remove config (optional)
    if [ -d "$HOME/.config/grim" ]; then
        if [ "$1" = "--purge" ]; then
            # Backup first
            BACKUP="$HOME/.config/grim.backup.$(date +%Y%m%d-%H%M%S)"
            mv "$HOME/.config/grim" "$BACKUP"
            print_success "Backed up config to $BACKUP"
        else
            print_warning "Config preserved at ~/.config/grim (use --purge to remove)"
        fi
    fi

    # Remove plugins directory (if --purge)
    if [ "$1" = "--purge" ]; then
        if [ -d "$HOME/.local/share/grim" ]; then
            rm -rf "$HOME/.local/share/grim"
            print_success "Removed ~/.local/share/grim"
        fi
    else
        print_warning "Plugins preserved at ~/.local/share/grim (use --purge to remove)"
    fi
}

main() {
    print_header

    if [ "$1" = "--purge" ]; then
        echo "Uninstalling Grim and removing ALL user data..."
    else
        echo "Uninstalling Grim (preserving config and plugins)"
        echo "Use --purge to remove everything"
    fi
    echo ""

    uninstall_grim "$1"

    echo ""
    echo -e "${GREEN}Grim uninstalled!${NC}"
}

main "$@"
