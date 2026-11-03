{ pkgs, iwad, math, nixComponents, src }:
let
  data = import ./asset-data.nix { inherit iwad; };
  assetSource = pkgs.lib.cleanSourceWith {
    inherit src;
    name = "doom-asset-source";
    filter = path: type: type == "directory" || builtins.elem (pkgs.lib.removePrefix "${src}/" path) [
      "math.nix" "vanilla/asset-data.nix" "vanilla/binary.nix" "vanilla/wad.nix"
      "vanilla/world.nix" "vanilla/geometry.nix"
    ];
  };
in {
  inherit (data) wad patchNames wallNames flatNames maps;
  # Keep expensive WAD/geometry evaluation out of `nix run`'s flake evaluation.
  # Only the cached builder invokes the matching, mathnix-enabled evaluator.
  package = pkgs.runCommand "doom-1.9-nix-assets" {
    nativeBuildInputs = [ nixComponents.nix-cli pkgs.imagemagick pkgs.python3 ];
  } ''
    export HOME="$TMPDIR/home"
    mkdir -p "$HOME" "$out"
    echo 'Decoding Doom artwork, effects and map geometry in Nix...'
    nix-instantiate --option plugin-files ${math}/lib/nix/plugins/mathnix.so \
      --eval --strict --json --expr \
      '{ iwad }: (import ${assetSource}/vanilla/asset-data.nix { inherit iwad; }).files' \
      --argstr iwad ${iwad} > "$TMPDIR/assets.json"
    # Generic byte/text serialization only: WAD decoding and compositing above
    # remain Nix. No Python game, WAD parser or geometry logic is used.
    python - "$TMPDIR/assets.json" "$out" <<'PY'
    import codecs, json, pathlib, sys
    output = pathlib.Path(sys.argv[2])
    for entry in json.loads(pathlib.Path(sys.argv[1]).read_text()):
        target = output / entry['name']
        if 'bytes' in entry:
            target.write_bytes(codecs.escape_decode(entry['bytes'].encode('ascii'))[0])
        else:
            target.write_text(entry['text'])
    PY
    magick mogrify -depth 8 -format png "$out"/*.tga
  '';
}
