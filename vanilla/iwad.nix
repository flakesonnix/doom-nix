{ fetchurl, runCommand, unzip }:
let
  archive = fetchurl {
    url = "https://www.gamers.org/pub/idgames/idstuff/doom/doom19s.zip";
    hash = "sha256-ys8BQrMcoa8AeWtKAzngeZKsXyG8P4HnUy/hteG0huY=";
  };
in runCommand "doom-1.9-shareware-data" { nativeBuildInputs = [ unzip ]; } ''
  mkdir -p "$out"
  # Join the original DOS installer volumes; unzip reads its embedded ZIP.
  # No DOS executable is run. Preserve the original distribution unchanged.
  unzip -p ${archive} DOOMS_19.1 > installer.zip
  unzip -p ${archive} DOOMS_19.2 >> installer.zip
  unzip -p installer.zip DOOM1.WAD > "$out/doom1.wad"
  echo '1d7d43be501e67d927e415e0b8f3e29c3bf33075e859721816f652a526cac771  '"$out/doom1.wad" | sha256sum -c
  unzip -p installer.zip README.TXT > "$out/README.TXT"
  cp ${archive} "$out/doom19s.zip"
  # Binary transport only. Every WAD field is decoded by vanilla/wad.nix.
  od -An -v -t x1 "$out/doom1.wad" | tr -d ' \n' > "$out/doom1.hex"
''
