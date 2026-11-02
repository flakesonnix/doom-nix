{ ray ? import ../nixray/lib, sounds ? null, audio ? true,
  hidden ? false, maxFrames ? 0, columns ? 160 }:
let app = import ./app.nix { inherit ray sounds audio columns; };
in ray.run (app.config // { inherit hidden maxFrames; }) app.frame
