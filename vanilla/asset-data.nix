{ iwad }:
let
  m = import ../math.nix;
  wad = import ./wad.nix (builtins.readFile "${iwad}/doom1.hex");
  geometry = import ./geometry.nix { inherit wad; };
  concat = builtins.concatStringsSep "";
  mod = a: b: a - builtins.div a b * b;
  octal = "01234567";
  byte = n: "\\${builtins.substring (builtins.div n 64) 1 octal}${builtins.substring (mod (builtins.div n 8) 8) 1 octal}${builtins.substring (mod n 8) 1 octal}";
  le = count: n: if count == 0 then "" else byte (mod n 256) + le (count - 1) (builtins.div n 256);
  palette = concat (builtins.genList (i:
    let c = builtins.elemAt wad.palette i;
    in concat (builtins.map byte [ (builtins.elemAt c 2) (builtins.elemAt c 1) (builtins.elemAt c 0) 255 ])
  ) 256) + "\\000\\000\\000\\000";
  tga = image:
    # Indexed TGA with a 257th, transparent palette entry. Pixel decoding,
    # patch compositing, texture definitions, and palette application are Nix.
    "\\000\\001\\001" + le 2 0 + le 2 257 + byte 32 + le 2 0 + le 2 0
      + le 2 image.width + le 2 image.height + byte 16 + byte 32 + palette
      + concat (m.concatMap (y: builtins.map (x:
        let index = image.pixel x y; in le 2 (if index == null then 256 else index)
      ) (m.range image.width)) (m.range image.height));
  spriteStart = (wad.lump "S_START").id; spriteEnd = (wad.lump "S_END").id;
  patchNames = builtins.map (l: l.name) (builtins.filter (l: l.size > 8 && builtins.match "STEP.*" l.name == null &&
    ((l.id > spriteStart && l.id < spriteEnd) ||
      builtins.match "(ST.*|M_.*|WI.*|TITLEPIC|CREDIT|HELP[0-9]*|INTERPIC)" l.name != null)
  ) wad.directory);
  wallNames = builtins.attrNames wad.textures;
  flatNames = builtins.attrNames (builtins.listToAttrs (m.concatMap (map:
    m.concatMap (s: builtins.map (name: { inherit name; value = true; })
      ([ s.floorTexture ] ++ (if s.ceilingTexture == "F_SKY1" then [] else [ s.ceilingTexture ]))) map.sectors
  ) wad.maps));
  images = builtins.map (name: { name = "patch-${name}"; image = wad.patch name; }) patchNames
    ++ builtins.map (name: { name = "wall-${name}"; image = wad.texture name; }) wallNames
    ++ builtins.map (name: { name = "flat-${name}"; image = wad.flat name; }) flatNames;
  sounds = builtins.filter (l: builtins.substring 0 2 l.name == "DS" && l.size > 8) wad.directory;
  wav = lump:
    let p = lump.offset; rate = wad.b.u16 (p + 2); count = wad.b.u32 (p + 4);
    in assert wad.b.u16 p == 3 && count + 8 <= lump.size;
      "RIFF" + le 4 (36 + count) + "WAVEfmt " + le 4 16 + le 2 1 + le 2 1
        + le 4 rate + le 4 rate + le 2 1 + le 2 8 + "data" + le 4 count
        + concat (builtins.genList (i: byte (wad.b.u8 (p + 8 + i))) count);
  files = builtins.map (entry: { name = "${entry.name}.tga";
      bytes = tga entry.image; }) images
    ++ builtins.map (l: { name = "${l.name}.wav"; bytes = wav l; }) sounds
    ++ m.concatMap (map: m.concatMap (model: [
      { name = "${model.name}.obj"; text = model.content; }
      { name = "${model.name}.mtl"; text = model.mtl; }
    ]) map.models) maps;
  maps = builtins.map (map:
    let geo = geometry.makeMap map;
    in { inherit (map) name; inherit geo;
      models = builtins.map (group: { name = "${map.name}-${group}";
        mtl = geo.mtl group;
        content = geo.obj group; }) geo.groups; }
  ) wad.maps;
in {
  inherit wad patchNames wallNames flatNames maps files;
}
