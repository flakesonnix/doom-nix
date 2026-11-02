rec {
  min = a: b: if a < b then a else b;
  max = a: b: if a > b then a else b;
  abs = x: if x < 0 then -x else x;
  clamp = low: high: x: max low (min high x);
  mod = a: b: a - builtins.floor (a / (b * 1.0)) * b;
  pi = 3.141592653589793;
  tau = 2 * pi;
  wrap = a: mod (a + pi) tau - pi;
  # Range reduction keeps these Taylor polynomials accurate over every heading.
  sin = angle:
    let x = wrap angle; x2 = x * x;
    in x * (1 - x2 / 6 * (1 - x2 / 20 * (1 - x2 / 42 *
      (1 - x2 / 72 * (1 - x2 / 110 * (1 - x2 / 156))))));
  cos = angle: sin (angle + pi / 2);
  sqrt = value:
    if value <= 0 then 0.0 else
    builtins.foldl' (guess: _: (guess + value / guess) / 2.0)
      (max 1.0 value) (builtins.genList (i: i) 18);
  length = x: y: sqrt (x * x + y * y);
  distance = a: b: length (a.x - b.x) (a.y - b.y);
  range = n: builtins.genList (i: i) n;
  concatMap = f: xs: builtins.concatLists (map f xs);
  indexed = f: xs: builtins.genList (i: f i (builtins.elemAt xs i)) (builtins.length xs);
  repeat = n: f: initial: builtins.foldl' (s: _: builtins.deepSeq s (f s)) initial (range n);
}
