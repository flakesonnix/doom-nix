{ iwad }:
let
  m = import ../math.nix;
  wad = import ../vanilla/wad.nix (builtins.readFile "${iwad}/doom1.hex");
  game = import ../vanilla/game.nix { inherit wad; };
  world = game.world;
  initial = game.initial {};
  playing = initial // { phase = "playing"; };
  empty = playing // { actors = []; };
  map = game.currentMap playing;
  tick = s: game.step s { delta = 1.0 / 35; };
  at = s: x: y: angle: s // { player = s.player // { inherit x y angle; momx = 0.0; momy = 0.0;
    z = (world.sector map s (world.sectorAt map { inherit x y; })).floor; }; };
  doorLine = builtins.head (builtins.filter (l: l.special == 1) map.lines);
  door = game.activate empty doorLine "use";
  opened = m.repeat 64 tick door;
  lockedMap = builtins.elemAt wad.maps 1;
  lockedLine = builtins.head (builtins.filter (l: l.special == 28) lockedMap.lines);
  lockedState = (game.initial { level = 1; }) // { phase = "playing"; actors = []; };
  locked = game.activate lockedState lockedLine "use";
  unlocked = game.activate (lockedState // { player = lockedState.player // { keys = [ "red" ]; }; }) lockedLine "use";
  exitLine = builtins.head (builtins.filter (l: l.special == 11) map.lines);
  exited = game.activate empty exitLine "use";
  next = game.step exited { start = true; };
  shots = m.repeat 39 (s: game.step s { delta = 1.0 / 35; fire = true; }) empty;
  movement = m.repeat 35 (s: game.step s { delta = 1.0 / 35; forward = 1; }) empty;
  paused = game.step playing { pause = true; };
  malformed = import ../vanilla/binary.nix "0001ff7f0080ffff";
  near = a: b: m.abs (a - b) < 0.0001;
  uvMap = {
    name = "UV";
    bounds = { left = 0; right = 64; bottom = 0; top = 64; };
    nodes = [ { x = 0; y = 0; dx = 1; dy = 0; right = 32768; left = 32768; } ];
    subsectors = [ { sector = 0; } ];
    sectors = [ { id = 0; tag = 0; floor = 0; ceiling = 72; light = 160;
      floorTexture = "FLOOR0_1"; ceilingTexture = "CEIL3_5"; } ];
    sides = [ { xOffset = 1; yOffset = 1; middle = "STARTAN3"; upper = "-"; lower = "-"; } ];
    lines = [ { a = { x = 0; y = 0; }; b = { x = 64; y = 0; }; front = 0; back = null;
      left = null; right = 0; special = 0; tag = 0; flags = 0; } ];
  };
  wallUVs = builtins.map (line: builtins.map builtins.fromJSON line) (builtins.filter (line: line != null)
    (builtins.map (line: builtins.match "vt ([^ ]+) ([^ ]+)" line)
      (builtins.filter builtins.isString (builtins.split "\n" ((game.geometry.makeMap uvMap).obj "base--wall-STARTAN3-160")))));
  checkPatch = name:
    let p = wad.patch name;
    in builtins.all (x: builtins.all (post: post.y >= 0 && post.y + builtins.length post.pixels <= p.height
      && builtins.all (c: c >= 0 && c <= 255) post.pixels) (builtins.elemAt p.columns x)) (m.range p.width);
  checks = {
    originalIwadSize = wad.b.size == 4196020;
    originalDirectory = builtins.length wad.directory == 1264;
    originalAllNineMaps = builtins.map (x: x.name) wad.maps == [ "E1M1" "E1M2" "E1M3" "E1M4" "E1M5" "E1M6" "E1M7" "E1M8" "E1M9" ];
    originalSectorCounts = builtins.map (x: builtins.length x.sectors) wad.maps == [ 85 200 177 139 143 250 170 74 147 ];
    originalLineCounts = builtins.map (x: builtins.length x.lines) wad.maps == [ 475 1033 1026 830 825 1352 958 333 653 ];
    littleEndian16 = malformed.u16 0 == 256;
    signedPositive16 = malformed.i16 2 == 32767;
    signedNegative16 = malformed.i16 4 == -32768 && malformed.i16 6 == -1;
    binaryBoundsChecked = !(builtins.tryEval (malformed.u8 8)).success;
    truncatedRecordsRejected = !(builtins.tryEval (malformed.records 0 3 2 (_: _: 0))).success;
    namesAreCaseInsensitive = (wad.lump "playpal").offset == (wad.lump "PLAYPAL").offset;
    originalPalette = builtins.length wad.palette == 256 && builtins.head wad.palette == [ 0 0 0 255 ];
    originalTitle = (wad.patch "TITLEPIC").width == 320 && (wad.patch "TITLEPIC").height == 200;
    originalHud = (wad.patch "STBAR").width == 320 && (wad.patch "STBAR").height == 32;
    originalPistolOffsets = (wad.patch "PISGA0").left == -126 && (wad.patch "PISGA0").top == -106;
    patchesDecode = builtins.all checkPatch [ "TITLEPIC" "STBAR" "PISGA0" "PISGB0" "SHTGA0" "TROOA1" "POSSA1" ];
    textureComposition = (wad.texture "STARTAN3").width == 128 && (wad.texture "STARTAN3").pixel 0 0 != null;
    flatDecoding = (wad.flat "FLOOR0_1").pixel 10 10 >= 0;
    spawnMatchesOriginal = initial.player.x == 1056 && initial.player.y == -3616 && near initial.player.angle (m.pi / 2);
    originalInventory = initial.player.hp == 100 && initial.player.bullets == 50 && initial.player.shells == 0
      && initial.player.weapons == [ "fist" "pistol" ];
    originalPlayerDimensions = initial.player.radius == 16 && initial.player.height == 56;
    bspSpawnSector = world.sectorAt map initial.player == 38;
    everySpawnInsideSector = builtins.all (i:
      let s = game.initial { level = i; }; map = game.currentMap s;
      in world.fits map s s.player s.player && world.sectorAt map s.player < builtins.length map.sectors
    ) (m.range 9);
    bspPolygonsAreConvexLeaves = builtins.all (p: builtins.length p.points >= 3 && p.sector != null) (world.polygons map);
    singleMaterialBatchesAvoidNativeLoaderHang = let geo = game.geometry.makeMap map;
      in builtins.all (group: builtins.length (builtins.filter builtins.isList (builtins.split "newmtl " (geo.mtl group))) == 1) geo.groups;
    wallHorizontalOffsetKeepsFractionalTexel = builtins.head (builtins.head wallUVs) == 1 / 128.0;
    wallVerticalCoordinatesDoNotTruncate = builtins.elemAt (builtins.head wallUVs) 1 == -73 / 128.0;
    singlePlayerFlagFiltering = !builtins.any (a: builtins.bitAnd a.flags 16 != 0) initial.actors;
    skillChangesPopulation = builtins.length (game.initial { skill = 0; }).actors < builtins.length (game.initial { skill = 3; }).actors;
    allSharewareThingsCovered = builtins.all (map: builtins.all (t:
      builtins.elem t.type [ 1 2 3 4 11 14 ] || game.rules.types ? ${toString t.type}
    ) map.things) wad.maps;
    fixed35Hz = (game.step empty { delta = 1.0 / 35; }).tic == 1;
    accumulatesFractionalTics = (game.step (game.step empty { delta = 1.0 / 70; }) { delta = 1.0 / 70; }).tic == 1;
    negativeDeltaClamped = (game.step empty { delta = -1; }).tic == 0;
    longFramesBounded = (game.step empty { delta = 100; }).tic <= 8;
    oneSecondIs35Tics = movement.tic == 35;
    accelerationMovesForward = movement.player.y > initial.player.y + 200;
    momentumDecays = (tick (empty // { player = empty.player // { momx = 1.0; }; })).player.momx < 1;
    pausedDoesNotSimulate = (game.step paused { delta = 1; forward = 1; fire = true; }).tic == paused.tic;
    pauseCanResume = !(game.step paused { pause = true; }).paused;
    titleOpensOriginalMenu = (game.step initial { start = true; }).menu;
    menuStartsGame = (game.step (game.step initial { start = true; }) { start = true; }).phase == "playing";
    selectedSkillRespawnsPopulation = builtins.length (game.step ((game.initial {}) // { menu = true; skill = 3; }) { start = true; }).actors
      == builtins.length (game.initial { skill = 3; }).actors;
    originalRngSequence = (game.random initial).value == 8 && (game.random (game.random initial).state).value == 109;
    originalRngWraps = (m.repeat 256 (s: (game.random s).state) initial).rng == 0;
    pistolHasOriginalStateTiming = (builtins.elemAt game.rules.weapons.pistol.states 0).tics == 4
      && (builtins.elemAt game.rules.weapons.pistol.states 1).tics == 6;
    heldPistolConsumesAmmo = shots.player.bullets < 50 && shots.player.bullets >= 47;
    shotgunHasSevenPellets = game.rules.weapons.shotgun.pellets == 7;
    baronsHave1000Hp = game.rules.types."3003".hp == 1000;
    damageArmorUsesOriginalThird = let damaged = game.damagePlayer (empty // {
      player = empty.player // { armor = 100; armorType = 1; }; }) 30;
      in damaged.player.hp == 80 && damaged.player.armor == 90;
    blueArmorAbsorbsHalf = (game.damagePlayer (empty // { player = empty.player // { armor = 200; armorType = 2; }; }) 30).player.hp == 85;
    easiestSkillHalvesDamage = (game.damagePlayer (empty // { skill = 0; }) 20).player.hp == 90;
    invulnerabilityBlocksDamage = (game.damagePlayer (empty // { player = empty.player // { invulnerability = 35; }; }) 100).player.hp == 100;
    lethalDamageKills = (game.damagePlayer empty 101).phase == "dead";
    manualDoorActivates = door.movers ? ${toString doorLine.back};
    doorRaisesCeiling = (world.sector map opened doorLine.back).ceiling > (world.sector map empty doorLine.back).ceiling;
    doorDoesNotActivateOnWalk = (game.activate empty doorLine "walk").movers == {};
    lockedDoorRequiresKey = locked.movers == {};
    originalKeyUnlocks = unlocked.movers != {};
    exitUsesOriginalSwitch = exited.phase == "intermission";
    nextMapKeepsInventory = next.level == 1 && next.player.bullets == exited.player.bullets;
    nextMapLoadsCorrectModels = next.phase == "loading";
    secretsUseE1M9 = (game.nextLevel (exited // { level = 2; secretExit = true; })).level == 8;
    secretMapReturnsToE1M4 = (game.nextLevel (exited // { level = 8; })).level == 3;
    e1m8CompletesEpisode = (game.nextLevel (exited // { level = 7; })).phase == "victory";
    victoryRestartReloadsFirstMapAssets = let resumed = game.step (playing // { phase = "victory"; level = 7; }) { start = true; };
      in resumed.level == 0 && resumed.phase == "loading";
    stateIsJsonSerializable = builtins.stringLength (builtins.toJSON movement) > 0;
  };
  failed = builtins.filter (name: !checks.${name}) (builtins.attrNames checks);
in if failed != [] then throw "Doom shareware tests failed: ${builtins.concatStringsSep ", " failed}"
else { passed = builtins.length (builtins.attrNames checks); tests = builtins.attrNames checks; }
