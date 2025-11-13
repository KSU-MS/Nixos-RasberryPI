{ config, pkgs, lib, ... }:

let
  cfg = config.services.copyParty;
  copyPartyPkg = pkgs.python3Packages.copy_party;
in
{
  options.services.copyParty = {
    enable = lib.mkEnableOption "CopyParty file server";

    dataDir = lib.mkOption {
      type = lib.types.path;
      default = "/srv/copyParty";
    };

    listenPort = lib.mkOption {
      type = lib.types.int;
      default = 3923;
    };
  };

  config = lib.mkIf cfg.enable {
    users.users.copyparty = {
      isSystemUser = true;
      group = "copyparty";
      home = cfg.dataDir;
      createHome = true;
    };

    users.groups.copyparty = {};

    systemd.services.copyparty = {
      description = "CopyParty file server";
      wantedBy = [ "multi-user.target" ];
      after = [ "network.target" ];

      serviceConfig = {
        User = "copyparty";
        Group = "copyparty";
        WorkingDirectory = cfg.dataDir;

        ExecStart = "${copyPartyPkg}/bin/copyparty -a 0.0.0.0:${toString cfg.listenPort} .";
        Restart = "on-failure";
      };
    };

    environment.systemPackages = [ copyPartyPkg ];
  };
}
