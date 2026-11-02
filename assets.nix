{ ray }:
let
  m = import ./math.nix;
  art = import ./art.nix;
  make = definition:
    let
      pixels = builtins.filter (p: builtins.elemAt p.color 3 != 0)
        (m.concatMap (y: map (x: { op = "drawPixel"; inherit x y; color = definition.pixel x y; })
          (m.range definition.width)) (m.range definition.height));
      count = builtins.length pixels;
      chunks = builtins.genList (i: builtins.genList (j: builtins.elemAt pixels (i * 128 + j))
        (m.min 128 (count - i * 128))) (builtins.ceil (count / 128.0));
    in {
      image = builtins.foldl' ray.imageTransform (ray.genImage {
        inherit (definition) width height; color = [ 0 0 0 0 ];
      }) chunks;
      filter = "point";
    };
in builtins.mapAttrs (_: make) art.textures
