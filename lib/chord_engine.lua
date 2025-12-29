-- Nexus - Chord Engine Component
-- 15 Diatonic Chords (Triads + 7ths + Vsus4)

local ChordEngine = {}

-- Chord quality intervals (semitones from root)
local chord_intervals = {
  major = {0, 4, 7},
  minor = {0, 3, 7},
  diminished = {0, 3, 6},
  augmented = {0, 4, 8},
  major7 = {0, 4, 7, 11},
  minor7 = {0, 3, 7, 10},
  dominant7 = {0, 4, 7, 10},
  dim7 = {0, 3, 6, 9},
  halfdim7 = {0, 3, 6, 10},
  sus2 = {0, 2, 7},
  sus4 = {0, 5, 7},
  add9 = {0, 4, 7, 14},
  dom9 = {0, 4, 7, 10, 14}
}

-- 15 chord slots (diatonic chords in major scale)
local chord_slots = {}

-- Scale context
local scale_context = {
  root_note = 60,              -- MIDI note (C4 = 60)
  scale_type = "major",
  scale_intervals = {0,2,4,5,7,9,11}  -- Major scale
}

-- musicutil library (loaded in init)
musicutil = nil

-----------------------------------
-- INITIALIZATION
-----------------------------------

function ChordEngine.init()
  print("ChordEngine: Initializing...")
  
  -- Load musicutil library
  musicutil = require("musicutil")
  
  -- Initialize with default scale (will be overridden by params)
  scale_context.root_note = 60
  scale_context.scale_type = "major"
  scale_context.scale_intervals = {0,2,4,5,7,9,11}
  
  -- Don't call set_scale here - let params do it after setup
  -- This prevents the "snap to C" issue
  
  print("ChordEngine: Ready! (waiting for scale params)")
end

-----------------------------------
-- CHORD GENERATION
-----------------------------------

-- Generate all 15 chords based on current scale
function ChordEngine.generate_all_chords()
  local scale_degrees = scale_context.scale_intervals
  local root = scale_context.root_note
  
  -- Slots 1-7: Diatonic triads (I, ii, iii, IV, V, vi, vii°)
  chord_slots[1] = ChordEngine.build_triad(root, scale_degrees, 0)  -- I (major)
  chord_slots[2] = ChordEngine.build_triad(root, scale_degrees, 1)  -- ii (minor)
  chord_slots[3] = ChordEngine.build_triad(root, scale_degrees, 2)  -- iii (minor)
  chord_slots[4] = ChordEngine.build_triad(root, scale_degrees, 3)  -- IV (major)
  chord_slots[5] = ChordEngine.build_triad(root, scale_degrees, 4)  -- V (major)
  chord_slots[6] = ChordEngine.build_triad(root, scale_degrees, 5)  -- vi (minor)
  chord_slots[7] = ChordEngine.build_triad(root, scale_degrees, 6)  -- vii° (dim)
  
  -- Slots 8-14: Diatonic 7th chords (Imaj7, ii7, iii7, IVmaj7, V7, vi7, viiø7)
  chord_slots[8] = ChordEngine.build_seventh(root, scale_degrees, 0)   -- Imaj7
  chord_slots[9] = ChordEngine.build_seventh(root, scale_degrees, 1)   -- ii7
  chord_slots[10] = ChordEngine.build_seventh(root, scale_degrees, 2)  -- iii7
  chord_slots[11] = ChordEngine.build_seventh(root, scale_degrees, 3)  -- IVmaj7
  chord_slots[12] = ChordEngine.build_seventh(root, scale_degrees, 4)  -- V7
  chord_slots[13] = ChordEngine.build_seventh(root, scale_degrees, 5)  -- vi7
  chord_slots[14] = ChordEngine.build_seventh(root, scale_degrees, 6)  -- viiø7
  
  -- Slot 15: Vsus4 (suspension - creates tension/release)
  chord_slots[15] = ChordEngine.build_chord_from_intervals(
    root + scale_degrees[(4 % 7) + 1],  -- V root
    chord_intervals.sus4
  )
  
  -- Print chord names
  for i = 1, 15 do
    local chord_name = ChordEngine.get_chord_name(i)
    print("  Slot " .. i .. ": " .. chord_name)
  end
end

-- Build triad from scale degree
function ChordEngine.build_triad(root, scale_intervals, degree, inversion)
  inversion = inversion or 0
  
  -- Get scale degree notes (1st, 3rd, 5th)
  local intervals = {
    scale_intervals[(degree % 7) + 1],      -- Root
    scale_intervals[((degree + 2) % 7) + 1], -- 3rd
    scale_intervals[((degree + 4) % 7) + 1]  -- 5th
  }
  
  -- Build notes
  local notes = {}
  for _, interval in ipairs(intervals) do
    table.insert(notes, root + interval)
  end
  
  -- Apply inversion
  notes = ChordEngine.apply_inversion(notes, inversion)
  
  return {
    notes = notes,
    degree = degree,
    quality = ChordEngine.detect_quality(intervals),
    root = root + scale_intervals[(degree % 7) + 1]
  }
end

-- Build 7th chord from scale degree
function ChordEngine.build_seventh(root, scale_intervals, degree, inversion)
  inversion = inversion or 0
  
  -- Get scale degree notes (1st, 3rd, 5th, 7th)
  local intervals = {
    scale_intervals[(degree % 7) + 1],      -- Root
    scale_intervals[((degree + 2) % 7) + 1], -- 3rd
    scale_intervals[((degree + 4) % 7) + 1], -- 5th
    scale_intervals[((degree + 6) % 7) + 1]  -- 7th
  }
  
  -- Build notes
  local notes = {}
  for _, interval in ipairs(intervals) do
    table.insert(notes, root + interval)
  end
  
  -- Apply inversion
  notes = ChordEngine.apply_inversion(notes, inversion)
  
  return {
    notes = notes,
    degree = degree,
    quality = ChordEngine.detect_quality(intervals) .. "7",
    root = root + scale_intervals[(degree % 7) + 1]
  }
end

-- Detect chord quality from intervals
function ChordEngine.detect_quality(intervals)
  if #intervals < 3 then return "?" end
  
  local third = (intervals[2] - intervals[1]) % 12
  local fifth = (intervals[3] - intervals[1]) % 12
  
  if third == 4 and fifth == 7 then
    return "maj"
  elseif third == 3 and fifth == 7 then
    return "min"
  elseif third == 3 and fifth == 6 then
    return "dim"
  elseif third == 4 and fifth == 8 then
    return "aug"
  else
    return "?"
  end
end

-- Apply inversion to chord notes
function ChordEngine.apply_inversion(notes, inversion)
  if inversion == 0 then
    return notes
  elseif inversion == 1 then
    -- First inversion
    local note_copy = {}
    for i, n in ipairs(notes) do table.insert(note_copy, n) end
    local lowest = table.remove(note_copy, 1)
    table.insert(note_copy, lowest + 12)
    return note_copy
  elseif inversion == 2 then
    -- Second inversion
    local note_copy = {}
    for i, n in ipairs(notes) do table.insert(note_copy, n) end
    if #note_copy >= 2 then
      local lowest1 = table.remove(note_copy, 1)
      local lowest2 = table.remove(note_copy, 1)
      table.insert(note_copy, lowest1 + 12)
      table.insert(note_copy, lowest2 + 12)
    end
    return note_copy
  end
  return notes
end

-- Build chord directly from interval pattern (for non-diatonic chords)
function ChordEngine.build_chord_from_intervals(root_note, intervals)
  local notes = {}
  for _, interval in ipairs(intervals) do
    table.insert(notes, root_note + interval)
  end
  
  return {
    notes = notes,
    degree = nil,
    quality = ChordEngine.detect_quality_from_intervals(intervals),
    root = root_note
  }
end

-- Detect quality from raw intervals
function ChordEngine.detect_quality_from_intervals(intervals)
  if #intervals < 2 then return "?" end
  
  -- Check for sus chords first
  if #intervals == 3 then
    local second = intervals[2]
    local third = intervals[3]
    if second == 2 and third == 7 then return "sus2" end
    if second == 5 and third == 7 then return "sus4" end
  end
  
  -- Check for extended chords
  if #intervals == 4 then
    local second = intervals[2]
    local third = intervals[3]
    local fourth = intervals[4]
    if second == 4 and third == 7 and fourth == 14 then return "add9" end
    if second == 4 and third == 7 and fourth == 10 then return "7" end
    if second == 4 and third == 7 and fourth == 11 then return "maj7" end
  end
  
  -- Fall back to basic detection
  if #intervals >= 3 then
    local third_interval = intervals[2]
    local fifth_interval = intervals[3]
    
    if third_interval == 4 and fifth_interval == 7 then
      return "maj"
    elseif third_interval == 3 and fifth_interval == 7 then
      return "min"
    elseif third_interval == 3 and fifth_interval == 6 then
      return "dim"
    elseif third_interval == 4 and fifth_interval == 8 then
      return "aug"
    end
  end
  
  return "?"
end

-----------------------------------
-- PUBLIC INTERFACE
-----------------------------------

-- Get chord notes by slot ID
function ChordEngine.get_chord(slot_id)
  if slot_id < 1 or slot_id > 15 then 
    print("ChordEngine: Invalid slot ID " .. slot_id)
    return {} 
  end
  
  local slot = chord_slots[slot_id]
  if not slot then 
    return {} 
  end
  
  return slot.notes
end

-- Set scale (root note + type)
function ChordEngine.set_scale(root_midi, scale_type)
  scale_context.root_note = root_midi
  scale_context.scale_type = scale_type or "major"
  
  -- Get scale intervals from musicutil
  if musicutil then
    local scale_name = scale_type:gsub("^%l", string.upper)
    local scale = musicutil.generate_scale(root_midi, scale_name, 1)
    
    if scale and #scale > 0 then
      scale_context.scale_intervals = {}
      for i, note in ipairs(scale) do
        table.insert(scale_context.scale_intervals, note - root_midi)
      end
    else
      -- Fallback to major scale
      scale_context.scale_intervals = {0,2,4,5,7,9,11}
    end
  end
  
  -- Regenerate all chords
  ChordEngine.generate_all_chords()
  
  local root_name = musicutil and musicutil.note_num_to_name(root_midi) or "C"
  print("ChordEngine: Scale set to " .. root_name .. " " .. scale_type)
end

-- Get current scale info
function ChordEngine.get_scale()
  return scale_context
end

-- Get chord name for display
function ChordEngine.get_chord_name(slot_id)
  if slot_id < 1 or slot_id > 15 then return "---" end
  
  local slot = chord_slots[slot_id]
  if not slot then return "---" end
  
  local root_name = musicutil and musicutil.note_num_to_name(slot.root) or "?"
  
  return root_name .. slot.quality
end

-- Get roman numeral for chord slot
function ChordEngine.get_chord_numeral(slot_id)
  local numerals = {"I", "ii", "iii", "IV", "V", "vi", "vii°"}
  local numeral_7ths = {"Imaj7", "ii7", "iii7", "IVmaj7", "V7", "vi7", "viiø7"}
  
  if slot_id >= 1 and slot_id <= 7 then
    return numerals[slot_id]
  elseif slot_id >= 8 and slot_id <= 14 then
    return numeral_7ths[slot_id - 7]
  elseif slot_id == 15 then
    return "Vsus4"  -- Tension chord
  end
  
  return "?"
end

-----------------------------------
-- CLEANUP
-----------------------------------

function ChordEngine.cleanup()
  print("ChordEngine: Cleanup")
end

return ChordEngine
