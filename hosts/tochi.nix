{ config, pkgs, ... }:

{
  networking.hostName = "tochi";
  time.timeZone = "America/New_York";

  # ✅ Enable flakes + new nix CLI
  nix = {
    package = pkgs.nixVersions.stable;
    settings.experimental-features = [ "nix-command" "flakes" ];
    settings.auto-optimise-store = true;
  };

  networking.firewall.enable = true;
  system.stateVersion = "24.11";
}
