{ runCommand }:
let
  m = import ./math.nix;
  rate = 8000;
  effects = {
    pistol = { duration = 0.13; frequency = 135; noise = 0.8; };
    shotgun = { duration = 0.28; frequency = 68; noise = 0.95; };
    chaingun = { duration = 0.09; frequency = 180; noise = 0.75; };
    punch = { duration = 0.10; frequency = 70; noise = 0.25; };
    hurt = { duration = 0.18; frequency = 110; noise = 0.5; };
    kill = { duration = 0.25; frequency = 85; noise = 0.6; };
    door = { duration = 0.35; frequency = 60; noise = 0.45; };
    pickup = { duration = 0.16; frequency = 880; noise = 0.0; };
    exit = { duration = 0.45; frequency = 440; noise = 0.0; };
  };
  mod = a: b: a - builtins.div a b * b;
  digits = [ "0" "1" "2" "3" "4" "5" "6" "7" ];
  byte = n: "\\${builtins.elemAt digits (builtins.div n 64)}${builtins.elemAt digits (mod (builtins.div n 8) 8)}${builtins.elemAt digits (mod n 8)}";
  le = bytes: n: if bytes == 0 then "" else byte (mod n 256) + le (bytes - 1) (builtins.div n 256);
  wav = effect:
    let
      frames = builtins.floor (effect.duration * rate);
      pcm = builtins.concatStringsSep "" (builtins.genList (i:
        let t = i / (rate * 1.0); envelope = 1.0 - i / (frames * 1.0);
            hiss = m.mod (i * 1103515245 + 12345 + i * i * 97) 65536 / 32768.0 - 1;
            tone = m.sin (m.tau * effect.frequency * t * (1 - t));
            sample = builtins.floor ((tone * (1 - effect.noise) + hiss * effect.noise) * envelope * envelope * 18000);
        in le 2 (if sample < 0 then sample + 65536 else sample)
      ) frames);
    in "RIFF" + le 4 (36 + frames * 2) + "WAVEfmt " + le 4 16 + le 2 1 + le 2 1
      + le 4 rate + le 4 (rate * 2) + le 2 2 + le 2 16 + "data" + le 4 (frames * 2) + pcm;
in
# Nix synthesizes PCM and headers; printf only writes the resulting bytes.
runCommand "doom-nix-sounds" {} (''
  mkdir -p "$out"
'' + builtins.concatStringsSep "\n" (map (name: ''
  printf '%b' '${wav effects.${name}}' > "$out/${name}.wav"
'') (builtins.attrNames effects)))
