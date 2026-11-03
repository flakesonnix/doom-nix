hex:
let
  b = import ./binary.nix hex;
  m = import ../math.nix;
  upper = builtins.replaceStrings (builtins.genList (i: builtins.substring i 1 "abcdefghijklmnopqrstuvwxyz") 26)
    (builtins.genList (i: builtins.substring i 1 "ABCDEFGHIJKLMNOPQRSTUVWXYZ") 26);
  count = b.u32 4;
  directoryOffset = b.u32 8;
  directory = builtins.genList (id:
    let p = directoryOffset + id * 16; offset = b.u32 p; size = b.u32 (p + 4);
    in if offset + size > b.size then throw "WAD: lump extends beyond file"
    else { inherit id offset size; name = upper (b.string (p + 8) 8); }
  ) count;
  named = builtins.listToAttrs (map (l: { inherit (l) name; value = l; }) directory);
  lump = name: named.${upper name} or (throw "WAD: missing lump ${name}");
  at = name: (lump name).offset;
  nameAt = p: upper (b.string p 8);
  palette = builtins.genList (i: builtins.genList (c: b.u8 (at "PLAYPAL" + i * 3 + c)) 3 ++ [ 255 ]) 256;
  patch = name:
    let
      l = lump name; p = l.offset;
      width = b.u16 p; height = b.u16 (p + 2);
      columns = builtins.genList (x:
        let
          posts = offset: remaining:
            if remaining == 0 then throw "WAD: unterminated patch column ${name}" else
            if offset < p || offset >= p + l.size then throw "WAD: invalid patch column ${name}" else
            let top = b.u8 offset; length = b.u8 (offset + 1);
            in if top == 255 then [] else
              [ { y = top; pixels = builtins.genList (i: b.u8 (offset + 3 + i)) length; } ]
              ++ posts (offset + length + 4) (remaining - 1);
        in posts (p + b.u32 (p + 8 + x * 4)) (height + 1)
      ) width;
      pixel = x: y:
        if x < 0 || y < 0 || x >= width || y >= height then null else
        let found = builtins.filter (post: y >= post.y && y < post.y + builtins.length post.pixels)
          (builtins.elemAt columns x);
        in if found == [] then null else
          let post = builtins.head found; in builtins.elemAt post.pixels (y - post.y);
    in if width > 4096 || height > 4096 || width == 0 || height == 0 then throw "WAD: invalid patch ${name}"
    else { inherit width height columns pixel; left = b.i16 (p + 4); top = b.i16 (p + 6); };
  patchNames = builtins.genList (i: nameAt (at "PNAMES" + 4 + i * 8)) (b.u32 (at "PNAMES"));
  textureTable = name:
    let base = at name;
    in builtins.genList (i:
      let p = base + b.u32 (base + 4 + i * 4);
      in {
        name = nameAt p; width = b.u16 (p + 12); height = b.u16 (p + 14);
        patches = builtins.genList (j:
          let q = p + 22 + j * 10;
          in { x = b.i16 q; y = b.i16 (q + 2); name = builtins.elemAt patchNames (b.u16 (q + 4)); }
        ) (b.u16 (p + 20));
      }
    ) (b.u32 base);
  textureDefinitions = textureTable "TEXTURE1" ++ (if named ? TEXTURE2 then textureTable "TEXTURE2" else []);
  texture = name:
    let
      def = textures.${name} or (throw "WAD: missing texture ${name}");
      patches = map (p: p // { image = patch p.name; }) def.patches;
      pixel = x: y: builtins.foldl' (color: p:
        let value = p.image.pixel (x - p.x) (y - p.y);
        in if value == null then color else value
      ) null patches;
    in { inherit (def) width height; inherit pixel; };
  textures = builtins.listToAttrs (map (t: { inherit (t) name; value = t; }) textureDefinitions);
  flat = name: { width = 64; height = 64; pixel = x: y: b.u8 (at name + y * 64 + x); };
  mapData = name:
    let
      marker = (lump name).id;
      table = index: stride: decode:
        let l = builtins.elemAt directory (marker + index);
        in b.records l.offset l.size stride decode;
      vertices = table 4 4 (id: p: { inherit id; x = b.i16 p; y = b.i16 (p + 2); });
      sides = table 3 30 (id: p: { inherit id; xOffset = b.i16 p; yOffset = b.i16 (p + 2);
        upper = nameAt (p + 4); lower = nameAt (p + 12); middle = nameAt (p + 20); sector = b.u16 (p + 28); });
      lines = table 2 14 (id: p:
        let a = builtins.elemAt vertices (b.u16 p); z = builtins.elemAt vertices (b.u16 (p + 2));
            front = b.u16 (p + 10); back = b.u16 (p + 12);
        in { inherit id a; b = z; flags = b.u16 (p + 4); special = b.u16 (p + 6); tag = b.u16 (p + 8);
          right = front; left = if back == 65535 then null else back;
          front = (builtins.elemAt sides front).sector;
          back = if back == 65535 then null else (builtins.elemAt sides back).sector;
          dx = z.x - a.x; dy = z.y - a.y;
        });
      sectors = table 8 26 (id: p: { inherit id; floor = b.i16 p; ceiling = b.i16 (p + 2);
        floorTexture = nameAt (p + 4); ceilingTexture = nameAt (p + 12);
        light = b.i16 (p + 20); special = b.u16 (p + 22); tag = b.u16 (p + 24);
      });
      segs = table 5 12 (id: p: { inherit id; a = b.u16 p; b = b.u16 (p + 2);
        angle = b.u16 (p + 4); line = b.u16 (p + 6); direction = b.u16 (p + 8); offset = b.u16 (p + 10); });
      subsectors = table 6 4 (id: p:
        let count = b.u16 p; first = b.u16 (p + 2); seg = builtins.elemAt segs first;
            line = builtins.elemAt lines seg.line;
        in { inherit id count first; sector = if seg.direction == 0 then line.front else line.back; });
      nodes = table 7 28 (id: p: { inherit id; x = b.i16 p; y = b.i16 (p + 2);
        dx = b.i16 (p + 4); dy = b.i16 (p + 6); right = b.u16 (p + 24); left = b.u16 (p + 26); });
      things = table 1 10 (id: p: { inherit id; x = b.i16 p; y = b.i16 (p + 2);
        angle = b.i16 (p + 4); type = b.u16 (p + 6); flags = b.u16 (p + 8); });
      blockLump = builtins.elemAt directory (marker + 10);
      blockBase = blockLump.offset;
      blockWidth = b.u16 (blockBase + 4); blockHeight = b.u16 (blockBase + 6);
      blockLists = builtins.genList (i:
        let offset = blockBase + b.u16 (blockBase + 8 + i * 2) * 2;
            read = p: n: if n == 0 then throw "WAD: unterminated blockmap" else
              let id = b.u16 p; in if id == 65535 then [] else [ id ] ++ read (p + 2) (n - 1);
        in read (offset + 2) (builtins.length lines + 1)
      ) (blockWidth * blockHeight);
    in { inherit name vertices sides lines sectors segs subsectors nodes things;
      blockmap = { width = blockWidth; height = blockHeight; x = b.i16 blockBase; y = b.i16 (blockBase + 2); cells = blockLists; };
      bounds = builtins.foldl' (acc: v: {
        left = m.min acc.left v.x; right = m.max acc.right v.x;
        bottom = m.min acc.bottom v.y; top = m.max acc.top v.y;
      }) { left = 32767; right = -32768; top = -32768; bottom = 32767; } vertices;
    };
in assert b.string 0 4 == "IWAD";
   assert count > 0 && count < 100000 && directoryOffset + count * 16 <= b.size;
   { inherit b directory named lump palette patch texture textures flat mapData;
     maps = builtins.genList (i: mapData "E1M${toString (i + 1)}") 9; }
