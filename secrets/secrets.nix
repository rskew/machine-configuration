let
  rowan = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIGLH6ekjtL25VOasfI17RRNORxUG2aJxnPSfcGp0xrFF rowan@rowan-p14";
  vpsManagement = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIMP6vikXvdj0wt9/WFCceeOPwimT1LqQcEItLXPTq7ye rowan@rowan-yoga-260-keenbean";
  idToDeployToServers = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAINyNsCdnk/Q9H9OWakN0llCHbgb4RTB0f2na54XEy6FW rowan@rowan-p14";
in
{
  "coolroom-monitor-influxdb-password.age".publicKeys = [ rowan vpsManagement idToDeployToServers ];
  "autofarm-frontend-server-basic-auth-credentials.age".publicKeys = [ rowan vpsManagement idToDeployToServers ];
  "farmdb-pgpassword.age".publicKeys = [ rowan vpsManagement idToDeployToServers ];
  "namecheap-api-credentials.age".publicKeys = [ rowan vpsManagement idToDeployToServers ];
  "restic-password.age".publicKeys = [ rowan vpsManagement idToDeployToServers ];
  "b2-credentials.age".publicKeys = [ rowan vpsManagement idToDeployToServers ];
  "pgbackrest-cipher-pass.age".publicKeys = [ rowan vpsManagement idToDeployToServers ];
  "pgbackrest-credentials-env.age".publicKeys = [ rowan vpsManagement idToDeployToServers ];
  "farm-basic-auth.age".publicKeys = [ rowan vpsManagement idToDeployToServers ];
}
