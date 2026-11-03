{ ray, wad, assets, music ? null, audio ? true, level ? 0, skill ? 2, start ? false }:
let
  game = import ./game.nix { inherit wad; };
  m = import ../math.nix;
  input = import ./input.nix;
  patchNames = builtins.map (l: l.name) (builtins.filter (l: l.size > 8 && builtins.match "STEP.*" l.name == null &&
    ((l.id > (wad.lump "S_START").id && l.id < (wad.lump "S_END").id) ||
      builtins.match "(ST.*|M_.*|WI.*|TITLEPIC|CREDIT|HELP[0-9]*|INTERPIC)" l.name != null)) wad.directory);
  soundNames = builtins.filter (name: builtins.substring 0 2 name == "DS") (builtins.attrNames wad.named);
  musicNames = state: [ "D_INTRO" "D_INTER" "D_VICTOR" "D_E1M${toString (state.level + 1)}" ];
  musicFor = state: if state.phase == "loading" then null else if state.phase == "title" then "D_INTRO"
    else if state.phase == "intermission" then "D_INTER" else if state.phase == "victory" then "D_VICTOR"
    else "D_E1M${toString (state.level + 1)}";
  configured = initial:
    let map = game.currentMap initial; geo = game.geometry.makeMap map;
    in {
      width = 960; height = 720; title = "DOOM Shareware 1.9 / Nix"; fps = 60;
      inherit audio;
      state = { game = initial; mouseX = null; track = null; musicPaused = false; };
      assets = {
        textures = builtins.listToAttrs (builtins.map (name: {
          name = "p-${name}"; value = { path = "${assets}/patch-${name}.png"; filter = "point"; };
        }) patchNames) // { sky = { path = "${assets}/wall-SKY1.png"; wrap = "repeat"; filter = "point"; }; };
        models = builtins.listToAttrs (builtins.map (group: {
          name = "${map.name}-${group}"; value = "${assets}/${map.name}-${group}.obj";
        }) geo.groups);
        renderTextures = { world = { width = 320; height = 168; filter = "point"; };
          screen = { width = 320; height = 200; filter = "point"; }; };
        sounds = if !audio then {} else builtins.listToAttrs (builtins.map (name: { inherit name; value = "${assets}/${name}.wav"; }) soundNames);
        music = if !audio || music == null then {} else builtins.listToAttrs (builtins.map (name: {
          inherit name; value = { path = "${music}/${name}.ogg"; looping = name != "D_INTRO"; };
        }) (musicNames initial));
      };
    };
  callback = initial:
    let render = import ./render.nix { inherit ray wad; map = game.currentMap initial; };
    in frame:
      let
        old = frame.state.game;
        next = game.step old (input frame old frame.state.mouseX);
        changed = old.captured != next.captured || old.phase != next.phase || old.paused != next.paused;
        events = builtins.attrNames (builtins.listToAttrs (builtins.map (name: { inherit name; value = true; }) next.events));
        track = if !audio || music == null then null else musicFor next;
        musicPaused = next.paused || next.muted;
        switched = track != frame.state.track;
        transport = if !audio || music == null then [] else
          (if switched then (if frame.state.track == null then [] else [ (ray.stopMusic frame.state.track) ])
            ++ (if track == null then [] else [ (ray.setMusicVolume { music = track; volume = 0.5; }) (ray.playMusic track) ])
            else [])
          ++ (if track == null then [] else if musicPaused && (switched || !frame.state.musicPaused) then [ (ray.pauseMusic track) ]
            else if !musicPaused && !switched && frame.state.musicPaused then [ (ray.resumeMusic track) ] else []);
      in {
        state = { game = next; mouseX = if changed then null else frame.mouseX; inherit track musicPaused; };
        commands = render next;
        audio = transport ++ (if !audio || next.muted then [] else builtins.map ray.playSound (builtins.filter (name: builtins.elem name soundNames) events));
        window = if !changed then [] else [ (ray.setCursorMode (if next.captured && next.phase == "playing" && !next.paused then "captured" else "normal")) ];
        close = next.phase == "loading";
      };
in {
  inherit game configured callback;
  initial = (game.initial { inherit level skill; }) // { phase = if start then "playing" else "title"; };
}
