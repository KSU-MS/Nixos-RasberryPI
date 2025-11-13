{
  description = "KSU flake with PC + Raspberry Pi 3B+";

  ############################
  # Inputs
  ############################
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-24.11";
  };

  ############################
  # Outputs
  ############################
  outputs = { self, nixpkgs, ... }:
  let
    lib = nixpkgs.lib;
  in {
    ############################
    # NixOS Configurations
    ############################
    nixosConfigurations = {
      # Your main x86_64 NixOS (laptop/PC)
      tochi = lib.nixosSystem {
        system = "x86_64-linux";
        modules = [
          ./hosts/tochi.nix

          # Enable ARM (aarch64) emulation via binfmt/qemu
          ({ config, pkgs, lib, ... }: {
            boot.binfmt.emulatedSystems = [ "aarch64-linux" ];
          })
        ];
      };

      # Raspberry Pi 3B+ system
      rpi3 = lib.nixosSystem {
        system = "aarch64-linux";
        modules = [
          # Provides system.build.sdImage for aarch64
          "${nixpkgs}/nixos/modules/installer/sd-card/sd-image-aarch64.nix"

          # Your Pi config (static IP, user, etc.)
          ./hosts/rpi3.nix
        ];
      };
    };

    ############################
    # Raspberry Pi SD Image
    ############################
    packages.x86_64-linux.rpi3-sdImage =
      self.nixosConfigurations.rpi3.config.system.build.sdImage;
  };
}
