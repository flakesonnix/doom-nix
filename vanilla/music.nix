{ pkgs, iwad }:
let
  wad = import ./wad.nix (builtins.readFile "${iwad}/doom1.hex");
  names = builtins.filter (name: builtins.substring 0 2 name == "D_") (builtins.attrNames wad.named);
  mod = a: n: a - builtins.div a n * n;
  octal = "01234567";
  byte = n: "\\${builtins.substring (builtins.div n 64) 1 octal}${builtins.substring (mod (builtins.div n 8) 8) 1 octal}${builtins.substring (mod n 8) 1 octal}";
  scores = builtins.listToAttrs (builtins.map (name:
    let lump = wad.lump name;
    in { inherit name; value = import ./mus.nix { inherit (wad) b; inherit (lump) offset size; }; }
  ) names);
  files = builtins.map (name: { inherit name;
    source = pkgs.writeText "${name}-midi-bytes" (builtins.concatStringsSep "" (builtins.map byte scores.${name}.midi));
  }) names;
in {
  inherit names scores;
  package = pkgs.runCommand "doom-1.9-music" {
    nativeBuildInputs = [ pkgs.fluidsynth pkgs.ffmpeg-headless pkgs.python3 ];
  } (''
    mkdir -p "$out"
    soundfont=${pkgs.soundfont-fluid}/share/soundfonts/FluidR3_GM2-2.sf2
    test -f "$soundfont"
  '' + builtins.concatStringsSep "\n" (builtins.map (file: ''
    printf '%b' "$(cat ${file.source})" > "$out/${file.name}.mid"
    # MUS parsing, channel/controller mapping and MIDI timing are Nix. These
    # generic tools only synthesize GM notes and encode streamed audio.
    fluidsynth -ni -r 44100 -F "$TMPDIR/${file.name}.wav" -T wav -O s16 \
      "$soundfont" "$out/${file.name}.mid"
    # FluidSynth can exit successfully with no loaded instruments. Verify PCM,
    # rather than accepting a silent file with valid duration and headers.
    python - "$TMPDIR/${file.name}.wav" <<'PY'
    import array, sys, wave
    with wave.open(sys.argv[1], 'rb') as source:
        assert source.getsampwidth() == 2
        samples = array.array('h', source.readframes(source.getnframes()))
    assert samples and max(abs(s) for s in samples) > 32, 'silent synthesized score'
    PY
    ffmpeg -nostdin -v error -i "$TMPDIR/${file.name}.wav" \
      -t ${builtins.toJSON (scores.${file.name}.ticks / 140.0)} \
      -c:a libvorbis -q:a 5 "$out/${file.name}.ogg"
  '') files));
}
