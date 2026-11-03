{ ray, wad, map }:
let
  m = import ../math.nix;
  rules = import ./rules.nix;
  world = import ./world.nix;
  geometry = (import ./geometry.nix { inherit wad; }).makeMap map;
  int = builtins.floor;
  white = [ 255 255 255 255 ];
  black = [ 0 0 0 255 ];
  patch = name: x: y: ray.texture { texture = "p-${name}"; x = int x; y = int y; };
  at = name: x: y:
    let image = wad.patch name;
    in patch name (x - image.left) (y - image.top);
  rect = x: y: width: height: color: ray.rectangle { inherit x y width height color; };
  upper = builtins.replaceStrings (builtins.genList (i: builtins.substring i 1 "abcdefghijklmnopqrstuvwxyz") 26)
    (builtins.genList (i: builtins.substring i 1 "ABCDEFGHIJKLMNOPQRSTUVWXYZ") 26);
  alphabet = " !\"#$%&'()*+,-./0123456789:;<=>?@ABCDEFGHIJKLMNOPQRSTUVWXYZ[\\]^_";
  characters = builtins.listToAttrs (builtins.genList (i: {
    name = builtins.substring i 1 alphabet; value = i + 32;
  }) (builtins.stringLength alphabet));
  font = string: x: y:
    (builtins.foldl' (acc: i:
      let char = builtins.substring i 1 (upper string); code = characters.${char} or 32;
          name = "STCFN${if code < 100 then "0" else ""}${toString code}";
          image = if code > 32 && wad.named ? ${name} then wad.patch name else null;
      in if image == null then acc // { x = acc.x + 4; } else {
        x = acc.x + image.width; commands = acc.commands ++ [ (at name acc.x y) ];
      }
    ) { inherit x; commands = []; } (m.range (builtins.stringLength string))).commands;
  digits = prefix: value: right: y:
    let string = toString (max 0 (int value)); count = builtins.stringLength string;
        max = m.max;
    in builtins.genList (i:
      let name = prefix + builtins.substring (count - 1 - i) 1 string; image = wad.patch name;
      in patch name (right - (i + 1) * image.width) y
    ) count;
  spriteLumps = builtins.filter (l: l.id > (wad.lump "S_START").id && l.id < (wad.lump "S_END").id) wad.directory;
  variants = builtins.listToAttrs (m.concatMap (l:
    let name = l.name;
    in [ { name = builtins.substring 0 6 name; value = { inherit name; flip = false; }; } ]
      ++ (if builtins.stringLength name < 8 then [] else [ {
        name = builtins.substring 0 4 name + builtins.substring 6 2 name;
        value = { inherit name; flip = true; };
      } ])
  ) spriteLumps);
in state:
let
  p = state.player;
  sector = world.sector map state (world.sectorAt map p);
  eye = p.z + (if state.phase == "dead" then 10 else 41)
    + min 8 ((p.momx * p.momx + p.momy * p.momy) / 8) * m.sin (state.tic * m.tau / 20);
  min = m.min;
  camera = {
    position = { x = p.x / 64.0; y = eye / 64.0; z = -p.y / 64.0; };
    target = { x = (p.x + m.cos p.angle * 64) / 64; y = eye / 64.0; z = -(p.y + m.sin p.angle * 64) / 64; };
    fovy = 55.398472;
  };
  model = group: y: ray.model { model = "${map.name}-${group}"; position = { x = 0; inherit y; z = 0; }; };
  models = builtins.map (batch:
    let field = if batch.type == "door" then "ceiling" else "floor";
        y = if batch.type == "base" then 0 else
          ((world.sector map state batch.sector).${field} - (builtins.elemAt map.sectors batch.sector).${field}) / 64.0;
    in model batch.name y
  ) geometry.batches;
  sprite = actor:
    let
      info = rules.types.${toString actor.type};
      monster = info.kind == "monster";
      age = if actor.deathTic == null then 0 else state.tic - actor.deathTic;
      death = info.death or "";
      frame = if actor.hp <= 0 && monster then builtins.substring (min (builtins.stringLength death - 1) (builtins.div age 6)) 1 death
        else if actor.hurt > 0 && monster then info.pain
        else if state.tic - actor.attackTic < 12 && monster then (if builtins.elem actor.type [ 3004 9 ] then "F" else "G")
        else if actor.alert && monster then builtins.substring (builtins.floor (m.mod (builtins.div state.tic 8) 4)) 1 "ABCD"
        else "A";
      relative = m.atan2 (p.y - actor.y) (p.x - actor.x) - actor.moveAngle;
      rotation = 1 + int (m.mod (int ((relative + m.pi / 8) / (m.tau / 8))) 8);
      requested = if !monster then info.sprite else "${info.sprite}${frame}${toString rotation}";
      chosen = variants.${requested} or variants.${"${info.sprite}${frame}0"} or
        variants.${"${info.sprite}A1"} or { name = info.sprite; flip = false; };
      image = wad.patch chosen.name;
      light = if state.muzzle > 0 || p.light > 0 || p.invulnerability > 0 then 255
        else (world.sector map state (world.sectorAt map actor)).light;
      z = max actor.z (world.sector map state (world.sectorAt map actor)).floor;
      max = m.max;
      shift = image.width / 2.0 - image.left;
    in ray.billboard {
      texture = "p-${chosen.name}";
      position = { x = (actor.x + m.sin p.angle * shift) / 64.0;
        y = (z + image.top - image.height / 2.0) / 64;
        z = -(actor.y - m.cos p.angle * shift) / 64.0; };
      width = image.width / 64.0; height = image.height / 64.0;
      flipX = chosen.flip;
      tint = [ light light light (if info.spectre or false then 70 else 255) ];
    };
  ordered = builtins.sort (a: b: m.distance a p > m.distance b p) state.actors;
  sprites = builtins.map sprite (builtins.filter (a:
    (a.x - p.x) * m.cos p.angle + (a.y - p.y) * m.sin p.angle > -64
    && (a.hp > 0 || rules.types.${toString a.type}.kind == "monster")
  ) ordered);
  bolts = builtins.map (bolt: ray.billboard {
    texture = "p-${bolt.sprite}";
    position = { x = bolt.x / 64; y = bolt.z / 64; z = -bolt.y / 64; };
    width = 0.4; height = 0.4;
  }) state.projectiles;
  w = rules.weapons.${p.weapon};
  gun = if p.weaponState == null then w.ready else (builtins.elemAt w.states p.weaponState).sprite;
  bob = min 6 ((p.momx * p.momx + p.momy * p.momy) / 16);
  weapon = [ (at gun (m.cos (state.tic * m.pi / 20) * bob) (m.abs (m.sin (state.tic * m.pi / 20)) * bob)) ]
    ++ (if state.muzzle <= 0 then [] else if p.weapon == "pistol" then [ (at "PISFA0" 0 0) ]
      else if p.weapon == "shotgun" then [ (at "SHTFA0" 0 0) ]
      else if p.weapon == "chaingun" then [ (at "CHGFA0" 0 0) ] else []);
  faceLevel = min 4 (builtins.div ((100 - min 100 p.hp) * 5) 101);
  face = if p.hp <= 0 then "STFDEAD0" else if p.invulnerability > 0 then "STFGOD0"
    else if state.damageCount > 20 then "STFOUCH${toString faceLevel}"
    else "STFST${toString faceLevel}${toString (builtins.floor (m.mod (builtins.div state.tic 17) 3))}";
  hud = [ (patch "STBAR" 0 168) (at "STARMS" 104 168) (at face 143 168)
    (at "STTPRCNT" 90 171) (at "STTPRCNT" 221 171) ]
    ++ digits "STTNUM" p.hp 90 171 ++ digits "STTNUM" p.armor 221 171
    ++ (if w.ammo == null then [] else digits "STTNUM" p.${w.ammo} 44 171)
    ++ m.concatMap (entry:
      digits "STYSNUM" p.${entry.name} 288 entry.y
      ++ digits "STYSNUM" (entry.max * (if p.backpack then 2 else 1)) 314 entry.y
    ) [ { name = "bullets"; max = 200; y = 173; } { name = "shells"; max = 50; y = 179; }
      { name = "rockets"; max = 50; y = 191; } { name = "cells"; max = 300; y = 185; } ]
    ++ m.concatMap (entry: if !builtins.elem entry.key p.keys then [] else [ (at "STKEYS${toString entry.icon}" 239 entry.y) ])
      [ { key = "blue"; icon = 0; y = 171; } { key = "yellow"; icon = 1; y = 181; } { key = "red"; icon = 2; y = 191; } ]
    ++ m.concatMap (entry: [ (at "${if builtins.elem entry.name p.weapons then "STYSNUM" else "STGNUM"}${toString entry.number}" entry.x entry.y) ])
      [ { name = "pistol"; number = 2; x = 111; y = 172; } { name = "shotgun"; number = 3; x = 123; y = 172; }
        { name = "chaingun"; number = 4; x = 135; y = 172; } { name = "rocket"; number = 5; x = 111; y = 182; }
        { name = "plasma"; number = 6; x = 123; y = 182; } { name = "bfg"; number = 7; x = 135; y = 182; } ];
  sky = ray.texture { texture = "sky"; x = 0; y = 0; width = 320; height = 168;
    source = { x = int (m.mod (-p.angle * 1024 / m.tau) 256); y = 0; width = 320; height = 128; }; };
  scale = min (300.0 / (map.bounds.right - map.bounds.left)) (150.0 / (map.bounds.top - map.bounds.bottom));
  mapPoint = a: { x = int (10 + (a.x - map.bounds.left) * scale); y = int (8 + (map.bounds.top - a.y) * scale); };
  automap = [ (rect 0 0 320 168 black) ] ++ builtins.map (line:
    let a = mapPoint line.a; b = mapPoint line.b;
    in ray.line { x1 = a.x; y1 = a.y; x2 = b.x; y2 = b.y;
      color = if line.back == null then [ 184 0 0 255 ] else if line.special != 0 then [ 255 255 0 255 ] else [ 112 72 0 255 ]; }
  ) (builtins.filter (line: (p.allmap || state.discovered ? ${toString line.id}) && builtins.bitAnd line.flags 128 == 0) map.lines)
    ++ [ (let a = mapPoint p; b = mapPoint { x = p.x + m.cos p.angle * 80; y = p.y + m.sin p.angle * 80; };
      in ray.line { x1 = a.x; y1 = a.y; x2 = b.x; y2 = b.y; color = white; }) ];
  title = [ (patch "TITLEPIC" 0 0) ] ++ (if !state.menu then [] else [
    (at "M_DOOM" 94 2) (at "M_NEWG" 97 64) (at "M_SKILL" 54 92)
    (at (builtins.elemAt [ "M_JKILL" "M_ROUGH" "M_HURT" "M_ULTRA" "M_NMARE" ] state.skill) 48 118)
    (at "M_SKULL1" 16 118)
  ]);
  stats = [ (patch "WIMAP0" 0 0) (at "WILV0${toString state.level}" 90 2) (at "WIF" 114 20)
    (at "WIOSTK" 50 50) (at "WIOSTI" 50 80) (at "WISCRT2" 50 110)
    (at "WITIME" 16 160) (at "WIPAR" 176 160) ]
    ++ digits "WINUM" (if state.totalMonsters == 0 then 100 else builtins.div (state.kills * 100) state.totalMonsters) 270 50
    ++ digits "WINUM" state.items 270 80
    ++ digits "WINUM" (if state.totalMapSecrets == 0 then 100 else builtins.div (state.secrets * 100) state.totalMapSecrets) 270 110
    ++ digits "WINUM" (builtins.div state.tic 35) 145 160
    ++ digits "WINUM" (builtins.elemAt rules.pars state.level) 300 160;
  messageCommands = if state.messageTics <= 0 then [] else font state.message 0 0;
  surface = if state.phase == "title" then title else if state.phase == "intermission" then stats
    else if state.phase == "victory" then [ (patch "CREDIT" 0 0) ] else [
      (ray.texture { texture = "world"; x = 0; y = 0; })
    ] ++ (if state.showMap then automap else []) ++ hud ++ messageCommands
      ++ (if state.damageCount <= 0 then [] else [ (rect 0 0 320 200 [ 255 0 0 (min 110 (state.damageCount * 3)) ]) ])
      ++ (if state.bonusCount <= 0 then [] else [ (rect 0 0 320 200 [ 215 187 69 (state.bonusCount * 4) ]) ])
      ++ (if state.paused then font "PAUSED" 136 72 else []);
in [
  (ray.clear black)
] ++ (if builtins.elem state.phase [ "title" "intermission" "victory" ] then [] else [
  (ray.paint { texture = "world"; commands = [ (ray.clear black) sky
    (ray.camera3D { inherit camera; commands = models ++ sprites ++ bolts; })
  ] ++ (if state.phase == "dead" then [] else weapon); })
]) ++ [
  (ray.paint { texture = "screen"; commands = [ (ray.clear black) ] ++ surface; })
  (ray.texture { texture = "screen"; x = 0; y = 0; width = 960; height = 720; })
]
