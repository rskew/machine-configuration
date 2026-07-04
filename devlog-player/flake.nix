{
  description = "devlog-player: scrub a day's work across asciinema, ActivityWatch, and Claude Code sessions on one timeline";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs = { self, nixpkgs }:
    let
      system = "x86_64-linux";
      pkgs = import nixpkgs { inherit system; };

      # Runtime libs that winit/wgpu dlopen at startup. /run/opengl-driver/lib
      # is where NixOS exposes the vulkan ICDs at run time.
      runtimeLibs = with pkgs; [
        wayland
        libxkbcommon
        vulkan-loader
        libGL
      ];
      libPath = pkgs.lib.makeLibraryPath runtimeLibs;
      runtimePath = "${libPath}:/run/opengl-driver/lib";

      src = pkgs.lib.cleanSourceWith {
        src = ./.;
        filter = path: _type:
          let p = toString path; in
          !(pkgs.lib.hasSuffix "/target" p)
          && !(pkgs.lib.hasInfix "/target/" p)
          && !(pkgs.lib.hasSuffix "/result" p);
      };

      devlog-player = pkgs.rustPlatform.buildRustPackage {
        pname = "devlog-player";
        version = "0.1.0";
        inherit src;
        cargoLock.lockFile = ./Cargo.lock;

        nativeBuildInputs = [ pkgs.pkg-config pkgs.makeWrapper ];

        # The `harness` feature pulls in `gui` (eframe) and egui_kittest so the
        # one derivation produces both the player and the visual harness.
        buildFeatures = [ "harness" ];
        cargoBuildFlags = [ "--bin" "devlog-player" "--bin" "harness" ];
        doCheck = false;

        # Wrap both binaries with LD_LIBRARY_PATH so winit/wgpu find their libs.
        postFixup = ''
          for b in devlog-player harness; do
            wrapProgram $out/bin/$b \
              --suffix LD_LIBRARY_PATH : "${runtimePath}"
          done
        '';

        meta.mainProgram = "devlog-player";
      };
    in
    {
      packages.${system} = {
        default = devlog-player;
        devlog-player = devlog-player;
      };

      apps.${system}.default = {
        type = "app";
        program = "${devlog-player}/bin/devlog-player";
      };

      # `nix develop` — cargo + rustc + the runtime libs all on PATH and
      # LD_LIBRARY_PATH, so `cargo run --features harness --bin harness` just
      # works (fast iteration vs `nix build`).
      devShells.${system}.default = pkgs.mkShell {
        packages = with pkgs; [ cargo rustc gcc pkg-config ];
        shellHook = ''
          export LD_LIBRARY_PATH="${runtimePath}''${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
        '';
      };
    };
}
