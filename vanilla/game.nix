{ wad }:
let
  m = import ../math.nix;
  world = import ./world.nix;
  rules = import ./rules.nix;
  geometry = import ./geometry.nix { inherit wad; };
  inherit (m) min max clamp;
  mod = a: b: a - builtins.div a b * b;
  fixed = x: builtins.floor (x * 65536) / 65536.0;
  currentMap = s: builtins.elemAt wad.maps s.level;
  random = s: let index = mod (s.rng + 1) 256;
    in { state = s // { rng = index; }; value = builtins.elemAt rules.random index; };
  sound = s: name: s // { events = s.events ++ [ name ]; };
  message = s: text: s // { message = text; messageTics = 140; };
  initial = { level ? 0, skill ? 2 }:
    let
      map = builtins.elemAt wad.maps level;
      spawn = builtins.head (builtins.filter (t: t.type == 1) map.things);
      skillFlag = if skill < 2 then 1 else if skill == 2 then 2 else 4;
      things = builtins.filter (t: builtins.bitAnd t.flags skillFlag != 0 && builtins.bitAnd t.flags 16 == 0
        && builtins.hasAttr (toString t.type) rules.types) map.things;
      actor = thing:
        let info = rules.types.${toString thing.type};
        in thing // { z = (builtins.elemAt map.sectors (world.sectorAt map thing)).floor;
          hp = info.hp or 1; radius = info.radius; height = info.height;
          alert = false; hurt = 0; cooldown = 35; deathTic = null; attackTic = -100;
          target = -1; moveAngle = thing.angle * m.pi / 180; spawnX = thing.x; spawnY = thing.y;
        };
    in {
      inherit level skill;
      phase = "title"; menu = false; paused = false;
      player = { inherit (spawn) x y; angle = spawn.angle * m.pi / 180;
        z = (builtins.elemAt map.sectors (world.sectorAt map spawn)).floor;
        radius = 16; height = 56; momx = 0.0; momy = 0.0; momz = 0.0;
        hp = 100; armor = 0; armorType = 0; bullets = 50; shells = 0; rockets = 0; cells = 0;
        weapons = [ "fist" "pistol" ]; weapon = "pistol"; keys = [];
        backpack = false; berserk = false; invulnerability = 0; invisibility = 0; suit = 0; light = 0;
        allmap = false; weaponState = null; weaponTics = 0; refire = false; teleportTics = 0;
      };
      actors = builtins.map actor things;
      sectors = {}; movers = {}; activated = {}; switches = {}; discovered = {};
      projectiles = []; rng = 0; tic = 0; accumulator = 0.0;
      kills = 0; items = 0; secrets = 0; totalKills = 0; totalSecrets = 0;
      totalMonsters = builtins.length (builtins.filter (t: rules.types.${toString t.type}.kind == "monster") things);
      totalItems = builtins.length (builtins.filter (t: builtins.elem rules.types.${toString t.type}.kind
        [ "healthBonus" "armorBonus" "soul" "invulnerability" "berserk" "invisibility" "suit" "map" "light" ]) things);
      totalMapSecrets = builtins.length (builtins.filter (s: s.special == 9) map.sectors);
      showMap = false; muted = false; captured = false; turnHeld = 0;
      damageCount = 0; bonusCount = 0; muzzle = 0; message = ""; messageTics = 0;
      events = []; secretExit = false;
    };
  setSector = s: id: attrs: s // { sectors = s.sectors // {
    ${toString id} = (s.sectors.${toString id} or {}) // attrs;
  }; };
  damagePlayer = s: amount:
    let
      p = s.player;
      damage = if s.skill == 0 then builtins.div amount 2 else amount;
      saved = min p.armor (builtins.div damage (if p.armorType == 2 then 2 else 3));
      hp = max 0 (p.hp - damage + saved);
    in if p.invulnerability > 0 || p.hp <= 0 then s else (sound s "DSPLPAIN") // {
      player = p // { inherit hp; armor = p.armor - saved; };
      damageCount = min 100 (s.damageCount + damage);
      phase = if hp <= 0 then "dead" else s.phase;
    };
  damageActor = s: id: amount: source:
    let
      old = builtins.head (builtins.filter (a: a.id == id) s.actors);
      info = rules.types.${toString old.type};
      dead = old.hp > 0 && old.hp <= amount;
      result = s // {
        actors = builtins.map (a: if a.id != id then a else a // {
          hp = max 0 (a.hp - amount); hurt = 4; alert = true; target = source;
          deathTic = if dead then s.tic else a.deathTic;
        }) s.actors;
        kills = s.kills + (if dead && info.kind == "monster" then 1 else 0);
      };
      dropType = if old.type == 3004 then 2007 else if old.type == 9 then 2001 else null;
      dropped = if !dead || dropType == null then result else result // {
        actors = result.actors ++ [ (old // { id = 100000 + old.id; type = dropType;
          hp = 1; deathTic = null; radius = 20; height = 16; dropped = true; }) ];
      };
      bossesDead = s.level == 7 && old.type == 3003 && dead && !builtins.any (a: a.type == 3003 && a.hp > 0) result.actors;
      bossFloor = if !bossesDead then dropped else builtins.foldl' (acc: sector:
        if sector.tag != 666 then acc else startFloor acc sector.id "lowest" 1 false
      ) dropped (currentMap s).sectors;
      exploded = if !dead || info.kind != "barrel" then bossFloor else
        builtins.foldl' (acc: a:
          let distance = max 0 (max (m.abs (a.x - old.x)) (m.abs (a.y - old.y)) - a.radius);
          in if a.id == id || a.hp <= 0 || distance >= 128 ||
            !builtins.elem rules.types.${toString a.type}.kind [ "monster" "barrel" ] ||
            !world.visible (currentMap s) acc old a then acc
            else damageActor acc a.id (builtins.floor (128 - distance)) source
        ) (if m.distance old bossFloor.player < 144 then damagePlayer bossFloor
          (builtins.floor (144 - m.distance old bossFloor.player)) else bossFloor) bossFloor.actors;
    in if !dead then dropped else sound exploded (if info.kind == "barrel" then "DSBAREXP"
      else if old.type == 3003 then "DSBRSDTH" else if old.type == 3001 then "DSBGDTH1" else "DSPODTH1");
  startMover = s: id: mover: s // { movers = s.movers // { ${toString id} = mover; }; };
  startDoor = s: id: mode:
    let
      sector = world.sector (currentMap s) s id;
      neighbors = builtins.map (n: world.sector (currentMap s) s n) (world.adjacent (currentMap s) id);
      target = builtins.foldl' min 32767 (builtins.map (n: n.ceiling) neighbors) - 4;
      active = s.movers.${toString id} or null;
    in if active != null then (if active.direction < 0 then startMover s id (active // { direction = 1; target = target; }) else s)
      else startMover (sound s (if mode == "close" then "DSDORCLS" else "DSDOROPN")) id {
        type = "ceiling"; direction = if mode == "close" then -1 else 1; speed = 2;
        target = if mode == "close" then sector.floor else target;
        wait = if mode == "raise" then 150 else if mode == "close30" then 1050 else 0;
        returnTarget = if mode == "close30" then target else sector.floor;
        returnDirection = if mode == "close30" then 1 else -1;
        phase = "moving"; timer = 0;
      };
  startFloor = s: id: mode: speed: returns:
    let
      sector = world.sector (currentMap s) s id;
      neighbors = builtins.map (n: world.sector (currentMap s) s n) (world.adjacent (currentMap s) id);
      floors = builtins.map (n: n.floor) neighbors;
      higher = builtins.filter (h: h > sector.floor) floors;
      target = if mode == "lowest" then builtins.foldl' min sector.floor floors
        else if mode == "highest" then builtins.foldl' max (-32768) floors
        else if mode == "turboLower" then builtins.foldl' max (-32768) (builtins.filter (h: h < sector.floor) floors) + 8
        else if mode == "ceiling" then builtins.foldl' min sector.ceiling (builtins.map (n: n.ceiling) neighbors)
        else if mode == "step8" then sector.floor + 8
        else if higher == [] then sector.floor else builtins.foldl' min 32767 higher;
    in if s.movers ? ${toString id} then s else startMover (sound s "DSPSTART") id {
      type = "floor"; direction = if target >= sector.floor then 1 else -1;
      inherit speed target; wait = if returns then 105 else 0;
      returnTarget = sector.floor; returnDirection = 1; phase = "moving"; timer = 0;
    };
  floorTarget = s: id: target: speed:
    let sector = world.sector (currentMap s) s id;
    in if s.movers ? ${toString id} then s else startMover (sound s "DSPSTART") id {
      type = "floor"; direction = if target >= sector.floor then 1 else -1;
      inherit speed target; wait = 0; returnTarget = sector.floor; returnDirection = 1; phase = "moving"; timer = 0;
    };
  stairs = s: first:
    let
      map = currentMap s; texture = (world.sector map s first).floorTexture;
      walk = acc: id: height: visited:
        let
          updated = floorTarget acc id height 0.25;
          next = builtins.filter (line: line.front == id && line.back != null
            && !builtins.elem line.back visited && (world.sector map s line.back).floorTexture == texture) map.lines;
        in if next == [] then updated else let idNext = (builtins.head next).back;
          in walk updated idNext (height + 8) (visited ++ [ idNext ]);
    in walk s first ((world.sector (currentMap s) s first).floor + 8) [ first ];
  donut = s: id:
    let
      map = currentMap s; neighbors = world.adjacent map id;
      pool = if neighbors == [] then null else builtins.head neighbors;
      outer = if pool == null then [] else builtins.filter (n: n != id) (world.adjacent map pool);
      target = if outer == [] then null else world.sector map s (builtins.head outer);
    in if target == null then s else
      floorTarget (floorTarget (setSector s pool { floorTexture = target.floorTexture; special = 0; }) id target.floor 0.5)
        pool target.floor 0.5;
  activate = s: line: trigger:
    let
      code = if s.activated ? ${toString line.id} then 0 else line.special;
      use = trigger == "use";
      valid = if use then builtins.elem code rules.useSpecials
        else if trigger == "gun" then code == 46 else builtins.elem code rules.walkSpecials;
      key = if builtins.elem code [ 26 32 99 ] then "blue" else if builtins.elem code [ 27 34 ] then "yellow"
        else if builtins.elem code [ 28 33 ] then "red" else null;
      direct = builtins.elem code [ 1 26 27 28 31 32 33 34 117 118 ];
      ids = if direct && line.back != null then [ line.back ] else builtins.map (sec: sec.id)
        (builtins.filter (sec: sec.tag == line.tag && line.tag != 0) (currentMap s).sectors);
      one = acc: id:
        if builtins.elem code [ 1 4 26 27 28 29 63 90 ] then startDoor acc id "raise"
        else if builtins.elem code [ 2 31 32 33 34 46 61 86 103 ] then startDoor acc id "open"
        else if builtins.elem code [ 3 42 50 75 ] then startDoor acc id "close"
        else if builtins.elem code [ 16 76 ] then startDoor acc id "close30"
        else if builtins.elem code [ 62 88 ] then startFloor acc id "lowest" 4 true
        else if builtins.elem code [ 23 82 ] then startFloor acc id "lowest" 1 false
        else if builtins.elem code [ 36 70 98 ] then startFloor acc id "turboLower" 4 false
        else if builtins.elem code [ 5 91 ] then startFloor acc id "ceiling" 1 false
        else if builtins.elem code [ 7 8 ] then stairs acc id
        else if code == 9 then donut acc id
        else if builtins.elem code [ 18 20 22 ] then startFloor acc id "next" 1 false
        else if code == 35 then setSector acc id { light = 35; } else acc;
      result = builtins.foldl' one s ids;
      destination = if code != 97 then [] else builtins.filter (t: t.type == 14 &&
        (builtins.elemAt (currentMap s).sectors (world.sectorAt (currentMap s) t)).tag == line.tag) (currentMap s).things;
      teleported = if destination == [] then result else let d = builtins.head destination;
        in (sound result "DSTELEPT") // { player = result.player // { inherit (d) x y;
          z = (world.sector (currentMap s) s (world.sectorAt (currentMap s) d)).floor;
          angle = d.angle * m.pi / 180; momx = 0.0; momy = 0.0; teleportTics = 18; }; };
    in if !valid then s else if key != null && !builtins.elem key s.player.keys
      then sound (message s "YOU NEED THE ${key} KEY TO OPEN THIS DOOR") "DSOOF"
      else if builtins.elem code [ 11 51 52 ] then sound (s // { phase = "intermission"; secretExit = code == 51; }) "DSSWTCHN"
      else teleported // {
        activated = s.activated // (if builtins.elem code rules.repeatSpecials then {} else { ${toString line.id} = true; });
        switches = teleported.switches // (if !use || direct then {} else { ${toString line.id} = s.tic; });
      };
  useLines = s:
    let p = s.player; hits = world.intersections (currentMap s) p { x = m.cos p.angle; y = m.sin p.angle; } 64;
        visit = acc: hit:
          if acc.stopped then acc else if hit.line.special != 0 then {
            state = activate acc.state hit.line "use"; stopped = true;
          } else let gap = world.opening (currentMap s) s hit.line;
            in if hit.line.back == null || gap.ceiling <= gap.floor then {
              state = sound acc.state "DSOOF"; stopped = true;
            } else acc;
    in (builtins.foldl' visit { state = s; stopped = false; } hits).state;
  moversTic = s: builtins.foldl' (acc: id:
    let
      mover = acc.movers.${id}; sector = world.sector (currentMap s) acc (builtins.fromJSON id);
      current = sector.${mover.type};
      next = if mover.direction > 0 then min mover.target (current + mover.speed) else max mover.target (current - mover.speed);
      playerHere = world.sectorAt (currentMap s) acc.player == sector.id;
      blocked = mover.type == "ceiling" && mover.direction < 0 && next - sector.floor < 56
        && (playerHere || builtins.any (a: a.hp > 0 && rules.types.${toString a.type}.solid &&
          world.sectorAt (currentMap s) a == sector.id) acc.actors);
      updated = if blocked then acc else setSector acc sector.id { ${mover.type} = next; };
      remove = state: state // { movers = builtins.removeAttrs state.movers [ id ]; };
    in if mover.phase == "waiting" then
      if mover.timer > 1 then startMover acc sector.id (mover // { timer = mover.timer - 1; })
      else startMover (sound acc (if mover.type == "ceiling" then "DSDORCLS" else "DSPSTART")) sector.id
        (mover // { phase = "returning"; target = mover.returnTarget; direction = mover.returnDirection; })
      else if blocked then startMover acc sector.id (mover // { direction = 1;
        target = builtins.foldl' min 32767 (builtins.map (n: (world.sector (currentMap s) s n).ceiling)
          (world.adjacent (currentMap s) sector.id)) - 4; })
      else if next != mover.target then updated
      else if mover.wait > 0 && mover.phase == "moving" then startMover updated sector.id (mover // { phase = "waiting"; timer = mover.wait; })
      else remove (if mover.type == "floor" then sound updated "DSPSTOP" else updated)
  ) s (builtins.attrNames s.movers);
  movePlayer = s: input:
    let
      p = s.player; speed = if input.run then 1 else 0;
      held = if input.turn == 0 then 0 else s.turnHeld + 1;
      turn = (if held < 6 then 320 else if input.run then 1280 else 640) * m.tau / 65536;
      angle = m.wrap (p.angle - input.turn * turn + input.look);
      forward = input.forward * builtins.elemAt rules.player.forward speed / 32.0;
      strafe = input.strafe * builtins.elemAt rules.player.side speed / 32.0;
      momx = clamp (-30) 30 (p.momx + forward * m.cos angle + strafe * m.sin angle);
      momy = clamp (-30) 30 (p.momy + forward * m.sin angle - strafe * m.cos angle);
      moved = if p.teleportTics > 0 then p else world.move (currentMap s) s p momx momy;
      overlaps = builtins.any (a: a.hp > 0 && rules.types.${toString a.type}.solid
        && m.abs (a.x - moved.x) < a.radius + p.radius && m.abs (a.y - moved.y) < a.radius + p.radius
        && a.z + a.height > moved.z && a.z < moved.z + moved.height) s.actors;
      position = if overlaps then p else moved;
      crossed = builtins.filter (l: l.special != 0 && world.side l p * world.side l position < 0
        && world.distanceToLine l position < m.length momx momy + 1) (world.blockLines (currentMap s) position 64);
      floor = (world.sector (currentMap s) s (world.sectorAt (currentMap s) position)).floor;
      z = max floor (position.z + p.momz);
      updated = s // { turnHeld = held; player = position // {
        inherit angle z;
        momx = if m.abs momx < 0.0625 && input.forward == 0 && input.strafe == 0 then 0.0 else fixed (momx * 0.90625);
        momy = if m.abs momy < 0.0625 && input.forward == 0 && input.strafe == 0 then 0.0 else fixed (momy * 0.90625);
        momz = if z <= floor then 0.0 else p.momz - 1;
      }; discovered = s.discovered // builtins.listToAttrs (builtins.map (line: {
        name = toString line.id; value = true;
      }) (world.blockLines (currentMap s) position 256)); };
    in builtins.foldl' (acc: line: activate acc line "walk") updated crossed;
  pickup = s: actor:
    let
      p = s.player; info = rules.types.${toString actor.type}; kind = info.kind; amount = info.amount or 0;
      cap = ammo: (if p.backpack then 2 else 1) * { bullets = 200; shells = 50; rockets = 50; cells = 300; }.${ammo};
      ammoAmount = (if s.skill == 0 || s.skill == 4 then 2 else 1) *
        (if actor.dropped or false then builtins.div amount 2 else amount);
      weapon = builtins.elem kind [ "shotgun" "chaingun" "rocket" "chainsaw" ];
      ammo = if kind == "shotgun" then "shells" else if kind == "chaingun" then "bullets" else "rockets";
      next = if kind == "health" then (if p.hp >= 100 then null else p // { hp = min 100 (p.hp + amount); })
        else if kind == "healthBonus" then p // { hp = min 200 (p.hp + 1); }
        else if kind == "soul" then p // { hp = min 200 (p.hp + 100); }
        else if kind == "armorBonus" then p // { armor = min 200 (p.armor + 1); armorType = max 1 p.armorType; }
        else if builtins.elem kind [ "greenArmor" "blueArmor" ] then
          (if p.armor >= amount then null else p // { armor = amount; armorType = if kind == "blueArmor" then 2 else 1; })
        else if builtins.elem kind [ "bullets" "shells" "rockets" "cells" ] then
          (if p.${kind} >= cap kind then null else p // { ${kind} = min (cap kind) (p.${kind} + ammoAmount); })
        else if weapon then p // {
          weapons = p.weapons ++ (if builtins.elem kind p.weapons then [] else [ kind ]);
          weapon = if builtins.elem kind p.weapons then p.weapon else kind;
          ${ammo} = if kind == "chainsaw" then p.${ammo} else min (cap ammo) (p.${ammo} + ammoAmount);
          weaponState = null;
        }
        else if kind == "backpack" then p // { backpack = true; bullets = min 400 (p.bullets + 10);
          shells = min 100 (p.shells + 4); rockets = min 100 (p.rockets + 1); cells = min 600 (p.cells + 20); }
        else if kind == "berserk" then p // { hp = max 100 p.hp; berserk = true; weapon = "fist"; }
        else if kind == "map" then p // { allmap = true; }
        else if builtins.elem kind [ "invulnerability" "invisibility" "suit" "light" ] then p // { ${kind} = amount; }
        else if builtins.elem kind [ "blueKey" "redKey" "yellowKey" ] then
          let key = builtins.replaceStrings [ "Key" ] [ "" ] kind;
          in p // { keys = p.keys ++ (if builtins.elem key p.keys then [] else [ key ]); }
        else null;
    in if next == null then s else (sound (message s (builtins.replaceStrings [ "_" ] [ " " ] ("PICKED UP " + kind)))
      (if weapon then "DSWPNUP" else if builtins.elem kind [ "soul" "invulnerability" "berserk" "invisibility" ] then "DSGETPOW" else "DSITEMUP")) // {
        player = next; bonusCount = 6; items = s.items + (if builtins.elem kind
          [ "healthBonus" "armorBonus" "soul" "invulnerability" "berserk" "invisibility" "suit" "map" "light" ] then 1 else 0);
        actors = builtins.filter (a: a.id != actor.id) s.actors;
      };
  collect = s: builtins.foldl' pickup s (builtins.filter (a:
    let info = rules.types.${toString a.type};
    in info.kind != "monster" && info.kind != "decor" && info.kind != "barrel"
      && m.abs (a.x - s.player.x) < 36 && m.abs (a.y - s.player.y) < 36 && m.abs (a.z - s.player.z) < 56
  ) s.actors);
  pellet = s: angle: damage: range:
    let
      p = s.player; dx = m.cos angle; dy = m.sin angle;
      targets = builtins.sort (a: b: a.depth < b.depth) (builtins.filter (a: a.hp > 0 && a.depth > 0
        && a.depth < range && a.offset < a.radius && builtins.elem rules.types.${toString a.type}.kind [ "monster" "barrel" ]
        && world.visible (currentMap s) s p a)
        (builtins.map (a: a // { depth = (a.x - p.x) * dx + (a.y - p.y) * dy;
          offset = m.abs ((a.x - p.x) * dy - (a.y - p.y) * dx); }) s.actors));
    in if targets == [] then s else damageActor s (builtins.head targets).id damage (-1);
  weaponAction = s: action:
    let
      p = s.player; w = rules.weapons.${p.weapon};
      enough = w.ammo == null || p.${w.ammo} > 0;
      fired = sound (s // { muzzle = if action == "punch" then 0 else 7;
        player = if w.ammo == null then p else p // { ${w.ammo} = p.${w.ammo} - 1; };
        actors = builtins.map (a: if rules.types.${toString a.type}.kind == "monster" && m.distance p a < 1400
          then a // { alert = true; } else a) s.actors;
      }) w.sound;
      shots = builtins.foldl' (acc: _:
        let r = random acc; r2 = random r.state; r3 = random r2.state;
            inaccurate = action == "punch" || p.weapon == "shotgun" || p.refire;
            spread = if inaccurate then (r2.value - r3.value) * m.tau / 524288 else 0;
            damage = if action == "punch" then (mod r.value 10 + 1) * 2 * (if p.berserk && p.weapon == "fist" then 10 else 1)
              else 5 * (mod r.value 3 + 1);
        in pellet (if inaccurate then r3.state else r.state) (p.angle + spread) damage w.range
      ) fired (m.range w.pellets);
    in if action == null || action == "refire" || !enough then s
      else if action == "rocket" then fired // { projectiles = fired.projectiles ++ [ {
        x = p.x; y = p.y; z = p.z + 32; vx = m.cos p.angle * 20; vy = m.sin p.angle * 20; vz = 0.0;
        sprite = "MISLA1"; source = -1; damage = 20; radius = 6; height = 8; life = 175;
      } ]; } else shots;
  weaponTic = s: input:
    let
      p = s.player; w = rules.weapons.${p.weapon}; active = p.weaponState != null;
      exhausted = w.ammo != null && p.${w.ammo} <= 0;
      enter = state: index:
        if index >= builtins.length w.states then state // { player = state.player // { weaponState = null; refire = input.fire; }; }
        else let frame = builtins.elemAt w.states index;
                 prepared = state // { player = state.player // { weaponState = index; weaponTics = frame.tics; }; };
                 acted = weaponAction prepared frame.action;
                 enough = w.ammo == null || acted.player.${w.ammo} > 0;
             in if frame.action == "refire" && input.fire && enough then
               enter (acted // { player = acted.player // { refire = true; }; }) 0
             else if frame.tics == 0 then enter acted (index + 1) else acted;
    in if active then (if p.weaponTics > 1 then s // { player = p // { weaponTics = p.weaponTics - 1; }; }
      else enter s (p.weaponState + 1))
      else if input.fire && !exhausted then enter s 0
      else if exhausted && input.fire then message s "OUT OF AMMO"
      else s // { player = p // { refire = false; }; };
  enemyTic = acc: actor:
    let
      s = acc.state; info = rules.types.${toString actor.type}; p = s.player;
      distance = m.distance actor p;
      # Perception/chase decisions follow the original coarse monster cadence.
      think = mod (s.tic + actor.id) (if s.skill == 4 then 2 else 4) == 0;
      sees = distance < 2048 && think && world.visible (currentMap s) s actor p;
      alert = actor.alert || sees;
      r = random s;
      attack = think && alert && sees && actor.cooldown <= 0 && (distance < 64 || mod r.value 256 < 64);
      direction = { x = (p.x - actor.x) / max 1 distance; y = (p.y - actor.y) / max 1 distance; };
      speed = info.speed or 0;
      moved = if !think || !alert || distance < 56 || attack then actor else
        world.move (currentMap s) s actor (direction.x * speed) (direction.y * speed);
      position = if m.distance moved p < actor.radius + 16 then actor else moved;
      next = position // { inherit alert; hurt = max 0 (actor.hurt - 1);
        cooldown = if attack then (if s.skill == 4 then 15 else 35) else max 0 (actor.cooldown - 1);
        attackTic = if attack then s.tic else actor.attackTic;
        moveAngle = if !alert then actor.moveAngle else
          (if direction.x >= 0 then (if direction.y >= 0 then 1 else -1) else (if direction.y >= 0 then 3 else -3)) * m.pi / 4;
      };
      damage = if actor.type == 3003 then 8 * (mod r.value 8 + 1) else if actor.type == 3002 || actor.type == 58
        then 4 * (mod r.value 10 + 1) else 3 * (mod r.value 8 + 1);
      hitscan = builtins.elem actor.type [ 3004 9 ];
      attacked = if !attack then s else if hitscan || distance < 64 then damagePlayer r.state
        (if hitscan then (mod r.value 5 + 1) * 3 * (if actor.type == 9 then 3 else 1) else damage)
        else r.state // { projectiles = s.projectiles ++ [ {
          x = actor.x + direction.x * 20; y = actor.y + direction.y * 20; z = actor.z + 32;
          vx = direction.x * (if actor.type == 3003 then 15 else 10);
          vy = direction.y * (if actor.type == 3003 then 15 else 10);
          vz = (p.z + 32 - actor.z - 32) / max 1 (distance / 10);
          sprite = if actor.type == 3003 then "BAL7A1" else "BAL1A0";
          source = actor.id; inherit damage; radius = 6; height = 8; life = 175;
        } ]; };
    in if info.kind != "monster" || actor.hp <= 0 || s.phase != "playing" then acc // { actors = acc.actors ++ [ actor ]; }
      else { state = attacked; actors = acc.actors ++ [ next ]; };
  enemiesTic = s:
    let result = builtins.foldl' enemyTic { state = s; actors = []; } s.actors;
    in result.state // { actors = result.actors; };
  projectilesTic = s:
    let result = builtins.foldl' (acc: bolt:
      let
        next = bolt // { x = bolt.x + bolt.vx; y = bolt.y + bolt.vy; z = bolt.z + bolt.vz; life = bolt.life - 1; };
        sector = world.sector (currentMap s) s (world.sectorAt (currentMap s) next);
        wall = !world.fits (currentMap s) s (bolt // { height = 8; }) next || next.z <= sector.floor || next.z >= sector.ceiling;
        playerHit = bolt.source != -1 && m.distance next acc.state.player < 22 && m.abs (next.z - acc.state.player.z - 28) < 32;
        targets = builtins.filter (a: a.id != bolt.source && a.hp > 0 &&
          builtins.elem rules.types.${toString a.type}.kind [ "monster" "barrel" ] && m.distance a next < a.radius + 6
          && next.z >= a.z && next.z < a.z + a.height) acc.state.actors;
        hit = wall || playerHit || targets != [];
        damaged = if playerHit then damagePlayer acc.state bolt.damage else if targets != [] then
          damageActor acc.state (builtins.head targets).id bolt.damage bolt.source else acc.state;
        splash = if !hit || bolt.sprite != "MISLA1" then damaged else
          builtins.foldl' (state: a:
            let distance = max 0 (max (m.abs (a.x - next.x)) (m.abs (a.y - next.y)) - a.radius);
            in if distance >= 128 || a.hp <= 0 || !builtins.elem rules.types.${toString a.type}.kind [ "monster" "barrel" ]
              then state else damageActor state a.id (builtins.floor (128 - distance)) bolt.source
          ) (if m.distance next damaged.player < 128 then damagePlayer damaged (builtins.floor (128 - m.distance next damaged.player)) else damaged)
          damaged.actors;
      in { state = if hit then sound splash "DSBAREXP" else splash;
        projectiles = acc.projectiles ++ (if hit || next.life <= 0 then [] else [ next ]); }
    ) { state = s; projectiles = []; } s.projectiles;
    in result.state // { projectiles = result.projectiles; };
  sectorTic = s:
    let
      id = world.sectorAt (currentMap s) s.player; sector = world.sector (currentMap s) s id;
      secret = sector.special == 9;
      base = if secret then (setSector s id { special = 0; }) // { secrets = s.secrets + 1; } else s;
      hurt = builtins.elem sector.special [ 5 7 16 11 ] && mod s.tic 32 == 0 && s.player.z <= sector.floor;
      amount = if sector.special == 7 then 5 else if sector.special == 5 then 10 else 20;
      damaged = if hurt && (s.player.suit <= 0 || sector.special == 11) then damagePlayer base amount else base;
    in if sector.special == 11 && damaged.player.hp <= 10 then damaged // { phase = "victory"; } else damaged;
  tic = previous: input:
    let
      timers = previous // {
        tic = previous.tic + 1; damageCount = max 0 (previous.damageCount - 1); bonusCount = max 0 (previous.bonusCount - 1);
        muzzle = max 0 (previous.muzzle - 1); messageTics = max 0 (previous.messageTics - 1);
        player = previous.player // {
          invulnerability = max 0 (previous.player.invulnerability - 1); invisibility = max 0 (previous.player.invisibility - 1);
          suit = max 0 (previous.player.suit - 1); light = max 0 (previous.player.light - 1);
          teleportTics = max 0 (previous.player.teleportTics - 1);
        };
      };
      moved = movePlayer (moversTic timers) input;
      picked = collect moved;
      fired = weaponTic picked input;
      enemies = enemiesTic fired;
      projectiles = projectilesTic enemies;
    in sectorTic projectiles;
  nextLevel = s:
    let level = if s.secretExit then 8 else if s.level == 8 then 3 else s.level + 1;
        fresh = initial { inherit level; inherit (s) skill; };
    in if s.level == 7 then s // { phase = "victory"; }
      else fresh // { phase = "loading"; inherit (s) muted captured;
        totalKills = s.totalKills + s.kills; totalSecrets = s.totalSecrets + s.secrets;
        player = fresh.player // { inherit (s.player) hp armor armorType bullets shells rockets cells weapons weapon backpack berserk; };
      };
  step = previous: { delta ? 0.0, forward ? 0, strafe ? 0, turn ? 0, look ? 0.0,
    run ? false, fire ? false, use ? false, start ? false, pause ? false, restart ? false,
    toggleMap ? false, toggleMute ? false, capture ? false, selectWeapon ? null, skill ? null, level ? null }:
    let
      s = previous // { events = [];
        showMap = if toggleMap then !previous.showMap else previous.showMap;
        muted = if toggleMute then !previous.muted else previous.muted;
        captured = if capture then !previous.captured else previous.captured;
        player = previous.player // { weapon = if selectWeapon != null && builtins.elem selectWeapon previous.player.weapons
          then selectWeapon else previous.player.weapon;
          weaponState = if selectWeapon != null && builtins.elem selectWeapon previous.player.weapons then null else previous.player.weaponState; };
      };
      reset = (initial { inherit (s) level skill; }) // { phase = "playing"; inherit (s) muted captured; };
      time = min 0.25 (max 0.0 delta) + s.accumulator;
      count = min 8 (builtins.floor (time * 35));
      input = { inherit forward strafe turn run fire; look = if count > 0 then look / count else 0.0; };
      advanced = builtins.foldl' (state: _: builtins.deepSeq state
        (if state.phase != "playing" then state else tic state input)) (if use then useLines s else s) (m.range count);
    in if restart then reset
      else if s.phase == "title" then
        if start && !s.menu then s // { menu = true; }
        else if start then (initial { inherit (s) level skill; }) // { phase = "playing"; inherit (s) muted captured; }
        else
          (if level != null && level != s.level then initial { level = clamp 0 8 level; skill = s.skill; } else s)
          // { skill = if skill != null then clamp 0 4 skill else s.skill; }
      else if s.phase == "intermission" then (if start then nextLevel s else s)
      else if s.phase == "victory" then (if start then (initial {}) // { phase = "loading"; inherit (s) muted captured; } else s)
      else if s.phase == "dead" then (if start then reset else s)
      else if s.paused then (if pause || start then s // { paused = false; } else s)
      else if pause then s // { paused = true; }
      else advanced // { accumulator = max 0.0 (time - count / 35.0); };
in { inherit initial step tic currentMap random activate useLines damagePlayer damageActor nextLevel rules world geometry; }
