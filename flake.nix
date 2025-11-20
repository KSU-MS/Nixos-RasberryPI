{
  description = "KSUMS: WSL + Raspberry Pi 3 + Copyparty + Static IPv4 + SSH + git + mcap-cli";

  nixConfig = {
    experimental-features = [ "nix-command" "flakes" ];
  };

  inputs = {
    nixpkgs.url   = "github:NixOS/nixpkgs/nixos-24.11";
    nixos-wsl.url = "github:nix-community/NixOS-WSL";
    copyparty.url = "github:9001/copyparty";
  };

  outputs = { self, nixpkgs, nixos-wsl, copyparty, ... }:
    let
      systemX86   = "x86_64-linux";
      systemAarch = "aarch64-linux";
      lib = nixpkgs.lib;
    in
    {

      ##############################
      ## NixOS CONFIGURATIONS
      ##############################

      nixosConfigurations = {

        ###########################
        ## WSL HOST
        ###########################
        wsl = lib.nixosSystem {
          system = systemX86;
          modules = [
            nixos-wsl.nixosModules.default
            copyparty.nixosModules.default
            ({ config, pkgs, ... }: {

              nixpkgs.overlays = [ copyparty.overlays.default ];

              networking.hostName = "nixos-wsl";
              time.timeZone = "America/New_York";

              wsl.enable = true;
              wsl.defaultUser = "tochi";

              nix.settings.experimental-features = [ "nix-command" "flakes" ];
              boot.binfmt.emulatedSystems = [ "aarch64-linux" ];

              users.users.tochi = {
                isNormalUser = true;
                home = "/home/tochi";
                extraGroups = [ "wheel" "networkmanager" ];
              };

              security.sudo.wheelNeedsPassword = false;

              environment.systemPackages = with pkgs; [
                git
                mcap-cli
                copyparty
                vim
                wget
              ];

              systemd.tmpfiles.rules = [
                "d /srv/copyparty 0755 tochi users -"
              ];

              services.copyparty = {
                enable = true;
                user   = "tochi";
                group  = "users";
                settings = {
                  i = "127.0.0.1";  # WSL: only localhost
                  p = [ 3923 ];
                  no-reload = true;
                };
                volumes."/" = {
                  path = "/srv/copyparty";
                  access = { r = "*"; rw = [ "*" ]; };
                };
                openFilesLimit = 8192;
              };

              system.stateVersion = "24.11";
            })
          ];
        };

        ###########################
        ## RASPBERRY PI 3
        ###########################
        rpi3 = lib.nixosSystem {
          system = systemAarch;
          modules = [
            "${nixpkgs}/nixos/modules/installer/sd-card/sd-image-aarch64.nix"
            copyparty.nixosModules.default
            ({ config, pkgs, ... }: {

              nixpkgs.overlays = [ copyparty.overlays.default ];

              networking.hostName = "rpi3";
              i18n.defaultLocale = "en_US.UTF-8";
              time.timeZone = "America/New_York";

              nix.settings.experimental-features = [ "nix-command" "flakes" ];

              #########################################
              ## SIMPLE STATIC IPv4 ON enu1u1
              #########################################
              networking.useNetworkd = false;   # use classic scripts instead of networkd
              networking.useDHCP = false;

              networking.interfaces.enu1u1 = {
                useDHCP = false;
                ipv4.addresses = [
                  {
                    address = "192.168.1.50";
                    prefixLength = 24;
                  }
                ];
              };

              networking.defaultGateway = "192.168.1.1";
              networking.nameservers   = [ "1.1.1.1" "8.8.8.8" ];

              networking.firewall = {
                enable = true;
                allowedTCPPorts = [ 22 3923 ];
              };

              #########################################
              ## USERS + SSH
              #########################################
              users.users.tochi = {
                isNormalUser = true;
                home = "/home/tochi";
                extraGroups = [ "wheel" "networkmanager" ];
                initialPassword = "changeme";  # change after first login
              };

              security.sudo.wheelNeedsPassword = false;

              services.openssh.enable = true;
              services.openssh.settings = {
                PasswordAuthentication = true;
                PermitRootLogin = "no";
              };

              services.getty.autologinUser = "tochi";

              #########################################
              ## PACKAGES + COPYPARTY CONFIG
              #########################################
              environment.systemPackages = with pkgs; [
                git
                mcap-cli
                copyparty
                vim
              ];

              systemd.tmpfiles.rules = [
                "d /srv/copyparty 0755 tochi users -"
              ];

              services.copyparty = {
                enable = true;
                user   = "tochi";
                group  = "users";
                settings = {
                  i = "0.0.0.0";  # Pi: all interfaces
                  p = [ 3923 ];
                  no-reload = true;
                };
                volumes."/" = {
                  path = "/srv/copyparty";
                  access = { r = "*"; rw = [ "*" ]; };
                };
                openFilesLimit = 8192;
              };

              #########################################
              ## BOOTLOADER
              #########################################
              boot.loader.grub.enable = false;
              boot.loader.generic-extlinux-compatible.enable = true;

              system.stateVersion = "24.11";
            })
          ];
        };
      };

      #########################################
      ## IMAGE OUTPUTS
      #########################################

      packages.${systemAarch}.rpi3-sdImage =
        self.nixosConfigurations.rpi3.config.system.build.sdImage;

      packages.${systemX86}.rpi3-sdImage =
        self.nixosConfigurations.rpi3.config.system.build.sdImage;

      defaultPackage.${systemX86} =
        self.packages.${systemX86}.rpi3-sdImage;
    };
}
