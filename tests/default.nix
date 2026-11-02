let
  m = import ../math.nix;
  world = import ../world.nix;
  game = import ../game.nix;
  art = import ../art.nix;
  initial = game.initial {};
  playing = game.step initial { start = true; };
  empty = playing // { enemies = []; items = []; };
  level = game.levelFor playing;
  near = a: b: m.abs (a - b) < 0.0001;
  at = state: x: y: angle: state // { player = state.player // { inherit x y angle; }; };
  tick = state: game.step state { delta = 1.0 / 60; };
  fire = state: game.step state { fire = true; delta = 0.01; };
  monster = kind: id: x: y: { inherit kind id x y; hp = game.enemyRules.${kind}.hp;
    cooldown = 10.0; hurt = 0.0; alert = false; };
  target = monster "guard" 0 5.5 4.5;
  arena = empty // { enemies = [ target ]; };
  shot = fire arena;
  killed = fire (shot // { cooldown = 0.0; });
  closedShot = fire (empty // { enemies = [ (monster "guard" 0 11.5 4.5) ]; });
  door = game.step (at empty 7.1 4.5 0.0) { use = true; };
  opened = m.repeat 40 tick door;
  locked = game.step (at empty 15.1 12.5 0.0) { use = true; };
  redOpened = game.step ((at empty 15.1 12.5 0.0) // {
    player = (at empty 15.1 12.5 0.0).player // { keys = [ "red" ]; };
  }) { use = true; };
  secret = game.step (at empty 7.1 14.5 0.0) { use = true; };
  health = { id = 0; kind = "health"; x = 3.5; y = 4.5; };
  pick = kind: state: tick (state // { items = [ (health // { inherit kind; }) ]; });
  shotgun = pick "shotgun" arena;
  shotgunShot = fire shotgun;
  paused = game.step playing { pause = true; };
  exit = game.step (at empty 22.5 3.5 0.0) { use = true; };
  next = game.step (exit // { kills = 3; secrets = 1; }) { start = true; };
  last = (game.initial { level = 2; }) // { phase = "playing"; };
  lastBlocked = game.step (at last 26.5 11.5 0.0) { use = true; };
  lastCleared = game.step (at (last // { enemies = []; }) 26.5 11.5 0.0) { use = true; };
  victory = game.step lastCleared { start = true; };
  ai = empty // { enemies = [ ((monster "imp" 0 6.5 4.5) // { cooldown = 0.0; }) ]; };
  bolt = { x = 3.6; y = 4.5; vx = -1.0; vy = 0.0; damage = 12; life = 1.0; kind = "fireball"; };
  simulation = m.repeat 600 (state: game.step state { delta = 1.0 / 60; forward = 1; run = true; }) empty;
  # Reachability models use-to-open doors, with and without the required key.
  reachable = map: allowRed:
    let
      start = { x = builtins.floor map.spawn.x; y = builtins.floor map.spawn.y; };
      visit = acc: cell:
        let id = world.key cell.x cell.y; t = world.tile map cell.x cell.y;
            blocked = builtins.elem t [ "#" "M" "B" ] || (t == "R" && !allowRed);
        in if acc.seen ? ${id} || blocked then acc else {
          seen = acc.seen // { ${id} = true; }; frontier = acc.frontier ++ [ cell ];
        };
      flood = seen: frontier:
        if frontier == [] then seen else
        let result = builtins.foldl' (acc: cell: builtins.foldl' visit acc [
          { x = cell.x - 1; y = cell.y; } { x = cell.x + 1; y = cell.y; }
          { x = cell.x; y = cell.y - 1; } { x = cell.x; y = cell.y + 1; }
        ]) { inherit seen; frontier = []; } frontier;
        in flood result.seen result.frontier;
    in flood { ${world.key start.x start.y} = true; } [ start ];
  levelValid = map:
    let
      all = reachable map true; beforeKey = reachable map false;
      key = builtins.head (builtins.filter (i: i.kind == "redkey") map.items);
      exits = m.concatMap (y: m.concatMap (x: if world.tile map x y == "X" then
        [ { inherit x y; } ] else []) (m.range map.width)) (m.range map.height);
      exitCell = builtins.head exits;
    in builtins.length exits == 1
      && beforeKey ? ${world.key (builtins.floor key.x) (builtins.floor key.y)}
      && !(beforeKey ? ${world.key exitCell.x exitCell.y})
      && all ? ${world.key exitCell.x exitCell.y}
      && builtins.all (e: all ? ${world.key (builtins.floor e.x) (builtins.floor e.y)}) (map.items ++ map.enemies)
      && world.fits map {} 0.2 map.spawn.x map.spawn.y;
  input = import ../input.nix;
  snapshot = { delta = 0.02; keysDown = []; keysPressed = []; mouseDown = []; mouseX = 100; };
  controls = input (snapshot // { keysDown = [ 87 68 340 32 ]; keysPressed = [ 69 51 258 ]; }) null playing;
  app = import ../app.nix { ray = {}; audio = false; };
  captureFrame = app.frame (snapshot // {
    state = { game = playing; mouseX = 100; }; keysPressed = [ 67 ];
  });
  checks = {
    startsOnTitle = initial.phase == "title";
    enterStarts = playing.phase == "playing";
    titleDoesNotAdvance = (game.step initial { delta = 1; }).elapsed == 0;
    hasThreeLevels = builtins.length game.levels == 3;
    everyMapIsSolvableAndKeyGated = builtins.all levelValid game.levels;
    mapsHaveClosedBorders = builtins.all (map:
      builtins.all (x: world.solid map {} x 0 && world.solid map {} x (map.height - 1)) (m.range map.width)
      && builtins.all (y: world.solid map {} 0 y && world.solid map {} (map.width - 1) y) (m.range map.height)
    ) game.levels;
    enemiesAndItemsHaveUniqueIds = builtins.all (map:
      builtins.length (builtins.attrNames (builtins.listToAttrs (builtins.map (e: { name = toString e.id; value = true; }) map.enemies)))
        == builtins.length map.enemies
    ) game.levels;
    sinZero = near (m.sin 0) 0;
    sinHalfPi = near (m.sin (m.pi / 2)) 1;
    cosPi = near (m.cos m.pi) (-1);
    sinWrap = near (m.sin (100 * m.tau + 0.25)) (m.sin 0.25);
    squareRoot = near (m.sqrt 144) 12;
    squareRootFraction = near (m.sqrt 0.01) 0.1;
    negativeModWraps = near (m.mod (-0.5) 1) 0.5;
    ddaHitsDoor = (world.cast level {} playing.player { x = 1; y = 0; }).tile == "D";
    ddaDistance = near (world.cast level {} playing.player { x = 1; y = 0; }).distance 4.5;
    ddaAxisAligned = (world.cast level {} playing.player { x = 0; y = -1; }).tile == "#";
    ddaNegativeAxis = near (world.cast level {} playing.player { x = -1; y = 0; }).distance 2.5;
    ddaOpenDoor = (world.cast level { "8,4" = 1.0; } playing.player { x = 1; y = 0; }).x == 16;
    lineOfSightBlocked = !world.visible level {} playing.player { x = 11.5; y = 4.5; };
    lineOfSightOpen = world.visible level { "8,4" = 1.0; } playing.player { x = 11.5; y = 4.5; };
    outOfBoundsIsSolid = world.solid level {} (-1) 4;
    cornerCollision = !world.fits level {} 0.2 8.05 3.95;
    movementUsesSeconds = near (game.step empty { forward = 1; delta = 0.1; }).player.x 3.8;
    runningIsFaster = (game.step empty { forward = 1; run = true; delta = 0.1; }).player.x > 3.8;
    strafingMovesSideways = (game.step empty { strafe = 1; delta = 0.1; }).player.y > 4.5;
    diagonalSpeedNormalized = near (m.distance empty.player
      (game.step empty { forward = 1; strafe = 1; delta = 0.1; }).player) 0.3;
    frameTimeCapped = game.step empty { forward = 1; delta = 99; } == game.step empty { forward = 1; delta = 0.1; };
    negativeDeltaClamped = game.step empty { delta = -1; } == game.step empty {};
    movementCannotTunnel = simulation.player.x < 7.81 && simulation.player.x > 7.7;
    wallSliding = (game.step (at empty 7.79 5.5 0.0) { forward = 1; strafe = 1; delta = 0.1; }).player.y > 5.5;
    turnUpdatesHeading = (game.step empty { turn = 1; delta = 0.1; }).player.angle > 0;
    mouseLookNotMultipliedBySubsteps = near (game.step empty { look = 0.2; delta = 0.1; }).player.angle 0.2;
    weaponConsumesAmmo = shot.player.bullets == 59;
    pistolHits = (builtins.head shot.enemies).hp == 18;
    deathCountsOnce = killed.kills == 1 && (builtins.head killed.enemies).hp == 0;
    deathDropsAmmo = builtins.any (i: i.kind == "bullets") killed.items;
    corpseCannotBeKilledAgain = (fire (killed // { cooldown = 0.0; })).kills == 1;
    wallsBlockBullets = (builtins.head closedShot.enemies).hp == 36;
    nearestEnemyBlocksBullets = let s = fire (arena // { enemies = [ target (monster "guard" 1 6.5 4.5) ]; });
      in (builtins.elemAt s.enemies 0).hp == 18 && (builtins.elemAt s.enemies 1).hp == 36;
    firingHasCooldown = (fire shot).player.bullets == 59;
    shotEmitsSound = builtins.elem "pistol" shot.events;
    eventsAreOneFrame = !(builtins.elem "pistol" (tick shot).events);
    emptyGunDoesNotFire = (fire (arena // { player = arena.player // { bullets = 0; }; })).shots == 0;
    fistNeedsNoAmmo = (fire (empty // { player = empty.player // { weapon = "fist"; bullets = 0; }; })).shots == 1;
    fistHasLimitedRange = (builtins.head (fire (arena // { player = arena.player // { weapon = "fist"; }; })).enemies).hp == 36;
    canSelectOwnedWeapon = (game.step playing { selectWeapon = "fist"; }).player.weapon == "fist";
    cannotSelectUnownedWeapon = (game.step playing { selectWeapon = "chaingun"; }).player.weapon == "pistol";
    shotgunPickupUnlocksWeapon = shotgun.player.weapon == "shotgun" && builtins.elem "shotgun" shotgun.player.weapons;
    shotgunHasSevenPellets = (builtins.head shotgunShot.enemies).hp == 0 && shotgunShot.player.shells == 11;
    duplicateWeaponInventoryUnique = builtins.length (pick "shotgun" shotgun).player.weapons == 3;
    chaingunUnlocks = builtins.elem "chaingun" (pick "chaingun" empty).player.weapons;
    healthDoesNotConsumeAtFull = (pick "health" empty).items != [];
    healthHeals = (pick "health" (empty // { player = empty.player // { hp = 50; }; })).player.hp == 80;
    healthIsCapped = (pick "health" (empty // { player = empty.player // { hp = 90; }; })).player.hp == 100;
    armorPickup = (pick "armor" empty).player.armor == 60;
    ammoIsCapped = (pick "bullets" (empty // { player = empty.player // { bullets = 295; }; })).player.bullets == 300;
    shellsPickup = (pick "shells" empty).player.shells == 8;
    keyPickup = (pick "redkey" empty).player.keys == [ "red" ];
    usedDoorBeginsOpening = door.doors."8,4" > 0;
    doorsFinishOpening = opened.doors."8,4" == 1.0;
    lockedDoorNeedsKey = locked.doors == {} && locked.message == "YOU NEED THE RED KEYCARD";
    keyUnlocksRedDoor = redOpened.doors ? "16,12";
    secretCounts = secret.secrets == 1;
    secretCountsOnlyOnce = (game.step secret { use = true; }).secrets == 1;
    useHasLimitedReach = (game.step empty { use = true; }).doors == {};
    damageLowersHealth = (game.damagePlayer empty 20).player.hp == 80;
    armorAbsorbsHalf = let s = game.damagePlayer (empty // { player = empty.player // { armor = 40; }; }) 20;
      in s.player.hp == 90 && s.player.armor == 30;
    armorCannotBecomeNegative = (game.damagePlayer (empty // { player = empty.player // { armor = 3; }; }) 20).player.armor == 0;
    difficultyScalesDamage = (game.damagePlayer (empty // { difficulty = 0; }) 20).player.hp > 80;
    lethalDamageEndsGame = (game.damagePlayer empty 999).phase == "dead";
    damageGracePeriod = (game.damagePlayer (game.damagePlayer empty 20) 20).player.hp == 80;
    enemiesWakeOnSight = (builtins.head (tick ai).enemies).alert;
    impsThrowFireballs = (tick ai).projectiles != [];
    projectilesHurt = (tick (empty // { projectiles = [ bolt ]; })).player.hp < 100;
    projectilesConsumedOnImpact = (tick (empty // { projectiles = [ bolt ]; })).projectiles == [];
    projectilesExpire = (tick (empty // { projectiles = [ (bolt // { x = 5.0; life = 0.001; }) ]; })).projectiles == [];
    projectilesHitWalls = (tick (empty // { projectiles = [ (bolt // { x = 7.99; vx = 3.0; }) ]; })).projectiles == [];
    slimeDamagesOverTime = (m.repeat 50 tick (at empty 10.5 10.5 0.0)).player.hp < 100;
    pauseDoesNotAdvance = paused.elapsed == playing.elapsed && paused.phase == "paused";
    pauseFreezesGame = (game.step paused { delta = 10; fire = true; forward = 1; }) == paused;
    pauseResumes = (game.step paused { pause = true; }).phase == "playing";
    restartResetsSector = (game.step shot { restart = true; }).player.bullets == 60;
    restartPreservesDifficulty = (game.step (shot // { difficulty = 2; }) { restart = true; }).difficulty == 2;
    exitOpensIntermission = exit.phase == "intermission";
    intermissionFreezesGame = (game.step exit { delta = 1; }).elapsed == exit.elapsed;
    entersNextLevel = next.level == 1 && next.phase == "playing";
    preservesCampaignTotals = next.totalKills == 3 && next.totalSecrets == 1;
    nextLevelResetsKey = (game.step (exit // { player = exit.player // { keys = [ "red" ]; }; }) { start = true; }).player.keys == [];
    finalExitRequiresBossKills = lastBlocked.phase == "playing";
    finalExitWorks = lastCleared.phase == "intermission";
    campaignCanBeWon = victory.phase == "victory";
    canReplayCampaign = (game.step victory { start = true; }).level == 0;
    mapToggles = (game.step playing { toggleMap = true; }).showMap;
    muteToggles = (game.step playing { toggleMute = true; }).muted;
    captureToggles = (game.step playing { capture = true; }).mouseCaptured;
    difficultySelectionOnlyOnTitle = (game.step initial { difficulty = 2; }).difficulty == 2
      && (game.step playing { difficulty = 2; }).difficulty == 1;
    keyboardControls = controls.forward == 1 && controls.strafe == 1 && controls.run && controls.fire && controls.use;
    weaponAndMapControls = controls.selectWeapon == "shotgun" && controls.toggleMap;
    mouseDisabledByDefault = (input snapshot 10 playing).look == 0;
    mouseHasDeltaWhenCaptured = near (input snapshot 90 (playing // { mouseCaptured = true; })).look 0.03;
    captureResetsMouseDelta = captureFrame.state.mouseX == null;
    allArtworkHasValidPixels = builtins.all (definition:
      builtins.all (y: builtins.all (x:
        let pixel = definition.pixel x y;
        in builtins.length pixel == 4 && builtins.all (n: builtins.isInt n && n >= 0 && n <= 255) pixel
      ) (m.range definition.width)) (m.range definition.height)
    ) (builtins.attrValues art.textures);
  };
  failed = builtins.filter (name: !checks.${name}) (builtins.attrNames checks);
in if failed != [] then throw "DOOM / NIX tests failed: ${builtins.concatStringsSep ", " failed}"
else { passed = builtins.length (builtins.attrNames checks); tests = builtins.attrNames checks; }
