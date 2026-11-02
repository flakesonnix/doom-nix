{ ray, sounds ? null, audio ? true, columns ? 160 }:
let
  game = import ./game.nix;
  render = import ./render.nix { inherit ray columns; };
  input = import ./input.nix;
  enabled = audio && sounds != null;
  audioActions = import ./audio.nix { inherit ray; inherit enabled; };
in {
  config = {
    width = 960; height = 640; fps = 60;
    title = "DOOM / NIX - nixray";
    audio = enabled;
    state = { game = game.initial {}; mouseX = null; };
    assets = {
      textures = import ./assets.nix { inherit ray; };
      sounds = if !enabled then {} else builtins.listToAttrs (map (name: {
        inherit name; value = "${sounds}/${name}.wav";
      }) [ "pistol" "shotgun" "chaingun" "punch" "hurt" "kill" "door" "pickup" "exit" ]);
    };
  };
  frame = frame:
    let
      previous = frame.state.game;
      next = game.step previous (input frame frame.state.mouseX previous);
      cursorChanged = previous.mouseCaptured != next.mouseCaptured || previous.phase != next.phase;
    in {
      state = { game = next; mouseX = if cursorChanged then null else frame.mouseX; };
      commands = render frame next;
      audio = audioActions next;
      window = if cursorChanged then [
        (ray.setCursorMode (if next.mouseCaptured && next.phase == "playing" then "captured" else "normal"))
      ] else [];
    };
}
