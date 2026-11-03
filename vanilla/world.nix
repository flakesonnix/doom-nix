let m = import ../math.nix;
in rec {
  cross = ax: ay: bx: by: ax * by - ay * bx;
  side = line: point: cross line.dx line.dy (point.x - line.a.x) (point.y - line.a.y);
  sectorAt = map: point:
    let walk = index:
      if index >= 32768 then (builtins.elemAt map.subsectors (index - 32768)).sector
      else let node = builtins.elemAt map.nodes index;
        in walk (if cross node.dx node.dy (point.x - node.x) (point.y - node.y) <= 0 then node.right else node.left);
    in walk (builtins.length map.nodes - 1);
  sector = map: state: id:
    (builtins.elemAt map.sectors id) // (state.sectors.${toString id} or {});
  adjacent = map: id: builtins.filter (x: x != null && x != id)
    (mapLines (l: if l.front == id then l.back else if l.back == id then l.front else null) map);
  mapLines = f: map: builtins.map f map.lines;
  neighbors = map: id: builtins.listToAttrs (builtins.map (s: { name = toString s; value = s; }) (adjacent map id));
  blockLines = map: point: radius:
    let
      bm = map.blockmap;
      left = m.max 0 (builtins.floor ((point.x - radius - bm.x) / 128.0));
      right = m.min (bm.width - 1) (builtins.floor ((point.x + radius - bm.x) / 128.0));
      bottom = m.max 0 (builtins.floor ((point.y - radius - bm.y) / 128.0));
      top = m.min (bm.height - 1) (builtins.floor ((point.y + radius - bm.y) / 128.0));
      ids = m.concatMap (y: m.concatMap (x: builtins.elemAt bm.cells (y * bm.width + x))
        (builtins.genList (i: left + i) (m.max 0 (right - left + 1))))
        (builtins.genList (i: bottom + i) (m.max 0 (top - bottom + 1)));
      unique = builtins.listToAttrs (builtins.map (id: { name = toString id; value = builtins.elemAt map.lines id; }) ids);
    in builtins.attrValues unique;
  distanceToLine = line: point:
    let length2 = line.dx * line.dx + line.dy * line.dy;
        t = if length2 == 0 then 0 else m.clamp 0.0 1.0
          (((point.x - line.a.x) * line.dx + (point.y - line.a.y) * line.dy) / (length2 * 1.0));
    in m.length (point.x - line.a.x - t * line.dx) (point.y - line.a.y - t * line.dy);
  opening = map: state: line:
    let a = sector map state line.front; b = if line.back == null then a else sector map state line.back;
    in { floor = m.max a.floor b.floor; ceiling = m.min a.ceiling b.ceiling; };
  fits = map: state: actor: point:
    let target = sector map state (sectorAt map point);
    in target.ceiling - target.floor >= actor.height && target.floor - actor.z <= 24
      && builtins.all (line:
        let gap = opening map state line;
        in distanceToLine line point >= actor.radius ||
          (line.back != null && builtins.bitAnd line.flags 1 == 0 && gap.ceiling - gap.floor >= actor.height
            && gap.floor - actor.z <= 24 && gap.ceiling - actor.z >= actor.height)
      ) (blockLines map point actor.radius);
  move = map: state: actor: dx: dy:
    let
      proposed = actor // { x = actor.x + dx; y = actor.y + dy; };
      blocking = builtins.filter (line:
        let gap = opening map state line;
        in distanceToLine line proposed < actor.radius && (line.back == null || builtins.bitAnd line.flags 1 != 0
          || gap.ceiling - gap.floor < actor.height || gap.floor - actor.z > 24)
      ) (blockLines map proposed actor.radius);
      line = if blocking == [] then null else builtins.head blocking;
      dot = if line == null then 0 else (dx * line.dx + dy * line.dy) / (1.0 * (line.dx * line.dx + line.dy * line.dy));
      slid = actor // { x = actor.x + (if line == null then 0 else line.dx * dot);
        y = actor.y + (if line == null then 0 else line.dy * dot); };
      result = if fits map state actor proposed then proposed
        else if fits map state actor slid then slid else actor;
      floor = (sector map state (sectorAt map result)).floor;
    in result // { z = m.max result.z floor; };
  intersections = map: origin: direction: range:
    let
      endpoint = { x = origin.x + direction.x * range; y = origin.y + direction.y * range; };
      midpoint = { x = (origin.x + endpoint.x) / 2; y = (origin.y + endpoint.y) / 2; };
      candidates = blockLines map midpoint (range / 2 + 1);
      intersect = line:
        let denominator = cross direction.x direction.y line.dx line.dy;
            ax = line.a.x - origin.x; ay = line.a.y - origin.y;
            distance = if m.abs denominator < 0.000001 then -1 else cross ax ay line.dx line.dy / denominator;
            fraction = if m.abs denominator < 0.000001 then -1 else cross ax ay direction.x direction.y / denominator;
        in { inherit line distance fraction; };
    in builtins.sort (a: b: a.distance < b.distance) (builtins.filter
      (h: h.distance > 0.001 && h.distance <= range && h.fraction >= 0 && h.fraction <= 1)
      (builtins.map intersect candidates));
  visible = map: state: a: b:
    let distance = m.distance a b;
        hits = intersections map a { x = (b.x - a.x) / m.max 0.001 distance;
          y = (b.y - a.y) / m.max 0.001 distance; } distance;
        eye = a.z + a.height / 2;
    in builtins.all (hit: let gap = opening map state hit.line;
      in hit.line.back != null && gap.ceiling > eye && gap.floor < eye) hits;
  # Each BSP leaf is convex. Clip the map bounds down the original partition
  # tree; the resulting polygons also include implicit subsector edges.
  polygons = map:
    let
      clip = polygon: node: positive:
        let signed = v: cross node.dx node.dy (v.x - node.x) (v.y - node.y) * (if positive then 1 else -1);
        in if polygon == [] then [] else (builtins.foldl' (acc: b:
          let a = acc.previous; da = signed a; db = signed b;
              t = da / (da - db);
              hit = { x = a.x + t * (b.x - a.x); y = a.y + t * (b.y - a.y); };
          in { previous = b; points = acc.points ++
            (if da >= 0 && db >= 0 then [ b ] else if da >= 0 then [ hit ]
              else if db >= 0 then [ hit b ] else []); }
        ) { previous = builtins.elemAt polygon (builtins.length polygon - 1); points = []; } polygon).points;
      walk = index: polygon:
        if builtins.length polygon < 3 then [] else if index >= 32768 then [ {
          sector = (builtins.elemAt map.subsectors (index - 32768)).sector; points = polygon;
        } ] else let node = builtins.elemAt map.nodes index;
          in walk node.right (clip polygon node false) ++ walk node.left (clip polygon node true);
      b = map.bounds;
    in walk (builtins.length map.nodes - 1) [
      { x = b.left - 16.0; y = b.bottom - 16.0; } { x = b.right + 16.0; y = b.bottom - 16.0; }
      { x = b.right + 16.0; y = b.top + 16.0; } { x = b.left - 16.0; y = b.top + 16.0; }
    ];
}
