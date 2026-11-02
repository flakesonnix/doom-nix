{ ray, columns ? 160 }:
assert builtins.isInt columns && columns > 0 && columns <= 960 && 960 - builtins.div 960 columns * columns == 0;
let
  m = import ./math.nix;
  world = import ./world.nix;
  game = import ./game.nix;
  width = 960; height = 640; viewHeight = 528;
  columnWidth = builtins.div width columns;
  focal = width / 1.32;
  centerY = viewHeight / 2;
  rgba = r: g: b: [ r g b 255 ];
  colors = {
    white = rgba 225 218 181; gold = rgba 219 179 69;
    red = rgba 193 48 29; green = rgba 108 160 78;
    dark = rgba 21 25 22; gray = rgba 111 118 98;
  };
  int = builtins.floor;
  rect = x: y: w: h: color: ray.rectangle {
    x = int x; y = int y; width = m.max 0 (int w); height = m.max 0 (int h); inherit color;
  };
  text = string: x: y: size: color: ray.text { text = string; x = int x; y = int y; inherit size color; };
  shade = light: builtins.genList (_: m.clamp 25 255 (int (light * 255))) 3 ++ [ 255 ];
in frame: state:
let
  level = game.levelFor state;
  p = state.player;
  dirX = m.cos p.angle; dirY = m.sin p.angle;
  rays = builtins.genList (i:
    let offset = (2.0 * (i + 0.5) / columns - 1) * 0.66;
    in world.cast level state.doors p { x = dirX - dirY * offset; y = dirY + dirX * offset; }
  ) columns;
  wallColumn = i:
    let
      hit = builtins.elemAt rays i;
      distance = m.max 0.08 hit.distance;
      wallHeight = m.min 10000 (int (focal / distance));
      top = int (centerY - wallHeight / 2.0);
      lift = if world.isDoor hit.tile then world.opening state.doors hit.x hit.y else 0;
      texture = if hit.tile == "B" then "brick" else if hit.tile == "R" then "redDoor"
        else if hit.tile == "D" then "door" else if builtins.elem hit.tile [ "M" "S" ] then "metal" else "stone";
      tx = m.clamp 0 31 (int (hit.u * 32));
      light = (if hit.side == 0 then 1.0 else 0.73) / (1 + distance * 0.10);
    in ray.texture {
      inherit texture;
      x = i * columnWidth; y = top - int (lift * wallHeight);
      width = columnWidth; height = wallHeight;
      source = { x = tx; y = 0; width = 1; height = 32; };
      tint = shade light;
    };
  project = object:
    let dx = object.x - p.x; dy = object.y - p.y;
    in object // { depth = dx * dirX + dy * dirY; lateral = -dx * dirY + dy * dirX; };
  # Project toxic floor tiles as near-clipped world-space quads. Walls drawn
  # afterwards occlude them, so hazards are visible without a native 3D renderer.
  slime = m.concatMap (y: m.concatMap (x:
    if world.tile level x y != "~" then [] else
    let
      vertices = map project [ { inherit x y; } { x = x + 1; inherit y; }
        { x = x + 1; y = y + 1; } { inherit x; y = y + 1; } ];
      clipped = (builtins.foldl' (acc: vertex:
        let
          a = acc.previous; b = vertex;
          aIn = a.depth >= 0.08; bIn = b.depth >= 0.08;
          t = (0.08 - a.depth) / (b.depth - a.depth);
          intersection = { depth = 0.08; lateral = a.lateral + t * (b.lateral - a.lateral); };
        in { previous = b; points = acc.points ++
          (if aIn && bIn then [ b ] else if aIn then [ intersection ]
            else if bIn then [ intersection b ] else []); }
      ) { previous = builtins.elemAt vertices 3; points = []; } vertices).points;
      points = map (v: { x = int (width / 2.0 + focal * v.lateral / v.depth);
        y = int (centerY + focal * 0.5 / v.depth); }) clipped;
      pulse = int (m.sin (state.elapsed * 2 + x + y) * 9);
    in if builtins.length points < 3 then [] else [ (ray.triangleFan {
      inherit points; color = rgba (40 + pulse) (78 + pulse) 20;
    }) ]
  ) (m.range level.width)) (m.range level.height);
  objects = map (e: {
    inherit (e) x y;
    texture = if e.hp <= 0 then "corpse" else e.kind;
    size = if e.hp <= 0 then 0.20 else if e.kind == "baron" then 1.05 else 0.82;
    aspect = if e.hp <= 0 then 3.2 else 16.0 / 24;
    sourceHeight = if e.hp <= 0 then 16 else 24;
    hurt = e.hurt > 0;
  }) state.enemies ++ map (item: {
    inherit (item) x y; texture = item.kind; size = 0.35;
    aspect = 1.0; sourceHeight = 16; hurt = false;
  }) state.items ++ map (bolt: {
    inherit (bolt) x y; texture = "fireball"; size = 0.28;
    aspect = 1.0; sourceHeight = 16; hurt = false; floating = true;
  }) state.projectiles ++ m.concatMap (y: m.concatMap (x:
    if world.tile level x y == "X" then [ {
      x = x + 0.5; y = y + 0.5; texture = "exit"; size = 0.7;
      aspect = 1.0; sourceHeight = 16; hurt = false;
    } ] else []) (m.range level.width)) (m.range level.height);
  visible = builtins.sort (a: b: a.depth > b.depth)
    (builtins.filter (o: o.depth > 0.12 && o.depth < 32) (map project objects));
  sprite = object:
    let
      h = focal * object.size / object.depth;
      w = h * object.aspect;
      left = width / 2.0 + focal * object.lateral / object.depth - w / 2;
      bottom = centerY + focal * (if object.floating or false then 0.12 else 0.5) / object.depth;
      first = m.clamp 0 columns (int (left / columnWidth));
      last = m.clamp 0 columns (builtins.ceil ((left + w) / columnWidth));
    in m.concatMap (j:
      let i = first + j; hit = builtins.elemAt rays i;
          u = ((i + 0.5) * columnWidth - left) / w;
      in if object.depth >= hit.distance || u < 0 || u >= 1 then [] else [ (ray.texture {
        inherit (object) texture;
        x = i * columnWidth; y = int (bottom - h);
        width = columnWidth; height = m.max 1 (int h);
        source = { x = m.clamp 0 15 (int (u * 16)); y = 0; width = 1; height = object.sourceHeight; };
        tint = if object.hurt then [ 255 113 85 255 ] else if object.texture == "fireball" then [ 255 255 255 255 ]
          else shade (1.0 / (1 + object.depth * 0.07));
      }) ]) (m.range (m.max 0 (last - first)));
  sky = [
    (ray.rectangleGradientV { x = 0; y = 0; inherit width; height = 264;
      top = rgba 20 26 24; bottom = rgba 93 87 62; })
  ] ++ builtins.genList (i: ray.triangle {
    x1 = i * 100 - 60; y1 = 264;
    x2 = i * 100 + 30; y2 = 128 + int (m.mod (i * 37) 70);
    x3 = i * 100 + 155; y3 = 264; color = rgba 33 40 32;
  }) 11 ++ [
    (ray.rectangleGradientV { x = 0; y = 264; inherit width; height = 264;
      top = rgba 26 29 24; bottom = rgba 77 72 52; })
  ] ++ builtins.genList (i: rect 0 (290 + i * i * 2.1) width 1 [ 18 23 18 40 ]) 11;
  weapon = [ (ray.texture {
    texture = "gun-${p.weapon}";
    x = 384 + int (m.sin state.bob * 5);
    y = 288 + int (m.abs (m.cos state.bob) * 6) + (if state.muzzle > 0 then 12 else 0);
    width = 192; height = 240;
  }) ] ++ (if state.muzzle <= 0 || p.weapon == "fist" then [] else [
    (ray.triangle { x1 = 445; y1 = 353; x2 = 480; y2 = 283; x3 = 513; y3 = 353; color = rgba 255 174 33; })
    (ray.triangle { x1 = 458; y1 = 339; x2 = 480; y2 = 306; x3 = 498; y3 = 344; color = rgba 255 246 188; })
  ]);
  face = [
    (rect 450 543 60 76 (rgba 46 48 36))
    (rect 461 551 38 51 (if p.hp > 30 then rgba 170 128 84 else rgba 148 87 62))
    (rect 457 549 46 12 (rgba 60 77 44))
    (rect 466 568 9 6 colors.dark) (rect 486 568 9 6 colors.dark)
    (rect 469 569 4 3 colors.white) (rect 489 569 4 3 colors.white)
    (rect 476 579 7 9 (rgba 114 76 48))
    (rect 468 593 25 4 (if state.muzzle > 0 then colors.white else colors.dark))
  ];
  ammo = if p.weapon == "fist" then "--" else toString p.${game.weapons.${p.weapon}.ammo};
  hud = [
    (rect 0 528 width 112 (rgba 59 65 54))
    (rect 0 528 width 4 (rgba 141 143 116))
    (rect 0 631 width 9 colors.dark)
    (text ammo 34 548 46 colors.gold) (text "AMMO" 34 602 16 colors.white)
    (text "${toString p.hp}%" 181 548 46 colors.red) (text "HEALTH" 190 602 16 colors.white)
    (text "${toString p.armor}%" 550 548 46 colors.gold) (text "ARMOR" 559 602 16 colors.white)
    (text "BULL  ${toString p.bullets} / 300" 729 547 16 colors.white)
    (text "SHEL  ${toString p.shells} / 80" 729 570 16 colors.white)
    (text "1  2  3  4" 335 553 20 colors.gold)
    (text "ARMS" 348 602 16 colors.white)
    (text (if builtins.elem "red" p.keys then "RED KEY" else "NO KEY") 729 602 16
      (if builtins.elem "red" p.keys then colors.red else colors.gray))
  ] ++ face;
  centered = string: y: size: color:
    text string ((width - (frame.measureText { text = string; inherit size; }).width) / 2) y size color;
  panel = heading: subtitle: body: [
    (rect 0 0 width viewHeight [ 8 12 9 197 ])
    (rect 134 69 692 403 (rgba 30 35 28))
    (rect 134 69 692 3 colors.red)
    (centered heading 96 48 colors.red)
    (centered subtitle 158 18 colors.gold)
  ] ++ body;
  title = panel "DOOM / NIX" "NO WADS. NO C. JUST DERIVATIONS AND DEMONS." [
    (centered "ENTER / SPACE   NEW GAME" 209 24 colors.white)
    (centered "<  ${builtins.elemAt [ "I'M TOO YOUNG TO EVAL" "HURT ME PLENTY" "ULTRA-IMPURE" ] state.difficulty}  >" 253 19 colors.gold)
    (centered "WASD MOVE  /  ARROWS TURN  /  SHIFT RUN" 304 17 colors.white)
    (centered "SPACE / CTRL / CLICK FIRE  /  E USE DOORS & EXIT" 335 17 colors.white)
    (centered "1-4 WEAPONS  /  TAB MAP  /  P PAUSE" 366 17 colors.white)
    (centered "C MOUSE CAPTURE  /  M MUTE  /  R RETRY  /  ESC QUIT" 410 15 colors.gray)
  ];
  minutes = builtins.div (int state.elapsed) 60;
  seconds = builtins.mod or (a: b: a - builtins.div a b * b);
  second = seconds (int state.elapsed) 60;
  timeString = "${toString minutes}:${if second < 10 then "0" else ""}${toString second}";
  intermission = panel "SECTOR CLEARED" level.name [
    (centered "KILLS      ${toString state.kills} / ${toString (builtins.length level.enemies)}" 222 27 colors.white)
    (centered "SECRETS    ${toString state.secrets} / ${toString level.secrets}" 267 27 colors.white)
    (centered "TIME       ${timeString}    PAR ${toString level.par}s" 312 23 colors.gold)
    (centered (if state.level == 2 then "ENTER   FINISH CAMPAIGN" else "ENTER   NEXT SECTOR") 407 22 colors.white)
  ];
  overlay = if state.phase == "title" then title
    else if state.phase == "paused" then panel "PAUSED" "The evaluator is taking a breath." [
      (centered "P / ENTER   RESUME" 257 26 colors.white)
      (centered "R RETRY SECTOR  /  M MUTE  /  ESC QUIT" 359 18 colors.gray)
    ] else if state.phase == "dead" then panel "YOU DIED" "Collected by the garbage collector." [
      (centered "ENTER / R   RETRY SECTOR" 270 26 colors.white)
      (centered "Keep moving. Use cover. Watch the fireballs." 350 18 colors.gray)
    ] else if state.phase == "intermission" then intermission
    else if state.phase == "victory" then panel "BUILD SUCCEEDED" "The store is clean. You are still alive." [
      (centered "ALL THREE SECTORS PURGED" 232 27 colors.white)
      (centered "${toString (state.totalKills + state.kills)} DEMONS / ${toString (state.totalSecrets + state.secrets)} SECRETS" 286 24 colors.gold)
      (centered "ENTER   PLAY AGAIN" 400 22 colors.white)
    ] else [];
  mapScale = m.min 23 (m.min (760.0 / level.width) (400.0 / level.height));
  mapX = (width - level.width * mapScale) / 2;
  mapY = (viewHeight - level.height * mapScale) / 2;
  automap = [ (rect 0 0 width viewHeight [ 10 15 11 240 ]) ] ++
    m.concatMap (y: m.concatMap (x:
      let t = world.tile level x y; door = world.isDoor t;
          color = if t == "R" then colors.red else if door then colors.gold
            else if t == "X" then colors.green else if t == "~" then rgba 46 79 27
            else if world.solid level state.doors x y then colors.gray else rgba 27 34 25;
      in [ (rect (mapX + x * mapScale) (mapY + y * mapScale) (mapScale - 1) (mapScale - 1) color) ]
    ) (m.range level.width)) (m.range level.height) ++
    map (e: ray.circle { x = int (mapX + e.x * mapScale); y = int (mapY + e.y * mapScale);
      radius = 3; color = colors.red; }) (builtins.filter (e: e.hp > 0) state.enemies) ++ [
      (ray.circle { x = int (mapX + p.x * mapScale); y = int (mapY + p.y * mapScale);
        radius = 5; color = colors.white; })
      (ray.line { x1 = int (mapX + p.x * mapScale); y1 = int (mapY + p.y * mapScale);
        x2 = int (mapX + (p.x + dirX * 0.8) * mapScale); y2 = int (mapY + (p.y + dirY * 0.8) * mapScale);
        color = colors.white; })
      (text "AUTOMAP / TAB TO CLOSE - GAME IS LIVE" 24 490 18 colors.gold)
    ];
  view = sky ++ slime ++ map wallColumn (m.range columns) ++ m.concatMap sprite visible ++
    (if state.phase == "dead" then [] else weapon) ++ [
      (rect 474 263 4 2 [ 230 220 180 130 ]) (rect 482 263 4 2 [ 230 220 180 130 ])
    ] ++ (if state.hurt <= 0 then [] else [ (rect 0 0 width viewHeight [ 190 14 5 (int (state.hurt * 200)) ]) ])
    ++ (if state.bonus <= 0 then [] else [ (rect 0 0 width viewHeight [ 211 176 43 (int (state.bonus * 200)) ]) ])
    ++ (if state.showMap && state.phase == "playing" then automap else []) ++ [
      (text level.name 18 12 16 colors.gold)
    ] ++ (if state.messageTimer <= 0 then [] else [ (centered state.message 40 17 colors.white) ])
    ++ overlay;
in [ (ray.clear colors.dark) (ray.clip { x = 0; y = 0; inherit width; height = viewHeight; commands = view; }) ]
  ++ hud ++ [ (text (if state.muted then "MUTED" else "NIXRAY") 864 614 10 colors.gray) ]
