let
  m = import ./math.nix;
  world = import ./world.nix;
  levels = import ./levels.nix;
  inherit (m) min max clamp;
  enemyRules = {
    guard = { hp = 36; speed = 1.05; damage = 7; interval = 1.5; };
    imp = { hp = 60; speed = 0.85; damage = 12; interval = 1.9; };
    baron = { hp = 240; speed = 0.65; damage = 24; interval = 1.6; };
  };
  weapons = {
    fist = { ammo = null; cost = 0; interval = 0.42; damage = 24; range = 1.35; pellets = [ 0.0 ]; };
    pistol = { ammo = "bullets"; cost = 1; interval = 0.28; damage = 18; range = 32; pellets = [ 0.0 ]; };
    shotgun = { ammo = "shells"; cost = 1; interval = 0.78; damage = 13; range = 24;
      pellets = [ (-0.09) (-0.06) (-0.03) 0.0 0.03 0.06 0.09 ]; };
    chaingun = { ammo = "bullets"; cost = 1; interval = 0.095; damage = 13; range = 30; pellets = [ 0.0 ]; };
  };
  levelFor = state: builtins.elemAt levels state.level;
  initial = { level ? 0, difficulty ? 1 }: let map = builtins.elemAt levels level;
  in {
    inherit level difficulty;
    phase = "title";
    player = map.spawn // {
      hp = 100; armor = 0; bullets = 60; shells = 0;
      weapon = "pistol"; weapons = [ "fist" "pistol" ]; keys = [];
    };
    enemies = builtins.map (e: e // {
      hp = enemyRules.${e.kind}.hp; cooldown = 0.8 + e.id * 0.13;
      alert = false; hurt = 0.0;
    }) map.enemies;
    items = map.items;
    doors = {}; projectiles = [];
    kills = 0; secrets = 0; collected = 0;
    totalKills = 0; totalSecrets = 0; campaignTime = 0.0;
    elapsed = 0.0; cooldown = 0.0; muzzle = 0.0; hurt = 0.0; bonus = 0.0;
    hazardTimer = 0.0; messageTimer = 4.0;
    message = map.subtitle;
    events = []; muted = false; showMap = false; mouseCaptured = false;
    bob = 0.0; shots = 0;
  };
  notify = state: message: state // { inherit message; messageTimer = 2.8; };
  damagePlayer = state: amount:
    if state.player.hp <= 0 || state.hurt > 0.15 then state else
    let
      scaled = max 1 (builtins.floor (amount * builtins.elemAt [ 0.55 1.0 1.4 ] state.difficulty));
      absorbed = min state.player.armor (builtins.div scaled 2);
      hp = max 0 (state.player.hp - scaled + absorbed);
    in state // {
      player = state.player // { inherit hp; armor = state.player.armor - absorbed; };
      hurt = 0.38;
      events = state.events ++ [ "hurt" ];
      phase = if hp == 0 then "dead" else state.phase;
    };
  movePlayer = state: input: dt:
    let
      p = state.player;
      angle = m.wrap (p.angle + clamp (-1) 1 input.turn * dt * 2.35 + clamp (-0.5) 0.5 input.look);
      forward = clamp (-1) 1 input.forward; strafe = clamp (-1) 1 input.strafe;
      norm = max 1.0 (m.length forward strafe);
      speed = if input.run then 4.7 else 3.0;
      dx = (m.cos angle * forward - m.sin angle * strafe) * speed * dt / norm;
      dy = (m.sin angle * forward + m.cos angle * strafe) * speed * dt / norm;
      moved = world.move (levelFor state) state.doors 0.2 p dx dy;
      overlaps = builtins.any (e: e.hp > 0 && m.distance e moved < 0.47) state.enemies;
    in state // {
      player = (if overlaps then p else moved) // { inherit angle; };
      bob = state.bob + (if forward != 0 || strafe != 0 then dt * speed * 2.5 else dt * 1.5);
    };
  interact = state:
    let
      p = state.player; level = levelFor state;
      cells = m.concatMap (dy: map (dx:
        let x = builtins.floor p.x + dx; y = builtins.floor p.y + dy;
            vx = x + 0.5 - p.x; vy = y + 0.5 - p.y;
        in { inherit x y; tile = world.tile level x y;
          distance = m.length vx vy; facing = vx * m.cos p.angle + vy * m.sin p.angle; }
      ) [ (-1) 0 1 ]) [ (-1) 0 1 ];
      nearby = builtins.sort (a: b: a.distance < b.distance)
        (builtins.filter (c: c.distance < 1.55 && (c.facing > 0.25 || c.distance < 0.65)
          && (world.isDoor c.tile || c.tile == "X")) cells);
      target = if nearby == [] then null else builtins.head nearby;
      id = if target == null then "" else world.key target.x target.y;
      bossesAlive = builtins.any (e: e.kind == "baron" && e.hp > 0) state.enemies;
    in if target == null then state
      else if target.tile == "X" then
        if state.level == 2 && bossesAlive then notify state "TERMINATE ALL BARONS TO RELEASE THE EXIT"
        else state // { phase = "intermission"; events = state.events ++ [ "exit" ]; }
      else if builtins.hasAttr id state.doors then state
      else if target.tile == "R" && !builtins.elem "red" p.keys then
        notify state "YOU NEED THE RED KEYCARD"
      else (notify state (if target.tile == "S" then "A SECRET IS REVEALED!" else "ACCESS GRANTED")) // {
        doors = state.doors // { ${id} = 0.01; };
        secrets = state.secrets + (if target.tile == "S" then 1 else 0);
        events = state.events ++ [ "door" ];
      };
  hitEnemy = state: id: damage:
    let
      target = builtins.head (builtins.filter (e: e.id == id) state.enemies);
      killed = target.hp > 0 && target.hp <= damage;
    in state // {
      enemies = map (e: if e.id != id then e else e // {
        hp = max 0 (e.hp - damage); hurt = 0.16; alert = true;
      }) state.enemies;
      kills = state.kills + (if killed then 1 else 0);
      events = state.events ++ (if killed then [ "kill" ] else []);
      items = state.items ++ (if killed && target.kind == "guard" then [ {
        id = 1000 + target.id; kind = "bullets"; inherit (target) x y;
      } ] else []);
    };
  pellet = weapon: angle: state:
    let
      dir = { x = m.cos angle; y = m.sin angle; };
      wall = world.cast (levelFor state) state.doors state.player dir;
      targets = builtins.sort (a: b: a.depth < b.depth) (builtins.filter (e:
        e.hp > 0 && e.depth > 0 && e.depth < min weapon.range wall.distance && e.offset < 0.32
      ) (map (e:
        let dx = e.x - state.player.x; dy = e.y - state.player.y;
        in e // { depth = dx * dir.x + dy * dir.y; offset = m.abs (dx * dir.y - dy * dir.x); }
      ) state.enemies));
    in if targets == [] then state else hitEnemy state (builtins.head targets).id weapon.damage;
  shoot = state:
    let
      p = state.player; w = weapons.${p.weapon};
      enough = w.ammo == null || p.${w.ammo} >= w.cost;
      fired = state // {
        player = if w.ammo == null then p else p // { ${w.ammo} = p.${w.ammo} - w.cost; };
        cooldown = w.interval; muzzle = 0.11; shots = state.shots + 1;
        enemies = map (e: e // { alert = e.alert || m.distance p e < 14; }) state.enemies;
        events = state.events ++ [ (if p.weapon == "fist" then "punch" else p.weapon) ];
      };
    in if state.cooldown > 0 then state else if !enough then
      (notify state "OUT OF AMMO - PRESS 1 FOR FISTS") // { cooldown = 0.25; }
    else builtins.foldl' (s: offset: pellet w (p.angle + offset) s) fired w.pellets;
  pickup = state: item:
    let
      p = state.player; kind = item.kind;
      weapon = builtins.elem kind [ "shotgun" "chaingun" ];
      applicable = weapon || kind == "redkey" ||
        (kind == "health" && p.hp < 100) || (kind == "armor" && p.armor < 100) ||
        (kind == "bullets" && p.bullets < 300) || (kind == "shells" && p.shells < 80);
      next = if kind == "health" then p // { hp = min 100 (p.hp + 30); }
        else if kind == "armor" then p // { armor = min 100 (p.armor + 60); }
        else if kind == "redkey" then p // { keys = [ "red" ]; }
        else if kind == "bullets" then p // { bullets = min 300 (p.bullets + 24); }
        else if kind == "shells" then p // { shells = min 80 (p.shells + 8); }
        else if kind == "shotgun" then p // { shells = min 80 (p.shells + 12); weapon = kind; }
        else p // { bullets = min 300 (p.bullets + 80); weapon = kind; };
      inventory = if weapon then next // {
        weapons = p.weapons ++ (if builtins.elem kind p.weapons then [] else [ kind ]);
      } else next;
      names = { health = "MEDIKIT"; armor = "SECURITY ARMOR"; redkey = "RED KEYCARD";
        bullets = "BULLETS"; shells = "SHELLS"; shotgun = "SHOTGUN"; chaingun = "CHAINGUN"; };
    in if !applicable then state else (notify state "PICKED UP ${names.${kind}}") // {
      player = inventory; bonus = 0.18; collected = state.collected + 1;
      items = builtins.filter (i: i.id != item.id) state.items;
      events = state.events ++ [ "pickup" ];
    };
  collect = state: builtins.foldl' pickup state
    (builtins.filter (i: m.distance state.player i < 0.6) state.items);
  enemyStep = dt: acc: e:
    let
      s = acc.state; p = s.player; rule = enemyRules.${e.kind};
      distance = m.distance e p;
      sees = distance < 14 && world.visible (levelFor s) s.doors e p;
      active = e.alert || sees;
      cooldown = max 0 (e.cooldown - dt);
      canAttack = active && sees && cooldown <= 0 && distance < (if e.kind == "guard" then 9 else 12);
      direction = { x = (p.x - e.x) / max 0.001 distance; y = (p.y - e.y) / max 0.001 distance; };
      moved = if active && distance > (if sees then 2.2 else 0.65) then
        world.move (levelFor s) s.doors 0.22 e (direction.x * rule.speed * dt) (direction.y * rule.speed * dt)
        else e;
      # Enemies cannot walk into the player, even when the player is cornered.
      position = if m.distance moved p < 0.62 then e else moved;
      next = position // { alert = active; hurt = max 0 (e.hurt - dt);
        cooldown = if canAttack then rule.interval else cooldown; };
      melee = canAttack && distance < 1.15;
      hitscan = canAttack && e.kind == "guard";
      attacked = if melee || hitscan then damagePlayer s rule.damage else s;
      bolt = { x = e.x + direction.x * 0.4; y = e.y + direction.y * 0.4;
        vx = direction.x * 3.4; vy = direction.y * 3.4; life = 5.0;
        damage = rule.damage; kind = "fireball"; };
    in if e.hp <= 0 then acc // { enemies = acc.enemies ++ [ e ]; }
      else if s.phase != "playing" then acc // { enemies = acc.enemies ++ [ e ]; }
      else { state = attacked // {
        projectiles = attacked.projectiles ++ (if canAttack && !melee && !hitscan then [ bolt ] else []);
      }; enemies = acc.enemies ++ [ next ]; };
  enemiesStep = state: dt:
    let result = builtins.foldl' (enemyStep dt) { inherit state; enemies = []; } state.enemies;
    in result.state // { inherit (result) enemies; };
  projectilesStep = state: dt:
    let result = builtins.foldl' (acc: bolt:
      let
        next = bolt // { x = bolt.x + bolt.vx * dt; y = bolt.y + bolt.vy * dt; life = bolt.life - dt; };
        hit = m.distance next acc.state.player < 0.35;
        blocked = !world.fits (levelFor state) state.doors 0.08 next.x next.y;
      in { state = if hit then damagePlayer acc.state bolt.damage else acc.state;
        bolts = acc.bolts ++ (if hit || blocked || next.life <= 0 then [] else [ next ]); }
    ) { inherit state; bolts = []; } state.projectiles;
    in result.state // { projectiles = result.bolts; };
  advance = state: input: dt:
    let
      timers = state // {
        elapsed = state.elapsed + dt; campaignTime = state.campaignTime + dt;
        cooldown = max 0 (state.cooldown - dt); muzzle = max 0 (state.muzzle - dt);
        hurt = max 0 (state.hurt - dt); bonus = max 0 (state.bonus - dt);
        messageTimer = max 0 (state.messageTimer - dt);
        doors = builtins.mapAttrs (_: amount: min 1.0 (amount + dt * 1.7)) state.doors;
      };
      moved = movePlayer timers input dt;
      fired = if input.fire && moved.phase == "playing" then shoot moved else moved;
      picked = collect fired;
      enemies = if picked.phase == "playing" then enemiesStep picked dt else picked;
      bolts = if enemies.phase == "playing" then projectilesStep enemies dt else enemies;
      onSlime = world.tile (levelFor bolts) (builtins.floor bolts.player.x) (builtins.floor bolts.player.y) == "~";
      hazard = bolts // { hazardTimer = if onSlime then bolts.hazardTimer + dt else 0.0; };
    in if onSlime && hazard.hazardTimer >= 0.7 && hazard.phase == "playing"
      then (damagePlayer hazard 8) // { hazardTimer = 0.0; } else hazard;
  nextLevel = state:
    if state.level + 1 >= builtins.length levels then state // { phase = "victory"; }
    else let fresh = initial { level = state.level + 1; inherit (state) difficulty; };
    in fresh // {
      phase = "playing"; inherit (state) muted campaignTime;
      totalKills = state.totalKills + state.kills; totalSecrets = state.totalSecrets + state.secrets;
      player = fresh.player // {
        inherit (state.player) hp armor bullets shells weapon weapons;
      };
    };
  step = previous: { delta ? 0.0, forward ? 0, strafe ? 0, turn ? 0, look ? 0,
    run ? false, fire ? false, use ? false, start ? false, pause ? false,
    restart ? false, toggleMap ? false, toggleMute ? false, selectWeapon ? null,
    difficulty ? null, capture ? false }:
    let
      state = previous // {
        events = [];
        muted = if toggleMute then !previous.muted else previous.muted;
        showMap = if toggleMap then !previous.showMap else previous.showMap;
        mouseCaptured = if capture then !previous.mouseCaptured else previous.mouseCaptured;
        difficulty = if previous.phase == "title" && difficulty != null
          then clamp 0 2 difficulty else previous.difficulty;
        player = previous.player // {
          weapon = if selectWeapon != null && builtins.elem selectWeapon previous.player.weapons
            then selectWeapon else previous.player.weapon;
        };
      };
      reset = (initial { inherit (state) level difficulty; }) // {
        phase = "playing"; inherit (state) muted totalKills totalSecrets;
        campaignTime = state.campaignTime - state.elapsed;
      };
      dt = clamp 0.0 0.1 delta;
      count = max 1 (builtins.ceil (dt * 60));
      input = { inherit forward strafe turn run fire; look = look / count; use = false; };
      interacted = if use then interact state else state;
      advanced = builtins.foldl' (s: _: builtins.deepSeq s
        (if s.phase != "playing" then s else advance s input (dt / count))) interacted (m.range count);
    in if restart then reset
      else if state.phase == "title" then (if start then state // { phase = "playing"; } else state)
      else if state.phase == "intermission" then (if start then nextLevel state else state)
      else if state.phase == "victory" then (if start then
        (initial { inherit (state) difficulty; }) // { phase = "playing"; inherit (state) muted; } else state)
      else if state.phase == "dead" then (if start then reset else state)
      else if state.phase == "paused" then (if pause || start then state // { phase = "playing"; } else state)
      else if pause then state // { phase = "paused"; }
      else advanced;
in {
  inherit initial step levels levelFor weapons enemyRules damagePlayer;
  use = interact;
}
