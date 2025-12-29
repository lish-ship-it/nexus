# Nexus

Generative chord sequencer for monome Norns.

Select chords from a 15-chord diatonic palette, let the probabilistic engine trigger notes, play along on the Grid. Outputs MIDI and Crow CV/Gate.

## Requirements

- Norns
- Grid 128 (optional but recommended)
- MIDI device and/or Crow

## Installation

From Maiden:
```
;install https://github.com/lish-ship-it/nexus
```

Or manually copy the `nexus` folder to `~/dust/code/`

## Grid Layout

```
Row 1:  Chord selection (15 chords)
Row 2:  Chord notes visualization
Row 3:  Active note triggers
Row 5:  Playable notes (lower octave)
Row 6:  Playable notes (upper octave)
Row 8:  Transport
```

### Row 1: Chords

| Pads | Chords |
|------|--------|
| 1-7 | Triads (I, ii, iii, IV, V, vi, vii°) |
| 8-14 | 7ths (Imaj7, ii7, iii7, IVmaj7, V7, vi7, viiø7) |
| 15 | Vsus4 |

### Row 8: Transport

| Pad | Function |
|-----|----------|
| 1 | Play / Stop |
| 2 | Random Chord Sequencer |
| 4 | Bass Sequencer |
| 5 | Sub-Bass Sequencer |

## Norns Controls

| Control | Function |
|---------|----------|
| K2 | Play / Stop |
| K3 | Panic (stop all notes) |
| E1 | Tempo |
| E2 | Probability |
| E3 | MIDI Channel |

## Parameters

### Generative
- **Tempo**: 40-300 BPM
- **Probability**: Chance each note triggers per beat (0-100%)
- **Random Sequencer**: Auto-select chords every 4 bars
- **Bass Sequencer**: Root note -1 octave on chord changes
- **Sub-Bass Sequencer**: Root note -2 octaves on chord changes

### Scale
- **Root Note**: C3-C5
- **Scale Type**: Major, Minor, Dorian, Phrygian, Lydian, Mixolydian, Locrian, Harmonic Minor, Melodic Minor, Whole Tone, Pentatonic Major, Pentatonic Minor, Blues, Chromatic

### MIDI Output
- **Device**: 1-16
- **Channel**: 1-16
- **Velocity**: Base velocity for notes

### Crow Output
- **Enable**: On/Off
- **Note Mode**: Root, Highest, Lowest, or Last Triggered
- **Gate Length**: Duration in seconds
- **Out 3**: Velocity CV, Envelope, or Off
- **Out 4**: Trigger, Clock, or Off

#### Crow Outputs

| Output | Signal |
|--------|--------|
| 1 | V/Oct (pitch) |
| 2 | Gate |
| 3 | Velocity CV or AR envelope |
| 4 | Trigger or clock pulse |

## How It Works

Every whole note (4 beats), the engine looks at the current chord and rolls probability for each note. Notes that pass are triggered with slight timing variations for organic movement.

- Chord notes hold for 2-5 beats
- Bass notes hold for 4-10 beats
- Sub-bass notes hold for 6-12 beats

The random chord sequencer picks a new chord every 4 whole notes (16 beats).

## Roadmap

- Just Friends integration (i2c)
- W/ integration

## Credits

Built with [Claude Code](https://claude.ai).

## License

MIT
