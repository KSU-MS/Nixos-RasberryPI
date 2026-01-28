{
  description = "KSUMS: Raspberry Pi 3 + CopyParty + Data Offload + Mumble + PipeWire + Foxglove";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-24.11";
    copyparty.url = "github:9001/copyparty";
    data-offload-app = {
      url = "github:KSU-MS/data_offload_app";
      flake = false;
    };
  };

  outputs = { self, nixpkgs, copyparty, data-offload-app, ... }@inputs:
    let
      lib = nixpkgs.lib;

      # Create patched source with Google Fonts removed and logo size fixed
      mkPatchedSource = pkgs: pkgs.runCommand "data-offload-app-patched" {} ''
        cp -r ${data-offload-app} $out
        chmod -R u+w $out

        # Patch layout.js to remove Google Fonts import
        cat > $out/src/app/layout.js << 'EOF'
import "./globals.css";

export const metadata = {
  title: "Data Offload App",
  description: "Utility for offloading data",
};

export default function RootLayout({ children }) {
  return (
    <html lang="en">
      <body className="font-sans antialiased">
        {children}
      </body>
    </html>
  );
}
EOF

        # Patch globals.css with system fonts
        cat > $out/src/app/globals.css << 'EOF'
@tailwind base;
@tailwind components;
@tailwind utilities;

body {
  font-family: ui-sans-serif, system-ui, -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, "Helvetica Neue", Arial, sans-serif;
}
EOF

        # Patch page.js to fix logo size (change h-96 to h-32)
        sed -i 's/className="h-96 w-auto"/className="h-32 w-auto"/g' $out/src/app/page.js

        # Patch next.config.mjs to disable image optimization (avoids cache write issues)
        cat > $out/next.config.mjs << 'EOF'
/** @type {import('next').NextConfig} */
const nextConfig = {
  images: {
    unoptimized: true,
  },
};

export default nextConfig;
EOF
      '';

      # Create patched backend source with writable database path
      mkPatchedBackend = pkgs: pkgs.runCommand "data-offload-backend-patched" {} ''
        cp -r ${data-offload-app}/backend $out
        chmod -R u+w $out

        # Patch settings.py to use environment variable for database path
        sed -i "s|'NAME': BASE_DIR / 'db.sqlite3'|'NAME': os.environ.get('DB_PATH', '/srv/ksums/db/db.sqlite3')|g" $out/config/settings.py
      '';

      # Build the frontend from patched source
      mkFrontend = pkgs: 
        let
          patchedSrc = mkPatchedSource pkgs;
        in pkgs.buildNpmPackage {
          pname = "data_offload_app_frontend";
          version = "0.1.0";
          src = patchedSrc;

          npmDepsHash = "sha256-l7Rk2R7DJCOcpH3JXfvHCTCorJ7Jp4qCc4yb+y3mG7g=";

          buildPhase = ''
            export NEXT_TELEMETRY_DISABLED=1
            export NEXT_PUBLIC_API_URL=http://192.168.1.50:8000
            npm run build
          '';

          installPhase = ''
            mkdir -p $out/app
            cp -r .next public package.json node_modules $out/app

            # Create a proper start script with absolute paths
            mkdir -p $out/bin
            cat > $out/bin/start-frontend << EOF
#!${pkgs.bash}/bin/bash
export NODE_ENV=production
export PORT=\''${PORT:-3000}
export HOSTNAME=\''${HOSTNAME:-0.0.0.0}
cd $out/app
exec ${pkgs.nodejs}/bin/node node_modules/next/dist/bin/next start -H \$HOSTNAME -p \$PORT
EOF
            chmod +x $out/bin/start-frontend
          '';
        };

      # Build the backend
      mkBackend = pkgs: 
        let
          patchedBackend = mkPatchedBackend pkgs;
        in pkgs.stdenv.mkDerivation {
        name = "data_offload_app_backend";
        src = patchedBackend;
        buildInputs = [ pkgs.python3 pkgs.makeWrapper ];
        installPhase = ''
          mkdir -p $out/app
          cp -r . $out/app

          makeWrapper ${pkgs.python3}/bin/python $out/bin/data-offload-backend \
            --add-flags "$out/app/manage.py runserver 0.0.0.0:8000" \
            --prefix PYTHONPATH : "$out/app" \
            --prefix PYTHONPATH : "${pkgs.python3Packages.django}/${pkgs.python3.sitePackages}" \
            --prefix PYTHONPATH : "${pkgs.python3Packages.djangorestframework}/${pkgs.python3.sitePackages}" \
            --prefix PYTHONPATH : "${pkgs.python3Packages.django-cors-headers}/${pkgs.python3.sitePackages}" \
            --prefix PYTHONPATH : "${pkgs.python3Packages.asgiref}/${pkgs.python3.sitePackages}" \
            --prefix PYTHONPATH : "${pkgs.python3Packages.sqlparse}/${pkgs.python3.sitePackages}" \
            --prefix PYTHONPATH : "${pkgs.python3Packages.typing-extensions}/${pkgs.python3.sitePackages}"
        '';
      };

      # Overlay to provide packages
      overlay = final: prev: {
        data_offload_app_frontend = mkFrontend final;
        data_offload_app_backend = mkBackend final;
      };

    in {
      nixosConfigurations.rpi3 = lib.nixosSystem {
        system = "aarch64-linux";
        modules = [
          "${nixpkgs}/nixos/modules/installer/sd-card/sd-image-aarch64.nix"
          copyparty.nixosModules.default

          ({ config, pkgs, lib, ... }: {
            nixpkgs.overlays = [
              copyparty.overlays.default
              overlay
            ];

            # Boot settings
            boot.loader.grub.enable = false;
            boot.loader.generic-extlinux-compatible.enable = true;
            hardware.enableRedistributableFirmware = true;

            # SD image settings
            sdImage.compressImage = true;

            networking.hostName = "ksums-pi";
            i18n.defaultLocale = "en_US.UTF-8";
            time.timeZone = "America/New_York";

            nix.settings.experimental-features = [ "nix-command" "flakes" ];

            #########################################
            ## STATIC IPv4
            #########################################
            networking.useNetworkd = false;
            networking.useDHCP = false;

            networking.interfaces.enu1u1 = {
              useDHCP = false;
              ipv4.addresses = [{
                address = "192.168.1.50";
                prefixLength = 24;
              }];
            };

            networking.defaultGateway = "192.168.1.1";
            networking.nameservers = [ "1.1.1.1" "8.8.8.8" ];

            networking.firewall = {
              enable = true;
              allowedTCPPorts = [ 
                22      # SSH
                3000    # Frontend (Next.js)
                3923    # CopyParty
                8000    # Backend API
                8765    # Foxglove WebSocket Bridge
                64738   # Mumble
              ];
              allowedUDPPorts = [
                64738   # Mumble voice
              ];
            };

            #########################################
            ## USERS + SSH
            #########################################
            users.users.tochi = {
              isNormalUser = true;
              home = "/home/tochi";
              extraGroups = [ "wheel" "networkmanager" "users" "audio" ];
              initialPassword = "changeme";
            };

            security.sudo.wheelNeedsPassword = false;

            services.openssh.enable = true;
            services.openssh.settings = {
              PasswordAuthentication = true;
              PermitRootLogin = "no";
            };

            services.getty.autologinUser = "tochi";

            #########################################
            ## DIRECTORIES
            #########################################
            systemd.tmpfiles.rules = [
              "d /srv/ksums 0755 tochi users -"
              "d /srv/ksums/recordings 0755 tochi users -"
              "d /srv/ksums/backup 0755 tochi users -"
              "d /srv/ksums/db 0755 tochi users -"
            ];

            #########################################
            ## PIPEWIRE - Low-latency audio
            #########################################
            security.rtkit.enable = true;
            services.pipewire = {
              enable = true;
              alsa.enable = true;
              pulse.enable = true;  # PulseAudio compatibility for Mumble
            };

            #########################################
            ## MUMBLE SERVER (Murmur)
            #########################################
            services.murmur = {
              enable = true;
              port = 64738;
              bandwidth = 72000;
              users = 10;
              registerName = "KSUMS Voice";
              welcometext = "Welcome to KSUMS Motorsports Voice Chat!";
              # No password - open access (set password = "yourpass"; for security)
            };

            #########################################
            ## FOXGLOVE WEBSOCKET BRIDGE
            ## Serves MCAP files over WebSocket for Foxglove Studio
            #########################################
            systemd.services.foxglove-bridge = {
              description = "Foxglove WebSocket Bridge for MCAP files";
              wantedBy = [ "multi-user.target" ];
              after = [ "network.target" ];
              
              serviceConfig = {
                Type = "simple";
                User = "tochi";
                Group = "users";
                Restart = "always";
                RestartSec = 5;
                ExecStart = "${pkgs.python3.withPackages (ps: [ ps.websockets ])}/bin/python3 -u ${pkgs.writeText "foxglove-server.py" ''
import asyncio
import websockets
import os
import json
import struct

MCAP_DIR = "/srv/ksums/recordings"

async def handler(websocket):
    print(f"Client connected: {websocket.remote_address}")
    try:
        async for message in websocket:
            try:
                data = json.loads(message)
                cmd = data.get("op", data.get("type", ""))
                
                if cmd == "list":
                    files = [f for f in os.listdir(MCAP_DIR) if f.endswith(".mcap")]
                    file_info = []
                    for f in files:
                        path = os.path.join(MCAP_DIR, f)
                        stat = os.stat(path)
                        file_info.append({"name": f, "size": stat.st_size})
                    await websocket.send(json.dumps({"op": "filelist", "files": file_info}))
                    
                elif cmd == "get":
                    filename = data.get("file", "")
                    filepath = os.path.join(MCAP_DIR, filename)
                    if os.path.exists(filepath) and filepath.startswith(MCAP_DIR) and filename.endswith(".mcap"):
                        with open(filepath, "rb") as f:
                            content = f.read()
                        await websocket.send(content)
                    else:
                        await websocket.send(json.dumps({"op": "error", "message": "File not found"}))
                        
            except json.JSONDecodeError:
                await websocket.send(json.dumps({"op": "error", "message": "Invalid JSON"}))
                
    except websockets.exceptions.ConnectionClosed:
        print(f"Client disconnected: {websocket.remote_address}")

async def main():
    print("Foxglove WebSocket Bridge starting on 0.0.0.0:8765")
    print(f"Serving MCAP files from: {MCAP_DIR}")
    async with websockets.serve(handler, "0.0.0.0", 8765):
        await asyncio.Future()

if __name__ == "__main__":
    asyncio.run(main())
''}";
              };
            };

            #########################################
            ## COPYPARTY - One-way dedup backup
            #########################################
            services.copyparty = {
              enable = true;
              user = "tochi";
              group = "users";
              settings = {
                i = "0.0.0.0";
                p = [ 3923 ];
                no-reload = true;
              };
              volumes = {
                "/recordings" = {
                  path = "/srv/ksums/recordings";
                  access = { r = "*"; };
                  flags = { e2d = true; };
                };
                "/backup" = {
                  path = "/srv/ksums/backup";
                  access = { r = "*"; rw = [ "*" ]; };
                  flags = { e2d = true; nodupe = true; };
                };
              };
              openFilesLimit = 8192;
            };

            #########################################
            ## DATA OFFLOAD BACKEND (Django)
            #########################################
            systemd.services.data_offload_backend = {
              description = "Data Offload Backend (Django)";
              wantedBy = [ "multi-user.target" ];
              after = [ "network.target" ];
              environment = {
                BASE_DIR = "/srv/ksums/recordings";
                DB_PATH = "/srv/ksums/db/db.sqlite3";
                DJANGO_SETTINGS_MODULE = "config.settings";
                PYTHONUNBUFFERED = "1";
              };
              path = [ pkgs.mcap-cli ];
              serviceConfig = {
                ExecStart = "${pkgs.data_offload_app_backend}/bin/data-offload-backend";
                WorkingDirectory = "/srv/ksums/db";
                Restart = "always";
                User = "tochi";
                Group = "users";
              };
            };

            #########################################
            ## DATA OFFLOAD FRONTEND (Next.js)
            #########################################
            systemd.services.data_offload_frontend = {
              description = "Data Offload Frontend (Next.js)";
              wantedBy = [ "multi-user.target" ];
              after = [ "network.target" "data_offload_backend.service" ];
              environment = {
                PORT = "3000";
                HOSTNAME = "0.0.0.0";
                NEXT_PUBLIC_API_URL = "http://192.168.1.50:8000";
              };
              serviceConfig = {
                ExecStart = "${pkgs.data_offload_app_frontend}/bin/start-frontend";
                Restart = "always";
                User = "tochi";
                Group = "users";
              };
            };

            #########################################
            ## PACKAGES
            #########################################
            environment.systemPackages = with pkgs; [
              git
              mcap-cli
              copyparty
              vim
              htop
              # Audio tools
              alsa-utils
              pamixer
              # Mumble CLI (for testing)
              mumble
            ];

            system.stateVersion = "24.11";
          })
        ];
      };

      images.rpi3 = self.nixosConfigurations.rpi3.config.system.build.sdImage;
    };
}
