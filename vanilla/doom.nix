{ ray, iwad, assets, audio ? true, hidden ? false, maxFrames ? 0, map ? 1, skill ? 2, start ? false }:
assert map >= 1 && map <= 9 && skill >= 0 && skill <= 4;
let
  wad = import ./wad.nix (builtins.readFile "${iwad}/doom1.hex");
  app = import ./app.nix { inherit ray wad assets audio skill start; level = map - 1; };
  run = initial: remaining: total:
    let result = ray.run ((app.configured initial) // { inherit hidden; maxFrames = remaining; }) (app.callback initial);
        next = result.state.game;
        left = if maxFrames == 0 then 0 else remaining - result.frames;
    in if next.phase == "loading" && (maxFrames == 0 || left > 0) then
      run (next // { phase = "playing"; }) left (total + result.frames)
    else result // { frames = total + result.frames; };
in run app.initial maxFrames 0
