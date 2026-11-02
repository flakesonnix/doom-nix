let
  m = import ./math.nix;
  rgb = r: g: b: [ r g b 255 ];
  blank = [ 0 0 0 0 ];
  inside = n: a: b: n >= a && n <= b;
  box = x: y: left: top: right: bottom: inside x left right && inside y top bottom;
  noise = x: y: builtins.floor (m.mod (x * 13 + y * 7 + x * y * 3) 13) - 6;
  shade = c: n: map (v: m.clamp 0 255 (v + n)) (builtins.genList (i: builtins.elemAt c i) 3) ++ [ 255 ];
  wall = kind: x: y:
    let
      mortar = m.mod y 8 == 0 || m.mod (x + (if m.mod (builtins.div y 8) 2 == 0 then 0 else 8)) 16 == 0;
      edge = m.mod x 16 == 0 || y == 0 || y == 31;
      bolt = builtins.elem x [ 2 29 ] && builtins.elem y [ 2 29 ];
      base = if kind == "brick" then (if mortar then rgb 34 24 23 else rgb 124 66 48)
        else if kind == "stone" then (if mortar then rgb 34 39 35 else rgb 90 99 82)
        else if kind == "metal" then (if edge then rgb 31 38 35 else if bolt then rgb 151 158 131 else rgb 82 96 85)
        else if y < 3 || y > 28 then rgb 37 40 35
        else if x < 3 || x > 28 then rgb 153 144 98
        else if inside y 13 18 then
          (if m.mod (x + y) 8 < 4 then (if kind == "redDoor" then rgb 187 37 24 else rgb 197 157 39) else rgb 30 30 25)
        else if m.mod y 5 == 0 then rgb 39 44 40 else rgb 98 108 98;
    in shade base (noise x y);
  monster = kind: x: y:
    let
      human = kind == "guard";
      skin = if human then rgb 194 145 97 else if kind == "baron" then rgb 173 68 65 else rgb 142 93 48;
      body = if human then rgb 74 103 58 else skin;
      dark = if human then rgb 37 48 31 else rgb 65 37 29;
    in if !human && ((box x y 3 0 4 3) || box x y 11 0 12 3) then rgb 213 194 141
      else if box x y 5 2 10 6 then
        if y == 4 && builtins.elem x [ 6 9 ] then rgb 255 78 26
        else if y == 6 && inside x 6 9 then rgb 45 21 16 else shade skin (noise x y)
      else if box x y 4 7 11 14 then
        if human && box x y 7 9 9 12 then rgb 39 43 39 else shade body (noise x y * 2)
      else if box x y 2 8 3 15 || box x y 12 8 13 15 then
        if y >= 13 then skin else dark
      else if box x y 4 15 6 21 || box x y 9 15 11 21 then
        if y >= 20 then dark else shade body (-20)
      else blank;
  pickup = kind: x: y:
    if kind == "fireball" then
      let d = (x - 7.5) * (x - 7.5) + (y - 7.5) * (y - 7.5);
      in if d < 12 then rgb 255 245 170 else if d < 26 then rgb 255 170 21
        else if d < 42 then rgb 225 51 13 else blank
    else if kind == "corpse" then
      if box x y 2 12 13 14 then (if m.mod x 3 == 0 then rgb 128 24 16 else rgb 68 36 24) else blank
    else if kind == "exit" then
      if box x y 1 2 14 13 then
        if x == 1 || x == 14 || y == 2 || y == 13 then rgb 137 147 117
        else if box x y 4 6 11 9 then rgb 101 255 77 else rgb 29 52 30 else blank
    else if kind == "redkey" then
      if box x y 3 5 12 11 then
        if x < 5 then rgb 215 204 152 else if y == 7 then rgb 255 106 74 else rgb 174 29 20 else blank
    else if kind == "health" then
      if box x y 2 5 13 13 then
        if (inside x 6 9 && inside y 6 12) || (inside y 8 10 && inside x 4 11)
          then rgb 200 34 27 else rgb 204 198 162 else blank
    else if kind == "armor" then
      if box x y 3 4 12 12 && !(inside x 6 9 && y < 6) then
        if y < 7 || x == 3 || x == 12 then rgb 75 130 73 else rgb 44 85 47 else blank
    else if builtins.elem kind [ "shotgun" "chaingun" ] then
      if box x y 1 7 14 9 then rgb 124 133 128
      else if box x y 9 10 12 13 then rgb 100 61 31
      else if kind == "chaingun" && box x y 1 10 8 11 then rgb 74 83 78 else blank
    else if box x y 3 6 12 13 then
      if kind == "shells" then (if m.mod x 3 == 0 || y == 13 then rgb 196 159 69 else rgb 161 42 24)
      else if y < 8 then rgb 205 167 76 else rgb 92 98 58 else blank;
  gun = kind: x: y:
    let
      metal = if builtins.elem x [ 13 17 ] then rgb 147 153 142 else rgb 67 75 70;
      barrel = if kind == "shotgun" then box x y 11 4 20 28
        else if kind == "chaingun" then box x y 8 9 23 28 else box x y 12 9 19 28;
    in if kind == "fist" then
      if box x y 10 14 23 31 then (if m.mod x 4 == 0 && y < 23 then rgb 123 82 50 else rgb 187 142 96)
      else if box x y 13 32 23 39 then rgb 80 89 52 else blank
    else if barrel then
      if y < 12 then (if inside x 13 18 then rgb 24 28 25 else metal)
      else if kind == "shotgun" && y > 21 then rgb 108 72 36
      else if kind == "chaingun" && m.mod x 4 < 2 then rgb 35 42 38 else metal
    else if box x y 8 29 23 39 then
      if box x y 11 29 20 35 then rgb 66 72 65 else rgb 168 122 80
    else if box x y 5 35 26 39 then rgb 72 84 49 else blank;
  definition = width: height: pixel: { inherit width height pixel; };
in {
  textures = {
    stone = definition 32 32 (wall "stone");
    brick = definition 32 32 (wall "brick");
    metal = definition 32 32 (wall "metal");
    door = definition 32 32 (wall "door");
    redDoor = definition 32 32 (wall "redDoor");
  } // builtins.listToAttrs (map (name: { inherit name; value = definition 16 24 (monster name); }) [ "guard" "imp" "baron" ])
    // builtins.listToAttrs (map (name: { inherit name; value = definition 16 16 (pickup name); })
      [ "health" "armor" "redkey" "bullets" "shells" "shotgun" "chaingun" "fireball" "corpse" "exit" ])
    // builtins.listToAttrs (map (name: { name = "gun-${name}"; value = definition 32 40 (gun name); })
      [ "fist" "pistol" "shotgun" "chaingun" ]);
}
