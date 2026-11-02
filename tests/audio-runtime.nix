{ ray, sounds }:
let
  app = import ../app.nix { inherit ray sounds; };
  actions = import ../audio.nix { inherit ray; enabled = true; };
  names = builtins.attrNames app.config.assets.sounds;
  count = builtins.length names;
  result = ray.run (app.config // { hidden = true; maxFrames = count; fps = 0; }) (frame:
    let audio = actions { muted = false; events = [ (builtins.elemAt names frame.frame) ]; };
    in assert frame.audio.enabled;
       assert ray.validateAudio audio == 1;
       { inherit audio; commands = [ (ray.clear [ 0 0 0 255 ]) ]; state = frame.frame; }
  );
in assert result.frames == count;
   { passed = count; }
