let
  inherit (import ./math.nix) range;
  enemy = kind: x: y: { inherit kind x y; };
  item = kind: x: y: { inherit kind x y; };
  # Rooms are built in Nix as well: no map compiler, WAD, or external assets.
  make = { name, subtitle, width, height, partitions, doors, pillars ? [],
    slime ? [], spawn, enemies, items, exit, par }:
    let
      inRect = x: y: r: x >= r.x && x < r.x + r.w && y >= r.y && y < r.y + r.h;
      tile = x: y:
        let door = builtins.filter (d: d.x == x && d.y == y) doors;
        in if x == 0 || y == 0 || x == width - 1 || y == height - 1 then "#"
        else if door != [] then (builtins.head door).kind
        else if builtins.any (inRect x y) (partitions ++ pillars) then
          (if x >= builtins.div width 2 then "B" else "M")
        else if exit.x == x && exit.y == y then "X"
        else if builtins.any (inRect x y) slime then "~" else ".";
    in {
      inherit name subtitle width height spawn par;
      grid = map (y: map (x: tile x y) (range width)) (range height);
      enemies = builtins.genList (i:
        let e = builtins.elemAt enemies i;
        in e // { id = i; x = e.x + 0.5; y = e.y + 0.5; }
      ) (builtins.length enemies);
      items = builtins.genList (i:
        let e = builtins.elemAt items i;
        in e // { id = i; x = e.x + 0.5; y = e.y + 0.5; }
      ) (builtins.length items);
      secrets = builtins.length (builtins.filter (d: d.kind == "S") doors);
    };
in map make [
  {
    name = "E1M1 / THE DERIVATION";
    subtitle = "The store has been compromised.";
    width = 25; height = 17; par = 90;
    spawn = { x = 3.5; y = 4.5; angle = 0.0; };
    partitions = [ { x = 8; y = 1; w = 1; h = 15; } { x = 16; y = 1; w = 1; h = 15; } ];
    doors = [ { x = 8; y = 4; kind = "D"; } { x = 16; y = 12; kind = "R"; }
      { x = 8; y = 14; kind = "S"; } ];
    pillars = [ { x = 11; y = 6; w = 2; h = 3; } { x = 20; y = 8; w = 2; h = 2; } ];
    slime = [ { x = 10; y = 10; w = 4; h = 2; } ];
    exit = { x = 22; y = 3; };
    enemies = [ (enemy "guard" 6 7) (enemy "imp" 11 3) (enemy "guard" 14 13)
      (enemy "imp" 18 12) (enemy "imp" 21 5) ];
    items = [ (item "bullets" 4 3) (item "shotgun" 11 4) (item "shells" 14 4)
      (item "redkey" 12 14) (item "health" 4 12) (item "armor" 6 14)
      (item "shells" 19 13) (item "health" 22 12) ];
  }
  {
    name = "E1M2 / IMPURE EVALUATION";
    subtitle = "Something is alive in the build farm.";
    width = 29; height = 19; par = 120;
    spawn = { x = 3.5; y = 9.5; angle = 0.0; };
    partitions = [ { x = 9; y = 1; w = 1; h = 17; } { x = 19; y = 1; w = 1; h = 17; }
      { x = 10; y = 9; w = 9; h = 1; } ];
    doors = [ { x = 9; y = 9; kind = "D"; } { x = 14; y = 9; kind = "D"; }
      { x = 19; y = 4; kind = "R"; } { x = 9; y = 15; kind = "S"; } ];
    pillars = [ { x = 4; y = 4; w = 2; h = 2; } { x = 4; y = 13; w = 2; h = 2; }
      { x = 23; y = 7; w = 2; h = 5; } ];
    slime = [ { x = 11; y = 3; w = 6; h = 3; } ];
    exit = { x = 26; y = 15; };
    enemies = [ (enemy "guard" 7 8) (enemy "imp" 13 13) (enemy "guard" 17 15)
      (enemy "imp" 13 7) (enemy "imp" 17 3) (enemy "guard" 22 4)
      (enemy "imp" 26 6) (enemy "baron" 26 13) ];
    items = [ (item "shotgun" 6 9) (item "shells" 7 12) (item "health" 2 15)
      (item "chaingun" 12 15) (item "redkey" 17 13) (item "armor" 11 16)
      (item "bullets" 17 7) (item "bullets" 22 3) (item "health" 25 4)
      (item "shells" 21 15) (item "health" 26 17) ];
  }
  {
    name = "E1M3 / GARBAGE COLLECTOR";
    subtitle = "Terminate the root process.";
    width = 29; height = 23; par = 180;
    spawn = { x = 3.5; y = 11.5; angle = 0.0; };
    partitions = [ { x = 8; y = 1; w = 1; h = 21; } { x = 19; y = 1; w = 1; h = 21; }
      { x = 9; y = 7; w = 10; h = 1; } { x = 9; y = 15; w = 10; h = 1; } ];
    doors = [ { x = 8; y = 11; kind = "D"; } { x = 14; y = 7; kind = "D"; }
      { x = 14; y = 15; kind = "D"; } { x = 19; y = 11; kind = "R"; }
      { x = 8; y = 19; kind = "S"; } ];
    pillars = [ { x = 12; y = 10; w = 2; h = 3; } { x = 23; y = 5; w = 2; h = 2; }
      { x = 23; y = 16; w = 2; h = 2; } ];
    slime = [ { x = 10; y = 2; w = 7; h = 3; } { x = 10; y = 18; w = 7; h = 3; } ];
    exit = { x = 26; y = 11; };
    enemies = [ (enemy "guard" 6 10) (enemy "imp" 10 11) (enemy "guard" 17 12)
      (enemy "imp" 11 5) (enemy "baron" 17 3) (enemy "imp" 11 17)
      (enemy "guard" 17 20) (enemy "imp" 22 10) (enemy "imp" 25 4)
      (enemy "imp" 25 19) (enemy "baron" 25 11) ];
    items = [ (item "shotgun" 5 11) (item "chaingun" 6 19) (item "shells" 10 13)
      (item "redkey" 17 2) (item "health" 14 6) (item "armor" 14 17)
      (item "bullets" 17 19) (item "shells" 10 20) (item "health" 4 4)
      (item "bullets" 21 9) (item "shells" 21 13) (item "health" 26 20) ];
  }
]
