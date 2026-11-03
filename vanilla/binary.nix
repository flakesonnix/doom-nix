hex:
let
  digits = "0123456789abcdef";
  table = builtins.listToAttrs (builtins.genList (n: {
    name = builtins.substring (builtins.div n 16) 1 digits + builtins.substring (n - builtins.div n 16 * 16) 1 digits;
    value = n;
  }) 256);
  ascii = " !\"#$%&'()*+,-./0123456789:;<=>?@ABCDEFGHIJKLMNOPQRSTUVWXYZ[\\]^_`abcdefghijklmnopqrstuvwxyz{|}~";
in rec {
  size = builtins.div (builtins.stringLength hex) 2;
  u8 = offset:
    if offset < 0 || offset >= size then throw "WAD: byte offset ${toString offset} outside ${toString size} bytes"
    else table.${builtins.substring (offset * 2) 2 hex} or (throw "WAD: invalid hexadecimal input");
  u16 = offset: u8 offset + 256 * u8 (offset + 1);
  i16 = offset: let n = u16 offset; in if n >= 32768 then n - 65536 else n;
  u32 = offset: u16 offset + 65536 * u16 (offset + 2);
  i32 = offset: let n = u32 offset; in if n >= 2147483648 then n - 4294967296 else n;
  string = offset: length: builtins.concatStringsSep "" (builtins.genList (i:
    let n = u8 (offset + i);
    in if n == 0 then "" else if n >= 32 && n <= 126 then builtins.substring (n - 32) 1 ascii
      else throw "WAD: non-ASCII identifier"
  ) length);
  records = offset: bytes: stride: decode:
    if bytes < 0 || bytes - builtins.div bytes stride * stride != 0 then throw "WAD: truncated record table"
    else builtins.genList (i: decode i (offset + i * stride)) (builtins.div bytes stride);
}
