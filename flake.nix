{
  description = "A WAD-backed Nix port targeting Doom 1.9 shareware, using nixray";
  inputs = {
    nixray.url = "github:flakesonnix/nixray/b4b6a26d1b7ac1d9d9963d294db9174f7a276087";
    nixpkgs.follows = "nixray/nixpkgs";
  };
  outputs = { self, nixray, nixpkgs }:
    let
      eachSystem = nixpkgs.lib.genAttrs [ "x86_64-linux" "aarch64-linux" ];
      forSystem = system:
        let
          pkgs = import nixpkgs { inherit system; };
          runtime = nixray.packages.${system}.default;
          iwad = pkgs.callPackage ./vanilla/iwad.nix {};
          original = import ./vanilla/assets.nix { inherit pkgs iwad; };
          doom = pkgs.writeShellApplication {
            name = "doom-nix";
            text = ''
              exec ${runtime}/bin/nixray ${self}/vanilla/doom.nix --arg ray 'import ${nixray}/lib' \
                --argstr iwad ${iwad} --argstr assets ${original.package} "$@"
            '';
            meta.description = "Play the Doom shareware maps with a Nix game engine";
          };
        in { inherit pkgs runtime doom iwad original; };
    in {
      packages = eachSystem (system: {
        default = (forSystem system).doom;
        doom-nix = (forSystem system).doom;
        iwad = (forSystem system).iwad;
        assets = (forSystem system).original.package;
      });
      apps = eachSystem (system: {
        default = { type = "app"; program = "${self.packages.${system}.default}/bin/doom-nix";
          meta.description = "DOOM / NIX"; };
      });
      checks = eachSystem (system:
        let inherit (forSystem system) pkgs runtime doom iwad original;
        in {
          logic = pkgs.runCommand "doom-nix-logic-tests" {
            nativeBuildInputs = [ runtime.nixComponents.nix-cli ];
          } ''
            export HOME="$TMPDIR"
            nix-instantiate --eval --strict --json ${self}/tests/vanilla.nix --argstr iwad ${iwad} > "$out"
          '';
          runtime = pkgs.runCommand "doom-nix-runtime-tests" {
            nativeBuildInputs = [ pkgs.xvfb-run ];
          } ''
            export HOME="$TMPDIR/home"
            export XDG_RUNTIME_DIR="$TMPDIR/runtime"
            mkdir -p "$HOME"
            mkdir -m 700 -p "$XDG_RUNTIME_DIR"
            export LIBGL_ALWAYS_SOFTWARE=1
            export GALLIUM_DRIVER=llvmpipe
            # Xvfb itself loads GLX before the nixray launcher configures Mesa.
            export LD_LIBRARY_PATH=${pkgs.lib.makeLibraryPath [ pkgs.mesa ]}
            export LIBGL_DRIVERS_PATH=${pkgs.mesa}/lib/dri
            export __GLX_VENDOR_LIBRARY_NAME=mesa
            export __EGL_VENDOR_LIBRARY_FILENAMES=${pkgs.mesa}/share/glvnd/egl_vendor.d/50_mesa.json
            export XDG_SESSION_TYPE=x11
            unset WAYLAND_DISPLAY
            export ALSA_CONFIG_PATH="$TMPDIR/alsa.conf"
            echo 'pcm.!default { type null }' > "$ALSA_CONFIG_PATH"
            export PULSE_SERVER="unix:$TMPDIR/no-pulse"
            export PIPEWIRE_REMOTE=doom-no-pipewire
            export JACK_NO_START_SERVER=1
            xvfb-run -a -s '-screen 0 1280x800x24 -noreset' \
              timeout -k 5s 120s ${runtime}/bin/nixray ${self}/tests/vanilla-runtime.nix --arg ray 'import ${nixray}/lib' \
                --argstr iwad ${iwad} --argstr assets ${original.package} > "$out"
            xvfb-run -a -s '-screen 0 1280x800x24 -noreset' \
              timeout -k 5s 60s ${runtime}/bin/nixray ${self}/tests/vanilla-audio.nix --arg ray 'import ${nixray}/lib' \
                --argstr assets ${original.package} > "$TMPDIR/audio.json"
            xvfb-run -a -s '-screen 0 1280x800x24 -noreset' \
              timeout -k 5s 60s ${doom}/bin/doom-nix --arg audio false --arg hidden true --arg maxFrames 3 > "$TMPDIR/launcher.json"
            grep -q '"frames":3' "$TMPDIR/launcher.json"
          '';
        });
      devShells = eachSystem (system:
        let inherit (forSystem system) pkgs runtime;
        in { default = pkgs.mkShell { packages = [ runtime pkgs.xvfb-run pkgs.nixfmt ]; }; });
    };
}
