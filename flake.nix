{
  description = "DOOM / NIX: a Doom-inspired FPS written in Nix using nixray";
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
          sounds = import ./sounds.nix { inherit (pkgs) runCommand; };
          doom = pkgs.writeShellApplication {
            name = "doom-nix";
            text = ''
              exec ${runtime}/bin/nixray ${self}/doom.nix --arg ray 'import ${nixray}/lib' --argstr sounds ${sounds} "$@"
            '';
            meta.description = "Play DOOM / NIX, a three-sector pure-Nix FPS";
          };
        in { inherit pkgs runtime sounds doom; };
    in {
      packages = eachSystem (system: {
        default = (forSystem system).doom;
        doom-nix = (forSystem system).doom;
        sounds = (forSystem system).sounds;
      });
      apps = eachSystem (system: {
        default = { type = "app"; program = "${self.packages.${system}.default}/bin/doom-nix";
          meta.description = "DOOM / NIX"; };
      });
      checks = eachSystem (system:
        let inherit (forSystem system) pkgs runtime doom sounds;
        in {
          logic = pkgs.runCommand "doom-nix-logic-tests" {
            nativeBuildInputs = [ runtime.nixComponents.nix-cli ];
          } ''
            export HOME="$TMPDIR"
            nix-instantiate --eval --strict --json ${self}/tests/default.nix > "$out"
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
              ${runtime}/bin/nixray ${self}/tests/runtime.nix --arg ray 'import ${nixray}/lib' > "$out"
            xvfb-run -a -s '-screen 0 1280x800x24 -noreset' \
              ${runtime}/bin/nixray ${self}/tests/audio-runtime.nix --arg ray 'import ${nixray}/lib' \
                --argstr sounds ${sounds} > "$TMPDIR/audio.json"
            xvfb-run -a -s '-screen 0 1280x800x24 -noreset' \
              ${doom}/bin/doom-nix --arg hidden true --arg maxFrames 3 > "$TMPDIR/launcher.json"
            grep -q '"frames":3' "$TMPDIR/launcher.json"
          '';
        });
      devShells = eachSystem (system:
        let inherit (forSystem system) pkgs runtime;
        in { default = pkgs.mkShell { packages = [ runtime pkgs.xvfb-run pkgs.nixfmt ]; }; });
    };
}
