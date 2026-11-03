{ b, offset ? 0, size ? b.size - offset }:
let
  m = import ../math.nix;
  mod = a: n: a - builtins.div a n * n;
  header = p: b.u16 (offset + p);
  scoreStart = offset + header 6;
  scoreEnd = scoreStart + header 4;
  primaryChannels = header 8;
  instrumentCount = header 12;
  byte = p: if p < scoreStart || p >= scoreEnd then throw "MUS: truncated score"
    else b.u8 p;
  midiChannel = channel: if channel == 15 then 9 else if channel >= 9 then channel + 1 else channel;
  controllers = [ 0 0 1 7 10 11 91 93 64 67 120 123 126 127 121 ];
  dataByte = p: let value = byte p;
    in if value > 127 then throw "MUS: invalid MIDI data byte" else value;
  delay = p: count: value:
    if count == 4 then throw "MUS: delay exceeds MIDI variable-length range" else
    let part = byte p; next = value * 128 + mod part 128;
    in if part < 128 then { value = next; position = p + 1; } else delay (p + 1) (count + 1) next;
  states = builtins.genericClosure {
    startSet = [ { key = scoreStart; clock = 0; pending = 0; velocity = {}; data = []; delta = 0; done = false; } ];
    operator = previous:
      if previous.done then [] else
      let
        descriptor = byte previous.key;
        channel = mod descriptor 16;
        midi = midiChannel channel;
        type = mod (builtins.div descriptor 16) 8;
        p = previous.key + 1;
        raw = byte p;
        hasVelocity = type == 1 && raw >= 128;
        velocity = if hasVelocity then dataByte (p + 1) else previous.velocity.${toString channel} or 127;
        controller = if type == 3 || type == 4 then dataByte p else 0;
        controllerNumber = if controller >= builtins.length controllers then throw "MUS: invalid controller"
          else builtins.elemAt controllers controller;
        data = if type == 0 then [ (128 + midi) (dataByte p) 0 ]
          else if type == 1 then [ (144 + midi) (mod raw 128) velocity ]
          else if type == 2 then [ (224 + midi) (mod raw 2 * 64) (builtins.div raw 2) ]
          else if type == 3 then
            if controller < 10 then throw "MUS: invalid system event" else
              [ (176 + midi) controllerNumber (if controller == 12 then primaryChannels + 1 else 0) ]
          else if type == 4 then
            if controller > 9 then throw "MUS: invalid control change" else
              if controller == 0 then [ (192 + midi) (dataByte (p + 1)) ]
              else [ (176 + midi) controllerNumber (dataByte (p + 1)) ]
          else if type == 6 then [ 255 47 0 ] else throw "MUS: unsupported event type";
        position = p + (if type == 6 then 0 else if type == 4 || hasVelocity then 2 else 1);
        wait = if descriptor < 128 || type == 6 then { value = 0; inherit position; } else delay position 0 0;
      in [ { key = wait.position; clock = previous.clock + wait.value; pending = wait.value;
        velocity = previous.velocity // (if type == 1 then { ${toString channel} = velocity; } else {});
        inherit data; delta = previous.pending; done = type == 6;
      } ];
  };
  events = builtins.tail states;
  vlq = value:
    let prefix = n: if n < 128 then [ (n + 128) ] else prefix (builtins.div n 128) ++ [ (mod n 128 + 128) ];
    in if value < 128 then [ value ] else prefix (builtins.div value 128) ++ [ (mod value 128) ];
  be16 = n: [ (builtins.div n 256) (mod n 256) ];
  be32 = n: be16 (builtins.div n 65536) ++ be16 (mod n 65536);
  # 70 ticks/quarter at 500,000 us/quarter preserves MUS's 140 Hz clock.
  track = [ 0 255 81 3 7 161 32 ] ++ m.concatMap (event: vlq event.delta ++ event.data) events;
in assert size >= 16 && offset >= 0 && offset + size <= b.size;
   assert builtins.genList (i: b.u8 (offset + i)) 4 == [ 77 85 83 26 ];
   assert primaryChannels <= 15 && scoreStart >= offset + 16 + instrumentCount * 2 && scoreEnd <= offset + size;
   {
     inherit events vlq;
     ticks = (builtins.elemAt states (builtins.length states - 1)).clock;
     instruments = builtins.genList (i: header (16 + i * 2)) instrumentCount;
     midi = [ 77 84 104 100 0 0 0 6 0 0 0 1 0 70 77 84 114 107 ] ++ be32 (builtins.length track) ++ track;
   }
