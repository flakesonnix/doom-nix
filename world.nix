let m = import ./math.nix;
in rec {
  key = x: y: "${toString x},${toString y}";
  tile = level: x: y:
    if x < 0 || y < 0 || x >= level.width || y >= level.height then "#"
    else builtins.elemAt (builtins.elemAt level.grid y) x;
  isDoor = t: builtins.elem t [ "D" "R" "S" ];
  opening = doors: x: y: doors.${key x y} or 0.0;
  solid = level: doors: x: y:
    let t = tile level x y;
    in builtins.elem t [ "#" "M" "B" ] || (isDoor t && opening doors x y < 1.0);
  # Circle / tile collision, including corners; axis-separated movement slides.
  fits = level: doors: radius: x: y:
    builtins.all (cy: builtins.all (cx:
      let nx = m.clamp cx (cx + 1.0) x; ny = m.clamp cy (cy + 1.0) y;
      in !solid level doors cx cy || (x - nx) * (x - nx) + (y - ny) * (y - ny) >= radius * radius
    ) [ (builtins.floor (x - radius)) (builtins.floor (x + radius)) ])
      [ (builtins.floor (y - radius)) (builtins.floor (y + radius)) ];
  move = level: doors: radius: position: dx: dy:
    let x = if fits level doors radius (position.x + dx) position.y then position.x + dx else position.x;
        y = if fits level doors radius x (position.y + dy) then position.y + dy else position.y;
    in position // { inherit x y; };
  # Amanatides/Woo DDA. t is perpendicular camera depth for unnormalized rays.
  cast = level: doors: origin: direction:
    let
      dx = direction.x; dy = direction.y;
      deltaX = if m.abs dx < 0.00000001 then 1.0e20 else m.abs (1.0 / dx);
      deltaY = if m.abs dy < 0.00000001 then 1.0e20 else m.abs (1.0 / dy);
      stepX = if dx < 0 then -1 else 1; stepY = if dy < 0 then -1 else 1;
      cellX = builtins.floor origin.x; cellY = builtins.floor origin.y;
      walk = x: y: sideX: sideY: remaining:
        let
          side = if sideX < sideY then 0 else 1;
          nx = x + (if side == 0 then stepX else 0);
          ny = y + (if side == 1 then stepY else 0);
          distance = if side == 0 then sideX else sideY;
          coordinate = if side == 0 then origin.y + distance * dy else origin.x + distance * dx;
          u = m.mod coordinate 1.0;
        in if remaining == 0 || solid level doors nx ny then {
          inherit side distance u;
          x = nx; y = ny; tile = tile level nx ny;
        } else walk nx ny (sideX + (if side == 0 then deltaX else 0))
          (sideY + (if side == 1 then deltaY else 0)) (remaining - 1);
    in walk cellX cellY
      ((if dx < 0 then origin.x - cellX else cellX + 1 - origin.x) * deltaX)
      ((if dy < 0 then origin.y - cellY else cellY + 1 - origin.y) * deltaY) 128;
  visible = level: doors: a: b:
    let dx = b.x - a.x; dy = b.y - a.y;
    in m.abs dx + m.abs dy < 0.00001 || (cast level doors a { x = dx; y = dy; }).distance >= 1.0;
}
