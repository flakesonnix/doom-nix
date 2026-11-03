{ ray, assets, iwad ? null, music ? null, mode ? "effects" }:
let
  names = [ "DSPISTOL" "DSSHOTGN" "DSRLAUNC" "DSSAWFUL" "DSPLPAIN" "DSDOROPN" "DSDORCLS" "DSITEMUP" "DSTELEPT" ];
  result = ray.run {
    width = 320; height = 200; hidden = true; maxFrames = builtins.length names * 6; audio = true; fps = 60;
    assets.sounds = builtins.listToAttrs (map (name: { inherit name; value = "${assets}/${name}.wav"; }) names);
  } (frame:
    let sound = builtins.elemAt names (builtins.div frame.frame 6);
    in assert frame.audio.enabled; {
      commands = [ (ray.clear [ 0 0 0 255 ]) ];
      audio = if frame.frame - builtins.div frame.frame 6 * 6 == 0 then [ (ray.playSound sound) ] else [];
    }
  );
  wad = import ../vanilla/wad.nix (builtins.readFile "${iwad}/doom1.hex");
  tracks = builtins.filter (name: builtins.substring 0 2 name == "D_") (builtins.attrNames wad.named);
  streamed = ray.run {
    width = 320; height = 200; hidden = true; maxFrames = builtins.length tracks * 12; audio = true; fps = 60;
    assets.music = builtins.listToAttrs (map (name: { inherit name; value = "${music}/${name}.ogg"; }) tracks);
  } (frame:
    let index = builtins.div frame.frame 12; track = builtins.elemAt tracks index;
        change = frame.frame - index * 12 == 0;
    in assert frame.audio.enabled && frame.audio.music.${track}.timeLength > 1;
       assert change || frame.audio.music.${track}.playing; {
      commands = [];
      audio = if !change then [] else (if index == 0 then [] else [ (ray.stopMusic (builtins.elemAt tracks (index - 1))) ])
        ++ [ (ray.playMusic track) ];
    }
  );
  app = import ../vanilla/app.nix { inherit ray wad assets music; };
  transport = ray.run ((app.configured app.initial) // { hidden = true; maxFrames = 45; fps = 60; }) (frame:
    let
      paused = builtins.elem frame.frame [ 6 10 ];
      playing = builtins.elem frame.frame [ 4 8 12 ];
      phase = if frame.frame == 20 then "intermission" else if frame.frame == 30 then "victory" else null;
      keysPressed = if builtins.elem frame.frame [ 2 3 ] then [ 257 ]
        else if builtins.elem frame.frame [ 5 7 ] then [ 80 ] else if builtins.elem frame.frame [ 9 11 ] then [ 77 ] else [];
    in assert !paused || !frame.audio.music.D_E1M1.playing;
       assert !playing || frame.audio.music.D_E1M1.playing;
       assert frame.frame != 1 || frame.audio.music.D_INTRO.playing;
       assert frame.frame != 21 || frame.audio.music.D_INTER.playing;
       assert frame.frame != 31 || frame.audio.music.D_VICTOR.playing;
       app.callback app.initial (frame // { inherit keysPressed; delta = 1.0 / 35; keysDown = []; mouseDown = [];
         state = frame.state // { game = frame.state.game // (if phase == null then {} else { inherit phase; }); };
       })
  );
  campaign = import ../vanilla/doom.nix {
    inherit iwad assets music; hidden = true; start = true; maxFrames = 3;
    ray = ray // { run = config: callback: ray.run (config // { fps = 60; }) (frame:
      callback (frame // { keysDown = []; mouseDown = []; keysPressed = if config.state.game.level == 0 then [ 257 ] else [];
        state = frame.state // { game = frame.state.game // (if config.state.game.level == 0 then { phase = "intermission"; } else {}); };
      })
    ); };
  };
in if mode == "effects" then assert result.frames == builtins.length names * 6; { passed = builtins.length names; }
   else assert mode == "music" && iwad != null && music != null;
     assert streamed.frames == builtins.length tracks * 12;
     assert campaign.frames == 3 && campaign.state.track == "D_E1M2";
     assert transport.frames == 45 && transport.state.track == "D_VICTOR";
     { passed = builtins.length tracks; transportFrames = transport.frames + campaign.frames; }
