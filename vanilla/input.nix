frame: state: previousMouse:
let
  down = k: builtins.elem k frame.keysDown;
  pressed = k: builtins.elem k frame.keysPressed;
  axis = yes: no: (if yes then 1 else 0) - (if no then 1 else 0);
in {
  delta = frame.delta;
  forward = axis (down 87 || down 265) (down 83 || down 264);
  strafe = axis (down 68) (down 65);
  turn = axis (down 262) (down 263);
  look = if !state.captured || previousMouse == null || state.phase != "playing" || state.paused then 0.0
    else -(frame.mouseX - previousMouse) * 0.003;
  run = down 340 || down 344;
  fire = down 341 || down 345 || builtins.elem 0 frame.mouseDown;
  use = pressed 32 || pressed 69;
  start = pressed 257 || (state.phase != "playing" && pressed 32);
  pause = pressed 80;
  restart = pressed 82;
  toggleMap = pressed 258;
  toggleMute = pressed 77;
  capture = pressed 67;
  selectWeapon = if pressed 49 then (if builtins.elem "chainsaw" state.player.weapons && state.player.weapon == "fist" then "chainsaw" else "fist")
    else if pressed 50 then "pistol" else if pressed 51 then "shotgun" else if pressed 52 then "chaingun"
    else if pressed 53 then "rocket" else null;
  skill = if state.phase != "title" then null else if pressed 264 || pressed 262 then state.skill + 1
    else if pressed 265 || pressed 263 then state.skill - 1 else null;
}
