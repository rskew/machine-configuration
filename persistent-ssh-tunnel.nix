#{ local-port,
#  local-ip ? "localhost",
#  remote-port,
#  remote-ip,
#  remote-user,
#  id-file,
#  known-hosts-line,
#  pkgs,
#}:
#
#let
#  known-hosts-file = pkgs.writeText "known_hosts" known-hosts-line;
#in
#
#{
#  description = "Persistant SSH tunnel. The id-file must not require a password.";
#  after = [ "network-pre.target" ];
#  wants = [ "network-pre.target" ];
#  wantedBy = [ "multi-user.target" ];
#  serviceConfig = {
#    Environment = "\"AUTOSSH_GATETIME=0\"";
#    ExecStart = ''
#      ${pkgs.autossh}/bin/autossh -M 0 \
#        -o "ExitOnForwardFailure yes" \
#        -o "ServerAliveInterval 30" \
#        -o "ServerAliveCountMax 3" \
#        -o "UserKnownHostsFile ${known-hosts-file}" \
#        -o "StrictHostKeyChecking yes" \
#        -i ${id-file} \
#        -R 127.0.0.1:${remote-port}:${local-ip}:${local-port} \
#        -N \
#        ${remote-user}@${remote-ip}
#    '';
#    Restart = "always";
#    RestartSec = 3;
#  };
#}

{ pkgs, lib, config }:
let
  cfg = config.services.persistentSSHTunnel;
in {
  options.services.persistentSSHTunnel = {
    enable = lib.mkEnableOption (lib.mdDoc "Nginx Web Server");
    remoteIp = mkOption {
      type = bool;
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
    remoteForwards = mkOption {
      type = with types; listOf (submodule { options = {
        localIp = mkOption { type = str;  description = lib.mdDoc "IP local to this machine.";  default = "localhost" };
        localPort = mkOption { type = port;  description = lib.mdDoc "Port number."; };
        remotePort = mkOption { type = port;  description = lib.mdDoc "Port number."; };
      }; });
      default = [];
      example = [
        { localPort = "22"; remotePort = 20022; }
      ];
    };
  };
  config =
   let
     knownHostsFile = pkgs.writeText "known_hosts" knownHostsLine;
     remoteForwardLines = concatStringsSep " " (map
       ({ remotePort, localIp, localPort }: "-R 127.0.0.1:${remotePort}:${localIp}:${localPort}")
       cfg.remoteForwards);
   in {
     systemd.services."${persistentSSHTunnel}-${cfg.remoteIp}" = lib.mkIf cfg.enable {
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
             -o "UserKnownHostsFile ${cfg.knownHostsFile}" \
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
};
