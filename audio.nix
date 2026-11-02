{ ray, enabled }:
state:
if !enabled || state.muted then [] else
map ray.playSound (builtins.filter (name:
  builtins.elem name [ "pistol" "shotgun" "chaingun" "punch" "hurt" "kill" "door" "pickup" "exit" ]
) state.events)
