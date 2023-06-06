{ pkgs, device_path }: rec {
  nodeDependencies = (pkgs.callPackage ./node-composition.nix {}).shell.nodeDependencies;
  vedirect-serial-usb-repo = pkgs.fetchFromGitHub {
    owner = "SignalK";
    repo = "vedirect-serial-usb";
    rev = "55e26734b913ca2021b9f30cac479062c0a3922b";
    sha256 = "sha256-xs27SXLqYb7bZkKGLhH4bq18t6ZBxrl599fY7DdGKns=";
  };
  node-modules-with-vedirect-serial-usb = pkgs.runCommand "node-modules-with-vedirect-serial-usb" {} ''
    mkdir -p $out/@signalk
    ln -s ${vedirect-serial-usb-repo} $out/@signalk/vedirect-serial-usb
  '';
  NODE_PATH = "${node-modules-with-vedirect-serial-usb}:${nodeDependencies}/lib/node_modules";
  script = pkgs.runCommand "index.js" {} ''
    cp ${./index.js} $out
    substituteInPlace $out --replace "DEVICE_PLACEHOLDER" ${device_path}
  '';
  package = pkgs.writeShellApplication {
    name = "shed-power-monitor";
    runtimeInputs = [ pkgs.nodejs pkgs.nodePackages.node2nix nodeDependencies ];
    text = "NODE_PATH=${NODE_PATH} ${pkgs.nodejs}/bin/node ${script}";
  };
  module = ({pkgs, ...}: {
    systemd.services.shed-power-monitor = {
      description = "Log shed power readings to influxdb";
      wantedBy = [ "multi-user.target" ];
      path = [ package ];
      script = "shed-power-monitor";
      serviceConfig = {
        Restart = "always";
        RestartSec = "1s";
      };
    };
  });
}
