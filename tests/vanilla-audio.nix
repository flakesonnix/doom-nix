{ ray, assets }:
let
  names = [ "DSPISTOL" "DSSHOTGN" "DSRLAUNC" "DSSAWFUL" "DSPLPAIN" "DSDOROPN" "DSDORCLS" "DSITEMUP" "DSTELEPT" ];
  result = ray.run {
    width = 320; height = 200; hidden = true; maxFrames = builtins.length names; audio = true; fps = 0;
    assets.sounds = builtins.listToAttrs (map (name: { inherit name; value = "${assets}/${name}.wav"; }) names);
  } (frame:
    let sound = builtins.elemAt names frame.frame;
    in assert frame.audio.enabled; {
      commands = [ (ray.clear [ 0 0 0 255 ]) ];
      audio = [ (ray.playSound sound) ];
    }
  );
in assert result.frames == builtins.length names;
  { passed = result.frames; }
