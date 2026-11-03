{ ray, iwad, assets }:
let
  wad = import ../vanilla/wad.nix (builtins.readFile "${iwad}/doom1.hex");
  app = import ../vanilla/app.nix { inherit ray wad assets; audio = false; start = true; };
  renderCase = level:
    let
      base = (app.game.initial { inherit level; }) // { phase = "playing"; };
      draw = import ../vanilla/render.nix { inherit ray wad; map = app.game.currentMap base; };
      scenarios = if level != 0 then [ base ] else [ base
        (base // { phase = "title"; }) (base // { phase = "title"; menu = true; })
        (base // { phase = "dead"; }) (base // { phase = "intermission"; })
        (base // { phase = "victory"; }) (base // { paused = true; }) (base // { showMap = true; })
        (base // { player = base.player // { weapon = "shotgun"; weaponState = 3; }; })
      ];
      frames = builtins.length scenarios;
      result = ray.run ((app.configured base) // { hidden = true; maxFrames = frames; fps = 0; }) (frame:
        let current = builtins.elemAt scenarios frame.frame;
            commands = draw current;
            next = app.game.step current { delta = 1.0 / 35; };
        in assert ray.validate commands > 0;
           assert builtins.stringLength (builtins.toJSON next) > 0;
           { inherit commands; state = frame.frame; }
      );
    in assert result.frames == frames; result.frames;
  results = builtins.genList renderCase 9;
  gameplay = ray.run ((app.configured app.initial) // { hidden = true; maxFrames = 45; fps = 0; }) (frame:
    app.callback app.initial (frame // {
      delta = 1.0 / 35; keysDown = [ 87 341 ]; mouseDown = [];
      keysPressed = if builtins.elem frame.frame [ 10 12 ] then [ 80 ] else if frame.frame == 20 then [ 258 ] else [];
    })
  );
  # Drive the real launcher through intermission and window/asset recreation.
  campaign = import ../vanilla/doom.nix {
    inherit iwad assets; audio = false; hidden = true; start = true; maxFrames = 3;
    ray = ray // { run = config: callback: ray.run (config // { fps = 0; }) (frame:
      callback (if config.state.game.level == 0 && frame.frame == 0 then frame // {
        state = frame.state // { game = frame.state.game // { phase = "intermission"; }; };
        keysPressed = [ 257 ];
      } else frame)
    ); };
  };
  image = ray.loadImage "${assets}/patch-TITLEPIC.png";
  pixel = (wad.patch "TITLEPIC").pixel 100 100;
in assert ray.imagePixel image { x = 100; y = 100; } == builtins.elemAt wad.palette pixel;
   assert builtins.elemAt (ray.imagePixel (ray.loadImage "${assets}/patch-AMMOA0.png") { x = 0; y = 0; }) 3 == 0;
   assert gameplay.frames == 45 && gameplay.state.game.tic == 42;
   assert gameplay.state.game.player.y > app.initial.player.y && gameplay.state.game.player.bullets < 50;
   assert gameplay.state.game.showMap && !gameplay.state.game.paused;
   assert campaign.frames == 3 && campaign.state.game.level == 1 && campaign.state.game.phase == "playing";
   { maps = builtins.length results; frames = builtins.foldl' (a: b: a + b) (gameplay.frames + campaign.frames) results; }
