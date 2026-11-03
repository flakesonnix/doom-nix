let
  monster = sprite: hp: radius: height: speed: pain: death: {
    inherit sprite hp radius height speed pain death;
    kind = "monster"; solid = true;
  };
  item = sprite: kind: amount: { inherit sprite kind amount; solid = false; radius = 20; height = 16; };
  decor = sprite: solid: radius: height: { inherit sprite solid radius height; kind = "decor"; };
  state = sprite: tics: action: { inherit sprite tics action; };
in {
  ticRate = 35;
  player = { radius = 16; height = 56; viewHeight = 41; maxMove = 30; friction = 0.90625;
    forward = [ 25 50 ]; side = [ 24 40 ]; };
  skills = [ "I'm too young to die." "Hey, not too rough." "Hurt me plenty." "Ultra-Violence." "Nightmare!" ];
  mapNames = [ "Hangar" "Nuclear Plant" "Toxin Refinery" "Command Control" "Phobos Lab"
    "Central Processing" "Computer Station" "Phobos Anomaly" "Military Base" ];
  pars = [ 30 75 120 90 165 180 180 30 165 ];
  # Doom's deterministic 256-byte gameplay random table (P_Random).
  random = [
    0 8 109 220 222 241 149 107 75 248 254 140 16 66 74 21 211 47 80 242 154 27 205 128 161 89 77 36
    95 110 85 48 212 140 211 249 22 79 200 50 28 188 52 140 202 120 68 145 62 70 184 190 91 197 152 224
    149 104 25 178 252 182 202 182 141 197 4 81 181 242 145 42 39 227 156 198 225 193 219 93 122 175 249 0
    175 143 70 239 46 246 163 53 163 109 168 135 2 235 25 92 20 145 138 77 69 166 78 176 173 212 166 113
    94 161 41 50 239 49 111 164 70 60 2 37 171 75 136 156 11 56 42 146 138 229 73 146 77 61 98 196
    135 106 63 197 195 86 96 203 113 101 170 247 181 113 80 250 108 7 255 237 129 226 79 107 112 166 103 241
    24 223 239 120 198 58 60 82 128 3 184 66 143 224 145 224 81 206 163 45 63 90 168 114 59 33 159 95
    28 139 123 98 125 196 15 70 194 253 54 14 109 226 71 17 161 93 186 87 244 138 20 52 123 251 26 36
    17 46 52 231 232 76 31 221 84 37 216 165 212 106 197 242 98 43 39 175 254 145 190 84 118 222 187 136
    120 163 236 249
  ];
  types = {
    "3004" = monster "POSS" 20 20 56 8 "G" "HIJKL";
    "9" = monster "SPOS" 30 20 56 8 "G" "HIJKL";
    "3001" = monster "TROO" 60 20 56 8 "H" "IJKLM";
    "3002" = monster "SARG" 150 30 56 10 "H" "IJKLMN";
    "58" = (monster "SARG" 150 30 56 10 "H" "IJKLMN") // { spectre = true; };
    "3003" = monster "BOSS" 1000 24 64 8 "H" "IJKLMNO";
    "2035" = (decor "BAR1A0" true 10 42) // { kind = "barrel"; hp = 20; };
    "2001" = item "SHOTA0" "shotgun" 8;
    "2002" = item "MGUNA0" "chaingun" 20;
    "2003" = item "LAUNA0" "rocket" 2;
    "2005" = item "CSAWA0" "chainsaw" 0;
    "2007" = item "CLIPA0" "bullets" 10;
    "2048" = item "AMMOA0" "bullets" 50;
    "2008" = item "SHELA0" "shells" 4;
    "2049" = item "SBOXA0" "shells" 20;
    "2010" = item "ROCKA0" "rockets" 1;
    "2046" = item "BROKA0" "rockets" 5;
    "8" = item "BPAKA0" "backpack" 1;
    "2011" = item "STIMA0" "health" 10;
    "2012" = item "MEDIA0" "health" 25;
    "2014" = item "BON1A0" "healthBonus" 1;
    "2015" = item "BON2A0" "armorBonus" 1;
    "2018" = item "ARM1A0" "greenArmor" 100;
    "2019" = item "ARM2A0" "blueArmor" 200;
    "2013" = item "SOULA0" "soul" 100;
    "2022" = item "PINVA0" "invulnerability" 1050;
    "2023" = item "PSTRA0" "berserk" 1;
    "2024" = item "PINSA0" "invisibility" 2100;
    "2025" = item "SUITA0" "suit" 2100;
    "2026" = item "PMAPA0" "map" 1;
    "2045" = item "PVISA0" "light" 4200;
    "5" = item "BKEYA0" "blueKey" 1;
    "6" = item "YKEYA0" "yellowKey" 1;
    "13" = item "RKEYA0" "redKey" 1;
    "10" = decor "PLAYW0" false 16 16;
    "12" = decor "PLAYN0" false 16 16;
    "15" = decor "PLAYN0" false 16 16;
    "24" = decor "POL5A0" false 16 16;
    "34" = decor "CANDA0" false 16 16;
    "35" = decor "CBRAA0" true 16 16;
    "46" = decor "TREDA0" true 16 16;
    "48" = decor "ELECA0" true 16 128;
    "2028" = decor "COLUA0" true 16 48;
  };
  weapons = {
    fist = { ready = "PUNGA0"; ammo = null; range = 64; sound = "DSPUNCH"; pellets = 1;
      states = [ (state "PUNGB0" 4 null) (state "PUNGC0" 4 "punch") (state "PUNGD0" 5 null)
        (state "PUNGC0" 4 null) (state "PUNGB0" 5 "refire") ]; };
    pistol = { ready = "PISGA0"; ammo = "bullets"; range = 2048; sound = "DSPISTOL"; pellets = 1;
      states = [ (state "PISGA0" 4 null) (state "PISGB0" 6 "hitscan")
        (state "PISGC0" 4 null) (state "PISGB0" 5 "refire") ]; };
    shotgun = { ready = "SHTGA0"; ammo = "shells"; range = 2048; sound = "DSSHOTGN"; pellets = 7;
      states = [ (state "SHTGA0" 3 null) (state "SHTGA0" 7 "hitscan") (state "SHTGB0" 5 null)
        (state "SHTGC0" 5 null) (state "SHTGD0" 4 null) (state "SHTGC0" 5 null)
        (state "SHTGB0" 5 null) (state "SHTGA0" 3 null) (state "SHTGA0" 7 "refire") ]; };
    chaingun = { ready = "CHGGA0"; ammo = "bullets"; range = 2048; sound = "DSPISTOL"; pellets = 1;
      states = [ (state "CHGGA0" 4 "hitscan") (state "CHGGB0" 4 "hitscan") (state "CHGGB0" 0 "refire") ]; };
    rocket = { ready = "MISGA0"; ammo = "rockets"; range = 2048; sound = "DSRLAUNC"; pellets = 1;
      states = [ (state "MISGB0" 8 null) (state "MISGB0" 12 "rocket") (state "MISGB0" 0 "refire") ]; };
    chainsaw = { ready = "SAWGC0"; ammo = null; range = 65; sound = "DSSAWFUL"; pellets = 1;
      states = [ (state "SAWGA0" 4 "punch") (state "SAWGB0" 4 "punch") (state "SAWGB0" 0 "refire") ]; };
  };
  # All action types appearing in the unmodified shareware maps. Separate use,
  # walk-over, and gun triggers prevent switches activating just by touching.
  useSpecials = [ 1 7 9 11 18 20 23 26 27 28 29 31 32 33 34 42 50 51 61 62 63 70 71 103 117 118 ];
  walkSpecials = [ 2 3 4 5 8 16 22 35 36 52 53 54 56 57 58 59 72 73 74 75 76 77 79 80 81 82 83 84 86 87 88 89 90 91 92 93 94 95 96 97 98 ];
  repeatSpecials = [ 1 26 27 28 42 61 62 63 70 72 73 74 75 76 77 79 80 81 82 83 84 86 87 88 89 90 91 92 93 94 95 96 97 98 ];
}
