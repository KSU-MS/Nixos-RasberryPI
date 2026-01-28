#!/usr/bin/env bash
# KSUMS Build Script for Arch Linux
# Builds the Raspberry Pi 3 SD image

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}"
echo "╔═══════════════════════════════════════════════════════════╗"
echo "║           KSUMS - Raspberry Pi 3 Build Script             ║"
echo "║        KSU Motorsports Data Acquisition System            ║"
echo "╚═══════════════════════════════════════════════════════════╝"
echo -e "${NC}"

# Check for nix
if ! command -v nix &> /dev/null; then
    echo -e "${RED}Error: Nix is not installed${NC}"
    echo "Install with: sh <(curl -L https://nixos.org/nix/install) --daemon"
    exit 1
fi

# Check for flakes
if ! nix --version | grep -q "nix (Nix)"; then
    echo -e "${YELLOW}Warning: Make sure flakes are enabled in your nix config${NC}"
    echo "Add to ~/.config/nix/nix.conf:"
    echo "  experimental-features = nix-command flakes"
fi

echo ""
echo "Choose build method:"
echo "  1) Build backend package only (x86_64)"
echo "  2) Build SD image (requires aarch64 or binfmt)"
echo "  3) Enter development shell"
echo "  4) Deploy to running Pi via SSH"
echo ""
read -p "Selection [1-4]: " choice

case $choice in
    1)
        echo -e "${GREEN}Building backend package...${NC}"
        nix build .#ksums-data-offload
        echo -e "${GREEN}Done! Package at: ./result${NC}"
        echo "Run with: ./result/bin/ksums-backend"
        ;;
    2)
        echo -e "${YELLOW}Building SD image for Raspberry Pi 3...${NC}"
        echo "This requires either:"
        echo "  - Running on aarch64 hardware"
        echo "  - binfmt-qemu setup for aarch64 emulation"
        echo ""
        read -p "Continue? [y/N] " confirm
        if [[ $confirm =~ ^[Yy]$ ]]; then
            # Check for binfmt
            if [[ -f /proc/sys/fs/binfmt_misc/aarch64 ]]; then
                echo -e "${GREEN}binfmt detected, building...${NC}"
            else
                echo -e "${YELLOW}Warning: binfmt not detected. Build may fail.${NC}"
                echo "On Arch, install: yay -S qemu-user-static-binfmt"
            fi
            
            nix build .#nixosConfigurations.ksums-pi.config.system.build.sdImage \
                --system aarch64-linux \
                -L
            
            echo -e "${GREEN}Done! SD image at:${NC}"
            ls -lh result/sd-image/
            echo ""
            echo "Flash with:"
            echo "  sudo dd if=result/sd-image/*.img of=/dev/sdX bs=4M status=progress"
        fi
        ;;
    3)
        echo -e "${GREEN}Entering development shell...${NC}"
        nix develop
        ;;
    4)
        read -p "Pi IP address [192.168.1.50]: " PI_IP
        PI_IP=${PI_IP:-192.168.1.50}
        
        echo -e "${GREEN}Deploying to $PI_IP...${NC}"
        echo "This will:"
        echo "  1. Copy the flake to the Pi"
        echo "  2. Rebuild NixOS on the Pi"
        echo ""
        
        # Copy flake
        rsync -avz --exclude='.git' --exclude='result' ./ nixos@$PI_IP:~/KSUMS/
        
        # Rebuild on Pi
        ssh nixos@$PI_IP "cd ~/KSUMS && sudo nixos-rebuild switch --flake .#ksums-pi"
        
        echo -e "${GREEN}Deployment complete!${NC}"
        ;;
    *)
        echo "Invalid selection"
        exit 1
        ;;
esac
