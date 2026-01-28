# KSUMS - KSU Motorsports Data Acquisition System

NixOS-based data offload and backup system for Raspberry Pi 3, designed for the Kennesaw State University Motorsports team.

## Features

- **MCAP Data Recovery**: Web API for recovering corrupted MCAP log files using `mcap-cli`
- **Deduplicated Backups**: Hash-based deduplication to save storage space
- **Static IP Networking**: Pre-configured for `192.168.1.50`
- **Auto-start Services**: All services start on boot via systemd
- **Headless Operation**: Designed for embedded use in the car

## Quick Start (Building on Arch Linux)

### Prerequisites

1. Install Nix on your Arch system:
```bash
sh <(curl -L https://nixos.org/nix/install) --daemon
```

2. Enable flakes (add to `~/.config/nix/nix.conf` or `/etc/nix/nix.conf`):
```
experimental-features = nix-command flakes
```

3. For cross-compilation to aarch64, enable binfmt:
```bash
# Install qemu-user-static from AUR
yay -S qemu-user-static-binfmt

# Or use the Nix-provided binfmt
# (requires NixOS or additional setup)
```

### Building the SD Image

**Option 1: Build on a Raspberry Pi or aarch64 machine**
```bash
nix build .#nixosConfigurations.ksums-pi.config.system.build.sdImage
```

**Option 2: Cross-compile from x86_64 (requires binfmt setup)**
```bash
# First, make sure binfmt is set up for aarch64
nix build .#nixosConfigurations.ksums-pi.config.system.build.sdImage --system aarch64-linux
```

**Option 3: Use a pre-built NixOS aarch64 installer, then deploy**

1. Download the official NixOS aarch64 SD image
2. Boot it on the Pi
3. Clone this repo and run:
```bash
sudo nixos-rebuild switch --flake .#ksums-pi
```

### Flashing the SD Card

```bash
# Find your SD card device
lsblk

# Flash (replace /dev/sdX with your device)
sudo dd if=result/sd-image/ksums-pi3.img of=/dev/sdX bs=4M status=progress
sync
```

## Usage

### Default Credentials

- **User**: `nixos`
- **Password**: `ksums`
- **SSH**: Enabled on port 22
- **Static IP**: `192.168.1.50`

**⚠️ Change these immediately after first boot!**

### Services

| Service | Port | Description |
|---------|------|-------------|
| `ksums-backend` | 8000 | Django REST API for MCAP recovery |
| `copyparty` | 3923 | CopyParty deduplicated backup server |
| `ksums-backup.timer` | - | Periodic backup (every 30 min) |
| `sshd` | 22 | Remote access |

### URLs

```bash
# Django API - List MCAP files
http://192.168.1.50:8000/api/files/

# Django API - Health check
http://192.168.1.50:8000/api/health/

# CopyParty Web UI - Browse recordings (read-only)
http://192.168.1.50:3923/recordings/

# CopyParty Web UI - Backup folder (read-write, deduplicated)
http://192.168.1.50:3923/backup/
```

### Managing Services

```bash
# Check service status
sudo systemctl status ksums-backend
sudo systemctl status copyparty
sudo systemctl status ksums-backup.timer

# View logs
sudo journalctl -u ksums-backend -f
sudo journalctl -u copyparty -f

# Manual backup
sudo systemctl start ksums-backup

# Restart services
sudo systemctl restart ksums-backend
sudo systemctl restart copyparty
```

### CopyParty Usage

CopyParty provides a web interface for browsing and uploading MCAP files with automatic deduplication.

**Volumes:**
- `/recordings` - Read-only view of DAQ recordings
- `/backup` - Read-write backup with deduplication enabled

**Upload via curl:**
```bash
# Upload a file to the backup folder (will be deduplicated)
curl -T myfile.mcap http://192.168.1.50:3923/backup/
```

**One-way sync from DAQ:**
The recordings folder is read-only from CopyParty. Files are placed there by the DAQ system, then CopyParty's dedup engine handles backup storage efficiently.

### Django API Endpoints

```bash
# List available MCAP files
curl http://192.168.1.50:8000/api/files/

# Health check  
curl http://192.168.1.50:8000/api/health/

# Recover corrupted files (returns ZIP)
curl -X POST http://192.168.1.50:8000/api/recover-and-zip/ \
  -H "Content-Type: application/json" \
  -d '{"files": ["log1.mcap", "log2.mcap"]}' \
  --output recovered.zip
```

### File Locations

| Path | Description |
|------|-------------|
| `/var/lib/ksums/recordings` | MCAP files from DAQ (source) |
| `/var/lib/ksums/backup` | Deduplicated backup storage |
| `/var/lib/ksums/backup/.dedup` | Dedup hash store |

## Development

### Enter dev shell
```bash
nix develop
```

### Run backend locally
```bash
cd backend
export BASE_DIR=/path/to/mcap/files
python manage.py runserver 0.0.0.0:8000
```

### Build just the backend package
```bash
nix build .#ksums-data-offload
./result/bin/ksums-backend
```

## Architecture

```
┌─────────────────────────────────────────────────────────┐
│                    Raspberry Pi 3                        │
│  ┌─────────────────────────────────────────────────┐    │
│  │                  NixOS 24.05                     │    │
│  │  ┌─────────────────┐  ┌────────────────────┐   │    │
│  │  │  ksums-backend  │  │   ksums-backup     │   │    │
│  │  │  (Django/DRF)   │  │   (systemd timer)  │   │    │
│  │  │    :8000        │  │                    │   │    │
│  │  └────────┬────────┘  └─────────┬──────────┘   │    │
│  │           │                     │              │    │
│  │           ▼                     ▼              │    │
│  │  ┌─────────────────────────────────────────┐   │    │
│  │  │         /var/lib/ksums/                 │   │    │
│  │  │  recordings/  ←──  DAQ MCAP files       │   │    │
│  │  │  backup/      ←──  Dedup'd copies       │   │    │
│  │  └─────────────────────────────────────────┘   │    │
│  └─────────────────────────────────────────────────┘    │
│                         │                               │
│                    eth0 │ 192.168.1.50                  │
└─────────────────────────┼───────────────────────────────┘
                          │
                          ▼
              ┌───────────────────────┐
              │   Laptop / Browser    │
              │   http://192.168.1.50 │
              └───────────────────────┘
```

## Customization

Edit `flake.nix` to change:

```nix
services.ksums = {
  enable = true;
  recordingsDir = "/var/lib/ksums/recordings";  # MCAP source
  backupDir = "/var/lib/ksums/backup";          # Backup dest
  staticIP = "192.168.1.50";                    # Pi IP address
  gateway = "192.168.1.1";                      # Router IP
  interface = "eth0";                           # Network interface
};
```

## Troubleshooting

### Pi won't boot
- Check SD card is properly flashed
- Verify power supply (5V 2.5A recommended)
- Check serial console for boot messages

### Can't reach API
```bash
# On the Pi
ip addr show eth0
sudo systemctl status ksums-backend
sudo journalctl -u ksums-backend --no-pager
```

### MCAP recovery fails
```bash
# Check mcap-cli is available
which mcap
mcap version

# Check file permissions
ls -la /var/lib/ksums/recordings/
```

### Backup not running
```bash
sudo systemctl list-timers
sudo systemctl status ksums-backup.timer
sudo journalctl -u ksums-backup
```

## License

MIT - KSU Motorsports Team

## Author

Created by [pkonnoth](https://github.com/pkonnoth)
