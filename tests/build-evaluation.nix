let
  assets = import ../vanilla/assets.nix {
    # These paths deliberately do not exist. Constructing the derivation must
    # not read the WAD or decode any pixels/geometry in the caller's evaluator.
    iwad = "/missing-doom-iwad";
    math = "/missing-mathnix";
    src = ../.;
    nixComponents.nix-cli = "/matching-nix";
    pkgs = {
      imagemagick = "/image-serializer";
      python3 = "/byte-serializer";
      lib.cleanSourceWith = _: "/asset-source";
      runCommand = _: dependencies: script: builtins.deepSeq dependencies script;
    };
  };
in builtins.stringLength assets.package > 0
