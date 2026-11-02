{ ray ? import ../../nixray/lib }:
let
  game = import ../game.nix;
  app = import ../app.nix { inherit ray; audio = false; };
  render = import ../render.nix { inherit ray; };
  base = game.step (game.initial {}) { start = true; };
  scenarios = [
    (game.initial {}) base
    (base // { phase = "paused"; }) (base // { phase = "dead"; })
    (base // { phase = "intermission"; }) (base // { phase = "victory"; })
    (base // { showMap = true; })
    (base // { muzzle = 0.1; player = base.player // { weapon = "shotgun"; }; })
    (base // { player = base.player // { weapon = "chaingun"; }; hurt = 0.2; })
    ((game.initial { level = 1; }) // { phase = "playing"; })
    ((game.initial { level = 2; }) // { phase = "playing"; })
    (base // { doors."8,4" = 0.5; })
  ];
  count = builtins.length scenarios;
  result = ray.run (app.config // { hidden = true; maxFrames = count; fps = 0; }) (frame:
    let
      current = builtins.elemAt scenarios frame.frame;
      output = app.frame (frame // {
        state = { game = current; mouseX = null; };
        keysDown = []; keysPressed = []; mouseDown = [];
        delta = 1.0 / 60;
      });
      commands = render frame current;
    in assert ray.validate commands > 0;
       assert ray.validateAudio output.audio == 0;
       assert ray.validateWindow output.window >= 0;
       output // { inherit commands; state = { scenario = frame.frame; }; }
  );
  stone = app.config.assets.textures.stone.image;
in assert (ray.imageInfo stone).width == 32;
   assert ray.imagePixel app.config.assets.textures.imp.image { x = 0; y = 0; } == [ 0 0 0 0 ];
   assert result.frames == count;
   assert result.state.scenario == count - 1;
   { passed = count; frames = result.frames; }
