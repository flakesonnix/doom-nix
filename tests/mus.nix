{ wad }:
let
  digits = "0123456789abcdef";
  mod = n: d: n - builtins.div n d * d;
  encode = bytes: builtins.concatStringsSep "" (builtins.map (n:
    builtins.substring (builtins.div n 16) 1 digits + builtins.substring (mod n 16) 1 digits) bytes);
  parse = events:
    let length = builtins.length events;
        b = import ../vanilla/binary.nix (encode ([ 77 85 83 26 (mod length 256) (builtins.div length 256)
          16 0 2 0 0 0 0 0 0 0 ] ++ events));
    in import ../vanilla/mus.nix { inherit b; };
  score = parse [ 16 188 90 17 61 144 62 129 0 32 129 31 163 100 25 64 64 0 30 64 3 100 48 12 128 60 1 96 ];
  events = builtins.map (e: e.data) score.events;
  all = builtins.map (name:
    let lump = wad.lump name;
    in import ../vanilla/mus.nix { inherit (wad) b; inherit (lump) offset size; }
  ) (builtins.filter (name: builtins.substring 0 2 name == "D_") (builtins.attrNames wad.named));
  rejects = bytes: !(builtins.tryEval (builtins.deepSeq (parse bytes).midi true)).success;
in {
  musVelocityPersistsPerChannel = builtins.elemAt events 0 == [ 144 60 90 ]
    && builtins.elemAt events 1 == [ 145 61 127 ] && builtins.elemAt events 2 == [ 144 62 90 ];
  musPercussionUsesMidiChannelTen = builtins.elemAt events 4 == [ 153 35 100 ];
  musMelodicChannelsSkipPercussion = builtins.elemAt events 5 == [ 154 64 127 ];
  musPitchBendPreservesLowBits = builtins.elemAt events 3 == [ 224 64 64 ];
  musProgramAndVolumeMapping = builtins.elemAt events 6 == [ 192 30 ] && builtins.elemAt events 7 == [ 176 7 100 ];
  musMonoModeUsesChannelCount = builtins.elemAt events 8 == [ 176 126 3 ];
  musReleasesNotes = builtins.elemAt events 9 == [ 128 60 0 ];
  musGroupDelaysAccumulate = score.ticks == 129 && (builtins.elemAt score.events 3).delta == 128
    && (builtins.elemAt score.events 10).delta == 1;
  musMidiVariableLengthEncoding = score.vlq 0 == [ 0 ] && score.vlq 127 == [ 127 ]
    && score.vlq 128 == [ 129 0 ] && score.vlq 16384 == [ 129 128 0 ];
  musMidiHasTempoAndEndMarker = builtins.genList (i: builtins.elemAt score.midi i) 14
    == [ 77 84 104 100 0 0 0 6 0 0 0 1 0 70 ] && builtins.elemAt events 10 == [ 255 47 0 ];
  musTruncatedVelocityRejected = rejects [ 16 188 ];
  musMissingEndRejected = rejects [ 16 60 ];
  musInvalidControllerRejected = rejects [ 64 15 0 96 ];
  musOverlongDelayRejected = rejects [ 144 60 128 128 128 128 0 96 ];
  musAllOriginalScoresDecode = builtins.length all == 13 && builtins.all (s:
    s.ticks > 0 && builtins.all (n: n >= 0 && n <= 255) s.midi) all;
  musOriginalTitleDuration = let lump = wad.lump "D_INTRO";
    in (import ../vanilla/mus.nix { inherit (wad) b; inherit (lump) offset size; }).ticks == 960;
}
