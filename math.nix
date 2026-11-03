let native = builtins.math or (throw "doom-nix requires mathnix; use the packaged launcher (nix run .)");
in rec {
  min = a: b: if a < b then a else b;
  max = a: b: if a > b then a else b;
  inherit (native) abs pi tau sin cos sqrt atan2;
  clamp = low: high: x: max low (min high x);
  mod = a: b: a - builtins.floor (a / (b * 1.0)) * b;
  wrap = a: mod (a + pi) tau - pi;
  length = native.hypot;
  distance = a: b: length (a.x - b.x) (a.y - b.y);
  range = n: builtins.genList (i: i) n;
  concatMap = f: xs: builtins.concatLists (map f xs);
  indexed = f: xs: builtins.genList (i: f i (builtins.elemAt xs i)) (builtins.length xs);
  repeat = n: f: initial: builtins.foldl' (s: _: builtins.deepSeq s (f s)) initial (range n);
}
