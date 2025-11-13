{ config, pkgs, lib, ... }:

{
  ########################################
  # Base system
  ########################################
  system.stateVersion = "24.11";

  ########################################
  # Networking - static IPv4 on enu1u1
  ########################################
  networking = {
    hostName = "rpi3";

    useNetworkd = true;
    useDHCP = false;

    interfaces.enu1u1 = {
      useDHCP = false;
      ipv4.addresses = [{
        address = "192.168.1.150";  # Pi IP
        prefixLength = 24;          # 255.255.255.0
      }];
    };

    defaultGateway = {
      address = "192.168.1.1";     # router IP
      interface = "enu1u1";
    };

    nameservers = [ "1.1.1.1" "8.8.8.8" ];
  };

  ########################################
  # User + SSH
  ########################################
  services.openssh.enable = true;

  users.users.tochi = {
    isNormalUser = true;
    initialPassword = "tochi";
    extraGroups = [ "wheel" "networkmanager" ];
  };

  services.getty.autologinUser = "tochi";
  security.sudo.wheelNeedsPassword = false;

  ########################################
  # Basic tools
  ########################################
  environment.systemPackages = with pkgs; [
    vim
    curl
    wget
    git
  ];

  ########################################
  # ZFS: force disabled
  ########################################
  boot.supportedFilesystems.zfs = lib.mkForce false;

  ########################################
  # NOTE: Copyparty will be installed on the Pi
  # after boot, not baked from nixpkgs.
  ########################################
}
