{ wad }:
let
  m = import ../math.nix;
  world = import ./world.nix;
  f = n: if builtins.isInt n then toString n else builtins.toJSON n;
  point = x: z: y: "${f (x / 64.0)} ${f (z / 64.0)} ${f (-y / 64.0)}";
  textureName = kind: name: "${kind}-${name}";
  doorSpecials = [ 1 26 27 28 31 32 33 34 117 118 ];
  taggedDoors = [ 2 3 4 16 29 42 46 50 61 63 75 76 86 90 99 103 105 106 107 108 109 110 111 112 113 114 115 116 ];
  doorIds = map: builtins.attrValues (builtins.listToAttrs
    (m.concatMap (line:
      let direct = builtins.elem line.special doorSpecials;
          tagged = builtins.elem line.special taggedDoors;
          sectors = if direct && line.back != null then [ line.back ] else
            if tagged && line.tag != 0 then builtins.map (s: s.id) (builtins.filter (s: s.tag == line.tag) map.sectors) else [];
      in builtins.map (id: { name = toString id; value = id; }) sectors
    ) map.lines));
  floorIds = map: builtins.map (s: s.id) map.sectors;
  makeMap = map:
    let
      doors = doorIds map; floors = floorIds map;
      polygons = world.polygons map;
      flatSurfaces = m.concatMap (polygon:
        let sector = builtins.elemAt map.sectors polygon.sector;
            make = ceiling: {
              texture = textureName "flat" (if ceiling then sector.ceilingTexture else sector.floorTexture);
              light = sector.light;
              group = if ceiling && builtins.elem sector.id doors then "door-${toString sector.id}"
                else if !ceiling && builtins.elem sector.id floors then "floor-${toString sector.id}" else "base";
              points = builtins.map (v: { position = point v.x (if ceiling then sector.ceiling else sector.floor) v.y;
                u = v.x / 64.0; v = -v.y / 64.0; })
                (if ceiling then builtins.genList (i: builtins.elemAt polygon.points (builtins.length polygon.points - i - 1))
                  (builtins.length polygon.points) else polygon.points);
            };
        in [ (make false) ] ++ (if sector.ceilingTexture == "F_SKY1" then [] else [ (make true) ])
      ) polygons;
      wallSurfaces = m.concatMap (line:
        let
          makeSide = reverse:
            let
              side = builtins.elemAt map.sides (if reverse then line.left else line.right);
              frontId = if reverse then line.back else line.front;
              backId = if reverse then line.front else line.back;
              front = builtins.elemAt map.sectors frontId;
              back = if backId == null then null else builtins.elemAt map.sectors backId;
              a = if reverse then line.b else line.a; b = if reverse then line.a else line.b;
              length = m.distance a b;
              quad = name: bottom: top: anchor: group:
                let texture = wad.texture name;
                    vertex = p: z: u: { position = point p.x z p.y; u = u / (texture.width * 1.0);
                      v = (z - anchor - side.yOffset) / (texture.height * 1.0); };
                in if name == "-" || top <= bottom then [] else [ {
                  texture = textureName "wall" name; light = front.light; inherit group;
                  points = [ (vertex a bottom side.xOffset) (vertex b bottom (side.xOffset + length))
                    (vertex b top (side.xOffset + length)) (vertex a top side.xOffset) ];
                } ];
              unpegBottom = builtins.bitAnd line.flags 16 != 0;
              unpegTop = builtins.bitAnd line.flags 8 != 0;
              door = backId != null && builtins.elem backId doors && !builtins.elem frontId doors;
              doorHeight = if door then
                builtins.foldl' m.max front.ceiling (builtins.map (s: (builtins.elemAt map.sectors s).ceiling)
                  (world.adjacent map backId)) else 0;
              ownDoor = builtins.elem frontId doors;
              ownHeight = if ownDoor then builtins.foldl' m.max front.ceiling
                (builtins.map (s: (builtins.elemAt map.sectors s).ceiling) (world.adjacent map frontId)) else front.ceiling;
              middleAnchor = if unpegBottom && side.middle != "-" then front.floor + (wad.texture side.middle).height else ownHeight;
              upperAnchor = if unpegTop then front.ceiling else back.ceiling +
                (if side.upper == "-" then 0 else (wad.texture side.upper).height);
            in if back == null then quad side.middle front.floor ownHeight middleAnchor "base"
              else (if front.ceilingTexture == "F_SKY1" && back.ceilingTexture == "F_SKY1" then []
                else if door then quad side.upper back.ceiling doorHeight upperAnchor "door-${toString backId}"
                else quad side.upper back.ceiling front.ceiling upperAnchor "base")
                ++ quad side.lower front.floor back.floor (if unpegBottom then front.ceiling else back.floor) "base"
                ++ (if side.middle == "-" then [] else quad side.middle (m.max front.floor back.floor)
                  (m.min ownHeight back.ceiling) (if unpegBottom then m.max front.floor back.floor + (wad.texture side.middle).height
                    else m.min ownHeight back.ceiling) "base");
        in makeSide false ++ (if line.left == null then [] else makeSide true)
      ) map.lines;
      surfaces = flatSurfaces ++ wallSurfaces;
      material = surface: "${surface.texture}-${toString surface.light}";
      # raylib 5.5's tinyobj material hash can loop forever on a moderately
      # populated MTL table. One material per batch avoids that native bug and
      # also avoids repeatedly loading unrelated textures for moving sectors.
      batchName = surface: "${surface.group}--${material surface}";
      groups = builtins.attrNames (builtins.listToAttrs (builtins.map (surface: {
        name = batchName surface; value = true;
      }) surfaces));
      belongs = group: surface: batchName surface == group;
      batches = builtins.map (name:
        let mover = builtins.match "(door|floor)-([0-9]+)--.*" name;
        in { inherit name; type = if mover == null then "base" else builtins.elemAt mover 0;
          sector = if mover == null then null else builtins.fromJSON (builtins.elemAt mover 1); }
      ) groups;
      materials = builtins.listToAttrs (builtins.map (surface: { name = material surface; value = surface; }) surfaces);
      mtl = group: builtins.concatStringsSep "\n" (builtins.map (name:
        let surface = materials.${name}; light = f (m.max 0.15 (surface.light / 255.0));
        in "newmtl ${name}\nKd ${light} ${light} ${light}\nd 1\nmap_Kd ${surface.texture}.png\n"
      ) (builtins.attrNames (builtins.listToAttrs (builtins.map (surface: {
        name = material surface; value = true;
      }) (builtins.filter (belongs group) surfaces)))));
      obj = group:
        let selected = builtins.filter (belongs group) surfaces;
            result = builtins.foldl' (acc: surface:
              let n = builtins.length surface.points; base = acc.count + 1;
                  vertices = builtins.concatStringsSep "\n" (builtins.map (v: "v ${v.position}") surface.points);
                  uv = builtins.concatStringsSep "\n" (builtins.map (v: "vt ${f v.u} ${f v.v}") surface.points);
                  index = i: "${toString (base + i)}/${toString (base + i)}";
                  faces = builtins.concatStringsSep "\n" (builtins.genList (i:
                    "f ${index 0} ${index (i + 1)} ${index (i + 2)}") (n - 2));
              in { count = acc.count + n; chunks = acc.chunks ++ [ "usemtl ${material surface}\n${vertices}\n${uv}\n${faces}\n" ]; }
            ) { count = 0; chunks = []; } selected;
        in "mtllib ${map.name}-${group}.mtl\n" + builtins.concatStringsSep "\n" result.chunks;
    in { inherit doors floors groups batches mtl obj; };
in { inherit makeMap doorIds floorIds; }
