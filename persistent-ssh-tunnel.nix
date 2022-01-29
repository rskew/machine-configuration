{ local-port,
  remote-port,
  remote-ip,
  remote-user,
  id-file,
  known-hosts-line,
  pkgs,
}:

let
  known-hosts-file = pkgs.writeText "known_hosts" known-hosts-line;
in

{
  description = ''
    Persistant SSH tunnel.
    The id-file must not require a password.
  '';
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
        -o "UserKnownHostsFile ${known-hosts-file}" \
        -o "StrictHostKeyChecking yes" \
        -i ${id-file} \
        -R 127.0.0.1:${remote-port}:localhost:${local-port} \
        -N \
        ${remote-user}@${remote-ip}
    '';
    Restart = "always";
    RestartSec = 3;
  };
}
