{ pkgs, lib, config, ... }:
let
  cfg = config.services.persistentSSHTunnel;
in {
  options.services.persistentSSHTunnel = {
    enable = lib.mkEnableOption (lib.mdDoc "Nginx Web Server");
    remoteIp = lib.mkOption {
      type = lib.types.str;
      description = lib.mdDoc "IP address of remote host.";
    };
    remoteUser = lib.mkOption {
      type = lib.types.str;
      description = "User on remote host";
    };
    idFile = lib.mkOption {
      type = lib.types.str;
      description = "Identity file to use with SSH";
    };
    knownHostsLine = lib.mkOption {
      type = lib.types.str;
      description = "Line to put in the known_hosts file so the remote server is recognized";
    };
    remoteForwards = lib.mkOption {
      type = with lib.types; listOf (submodule { options = {
        localIp = lib.mkOption { type = str;  description = lib.mdDoc "IP local to this machine.";  default = "localhost"; };
        localPort = lib.mkOption { type = port;  description = lib.mdDoc "Port number."; };
        remotePort = lib.mkOption { type = port;  description = lib.mdDoc "Port number."; };
      }; });
      default = [];
      example = [
        { localPort = "22"; remotePort = 20022; }
      ];
    };
  };
  config =
   let
     knownHostsFile = pkgs.writeText "known_hosts" cfg.knownHostsLine;
     remoteForwardLines = lib.concatStrings (map
       ({ remotePort, localIp, localPort }: " -R 127.0.0.1:${toString(remotePort)}:${localIp}:${toString(localPort)} ")
       cfg.remoteForwards);
   in {
     systemd.services."persistentSSHTunnel-${cfg.remoteIp}" = lib.mkIf cfg.enable {
       description = "Persistant SSH tunnel. The id-file must not require a password.";
       after = [ "network-pre.target" ];
       wants = [ "network-pre.target" ];
       wantedBy = [ "multi-user.target" ];
       serviceConfig = {
         Environment = "\"AUTOSSH_GATETIME=0\"";
         ExecStart = ''
           ${pkgs.autossh}/bin/autossh -M 0 \
             -o "ExitOnForwardFailure yes" \
             -o "ServerAliveInterval 30" \
             -o "ServerAliveCountMax 3" \
             -o "UserKnownHostsFile ${knownHostsFile}" \
             -o "StrictHostKeyChecking yes" \
             -i ${cfg.idFile} \
         '' + remoteForwardLines + ''
             -N \
             ${cfg.remoteUser}@${cfg.remoteIp}
         '';
         Restart = "always";
         RestartSec = 3;
       };
     };
   };
}
