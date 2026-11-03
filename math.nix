let
  native = builtins.math or (throw "doom-nix requires mathnix; use the packaged launcher (nix run .)");
  integers = builtins.all builtins.isInt;
  exactFloat = x: x >= -9007199254740992 && x <= 9007199254740992;
  # mathnix's real bounds functions return floats. Keep indices integral, and
  # select original operands beyond binary64's exact integer range.
  bound = operation: select: a: b:
    if integers [ a b ] then
      if exactFloat a && exactFloat b then native.floor (operation a b) else select a b
    else operation a b;
in rec {
  min = bound native.min (a: b: if a < b then a else b);
  max = bound native.max (a: b: if a > b then a else b);
  inherit (native) abs pi tau sin cos sqrt atan2;
  clamp = low: high: x:
    if integers [ low high x ] then
      if builtins.all exactFloat [ low high x ] then native.floor (native.clamp low high x)
      else assert low <= high; max low (min high x)
    else native.clamp low high x;
  mod = a: b: if integers [ a b ] then native.mod a b else
    let remainder = native.fmod a b;
    in if remainder < 0 then remainder + b else remainder;
  wrap = angle:
    let remainder = native.remainder angle tau;
    in if remainder >= pi then remainder - tau else remainder;
  length = native.hypot;
  distance = a: b: length (a.x - b.x) (a.y - b.y);
  range = n: builtins.genList (i: i) n;
  concatMap = f: xs: builtins.concatLists (map f xs);
  indexed = f: xs: builtins.genList (i: f i (builtins.elemAt xs i)) (builtins.length xs);
  repeat = n: f: initial: builtins.foldl' (s: _: builtins.deepSeq s (f s)) initial (range n);
}
