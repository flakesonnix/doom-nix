frame: previousMouse: state:
let
  down = key: builtins.elem key frame.keysDown;
  pressed = key: builtins.elem key frame.keysPressed;
  axis = positive: negative: (if positive then 1 else 0) - (if negative then 1 else 0);
  look = if !state.mouseCaptured || previousMouse == null || state.phase != "playing" then 0.0
    else (frame.mouseX - previousMouse) * 0.003;
in {
  delta = frame.delta;
  forward = axis (down 87 || down 265) (down 83 || down 264);
  strafe = axis (down 68) (down 65);
  turn = axis (down 262) (down 263);
  inherit look;
  run = down 340 || down 344;
  fire = down 32 || down 341 || down 345 || builtins.elem 0 frame.mouseDown;
  use = pressed 69;
  start = pressed 257 || (state.phase != "playing" && pressed 32);
  pause = pressed 80;
  restart = pressed 82;
  toggleMap = pressed 258;
  toggleMute = pressed 77;
  capture = pressed 67;
  selectWeapon = if pressed 49 then "fist" else if pressed 50 then "pistol"
    else if pressed 51 then "shotgun" else if pressed 52 then "chaingun" else null;
  difficulty = if state.phase == "title" then
    (if pressed 263 then state.difficulty - 1 else if pressed 262 then state.difficulty + 1 else null)
    else null;
}
