let
  rowan1 = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIFfBc65tSs79GyOkzztEiH08QIJgoTUmTQAmX3oCz6oC rowan@rowan-p14";
  vps-management = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIMP6vikXvdj0wt9/WFCceeOPwimT1LqQcEItLXPTq7ye rowan@rowan-yoga-260-keenbean";
  id-to-deploy-to-servers = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAINyNsCdnk/Q9H9OWakN0llCHbgb4RTB0f2na54XEy6FW rowan@rowan-p14";
in
{
  "coolroom-monitor-relay-sys.config.age".publicKeys = [ vps-management id-to-deploy-to-servers ];
}
