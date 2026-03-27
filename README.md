# Retrospects Playbox

Stripped-down MIDI jukebox for The Retrospects live rig. Loads any MIDI file and auto-maps tracks to the band's 4 instruments.

## The Rig

| Synth | Role | MIDI Ch |
|-------|------|---------|
| Moog Grandmother | Bass | 2 |
| Sequential OB-6 | Lead + Chords | 4 |
| Sequential Rev2 | Chords (layer) | 11 |
| Internal Drums | Drums | -- |

Single chord track layers to both OB-6 + Rev2. Multiple chord tracks split between them.

Drum engine: 808 / 707 / 606 / DrumTraks with LPF + delay.

MIDI filter defaults strip excessive notes: quantize 1/8, min velocity 25, min duration 50ms.

## How It Works

Drop any standard MIDI file in `~/dust/data/midi/`. The script auto-detects track roles (bass/chord/lead/drum) by name and note range, then routes each to the right synth. Reassign on the Tracks page if the auto-detect gets it wrong.

## Pages

### PLAY (page 1)
Now playing with synth activity bars (GM / OB6 / REV2 / DRM).

- **E2**: BPM
- **E3**: next song
- **K2**: play/stop
- **K3**: restart

### TRACKS (page 2)
Per-track routing. Reassign any track to a different synth.

- **E2**: select track
- **E3**: cycle synth assignment (GM/OB6/REV2/DRM/OFF)
- **K2**: toggle field (synth vs octave)
- **K3**: toggle mute

### DRUMS (page 3)
Drum engine controls: kit, volume, LPF, resonance, randomize.

### SONGS (page 4)
Queue + library browser. **K2** toggles between queue and library views.

- Queue: **E2** scroll, **E3** reorder, **K3** play, **K1+K2** remove, **K1+K3** save playlist
- Library: **E2/E3** scroll, **K3** add to queue, **K1+K3** toggle favorite

## MIDIMIX

```
FADERS 1-4:  synth track velocity (GM, OB6, REV2, DRM)
MUTE 1-4:    toggle track mute
MASTER:      BPM (20-300)
KNOB ROW 2 col 8: drum LPF
KNOB ROW 1 col 8: delay mix
KNOB ROW 3 col 8: delay time
BANK L/R:    prev/next song
SEND ALL:    PANIC
```

## Install

```
;install https://github.com/cfurrow7/retrospects-playbox.git
```

Place `.mid` files in `~/dust/data/midi/`.

## Credits

Forked from [midi-playbox](https://github.com/cfurrow7/midi-playbox). v1.0 @clf
