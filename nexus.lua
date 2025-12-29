-- Nexus
-- Generative Chord Sequencer with MIDI + Crow Output
-- v1.1 - Playable rows, bass/sub-bass sequencers

-- No engine needed - MIDI/Crow only
engine.name = nil

local MidiCrowOutput = include("lib/midi_crow_output")
local ChordEngine = include("lib/chord_engine")
local GenerativeEngine = include("lib/generative_engine")
local GridController = include("lib/grid_controller")

-- Track key states
local key_pressed = {false, false, false}

-- Screen refresh flag
local screen_dirty = true

-- Initialization complete flag
local initialized = false

-- Redraw metro
local redraw_metro = metro.init()
redraw_metro.time = 1/15  -- 15 fps
redraw_metro.event = function()
  if initialized then
    -- Always update Grid when playing
    GridController.redraw()
    
    -- Update screen
    if screen_dirty or GenerativeEngine.is_playing() then
      redraw()
      screen_dirty = false
    end
  end
end

-----------------------------------
-- INITIALIZATION
-----------------------------------

function init()
  print("========================================")
  print("Nexus")
  print("Generative Chord Sequencer")
  print("v1.1 - MIDI + Crow Output")
  print("========================================")
  
  -- Short delay for system init
  clock.run(function()
    clock.sleep(0.5)
    
    -- Initialize components
    print("Initializing MidiCrowOutput...")
    MidiCrowOutput.init()
    
    print("Initializing ChordEngine...")
    ChordEngine.init()
    
    print("Initializing GridController...")
    GridController.init(nil, ChordEngine, MidiCrowOutput, nil)
    
    print("Initializing GenerativeEngine...")
    GenerativeEngine.init(MidiCrowOutput, ChordEngine, GridController, nil)
    
    -- Now set the GenerativeEngine reference in GridController
    GridController.set_generative_engine(GenerativeEngine)
    
    -- Add PARAMS
    print("Setting up parameters...")
    setup_params()
    
    -- Initialize scale with default params (triggers chord generation)
    ChordEngine.set_scale(params:get("scale_root"), "major")
    
    print("")
    print("Output:")
    print("  MIDI: Notes sent to selected device")
    print("  Crow: CV/Gate on outputs 1-4")
    print("")
    print("Grid Layout:")
    print("  Row 1: Chord selection (15 chords)")
    print("  Row 2: Chord notes visualization")
    print("  Row 3: Active note triggers")
    print("  Row 5: Playable notes (lower octave)")
    print("  Row 6: Playable notes (upper octave)")
    print("  Row 8: Transport")
    print("    Pad 1: Play/Stop")
    print("    Pad 2: Sequencer On/Off")
    print("    Pad 4: Bass Sequencer")
    print("    Pad 5: Sub-Bass Sequencer")
    print("")
    print("Norns Controls:")
    print("  K2: Play/Stop")
    print("  K3: Panic (stop all notes)")
    print("  E1: Tempo")
    print("  E2: Probability")
    print("  E3: MIDI Channel")
    print("")
    print("Ready to play!")
    print("========================================")
    
    -- Start screen refresh
    redraw_metro:start()
    
    -- Mark initialization complete
    initialized = true
    
    redraw()
  end)
end

-----------------------------------
-- PARAMETERS
-----------------------------------

function setup_params()
  params:add_separator("NEXUS")
  
  -- Tempo
  params:add{
    type = "number",
    id = "tempo",
    name = "Tempo",
    min = 40,
    max = 300,
    default = 80,
    action = function(value)
      GenerativeEngine.set_tempo(value)
      screen_dirty = true
    end
  }
  
  -- Probability
  params:add{
    type = "number",
    id = "probability",
    name = "Probability",
    min = 0,
    max = 100,
    default = 25,
    action = function(value)
      GenerativeEngine.set_probability(value)
      screen_dirty = true
    end
  }
  
  -- Sequencer
  params:add{
    type = "option",
    id = "sequencer",
    name = "Random Sequencer",
    options = {"Off", "On"},
    default = 1,
    action = function(value)
      local enabled = (value == 2)
      GenerativeEngine.set_sequencer(enabled)
      GridController.update_sequencer_state(enabled)
      screen_dirty = true
    end
  }
  
  -- Bass Sequencer
  params:add{
    type = "option",
    id = "bass_sequencer",
    name = "Bass Sequencer",
    options = {"Off", "On"},
    default = 1,
    action = function(value)
      local enabled = (value == 2)
      GenerativeEngine.set_bass_sequencer(enabled)
      GridController.update_bass_seq_state(enabled)
      screen_dirty = true
    end
  }
  
  -- Sub-Bass Sequencer
  params:add{
    type = "option",
    id = "sub_bass_sequencer",
    name = "Sub-Bass Sequencer",
    options = {"Off", "On"},
    default = 1,
    action = function(value)
      local enabled = (value == 2)
      GenerativeEngine.set_sub_bass_sequencer(enabled)
      GridController.update_sub_bass_seq_state(enabled)
      screen_dirty = true
    end
  }
  
  params:add_separator("SCALE")
  
  -- Scale Root
  params:add{
    type = "number",
    id = "scale_root",
    name = "Root Note",
    min = 48,
    max = 72,
    default = 60,
    formatter = function(param)
      return musicutil.note_num_to_name(param:get())
    end,
    action = function(value)
      ChordEngine.set_scale(value, params:get("scale_type"))
      screen_dirty = true
    end
  }
  
  -- Scale Type
  params:add{
    type = "option",
    id = "scale_type",
    name = "Scale Type",
    options = {
      "Major", 
      "Minor", 
      "Dorian", 
      "Phrygian", 
      "Lydian", 
      "Mixolydian", 
      "Locrian",
      "Harmonic Minor",
      "Melodic Minor",
      "Whole Tone",
      "Pentatonic Major",
      "Pentatonic Minor",
      "Blues",
      "Chromatic"
    },
    default = 1,
    action = function(value)
      local scale_names = {
        "major", 
        "minor", 
        "dorian", 
        "phrygian", 
        "lydian", 
        "mixolydian", 
        "locrian",
        "harmonic minor",
        "melodic minor",
        "whole tone",
        "major pentatonic",
        "minor pentatonic",
        "blues",
        "chromatic"
      }
      ChordEngine.set_scale(params:get("scale_root"), scale_names[value])
      screen_dirty = true
    end
  }
  
  params:add_separator("MIDI OUTPUT")
  
  -- MIDI Device
  params:add{
    type = "number",
    id = "midi_device",
    name = "MIDI Device",
    min = 1,
    max = 16,
    default = 1,
    action = function(value)
      MidiCrowOutput.set_midi_device(value)
      screen_dirty = true
    end
  }
  
  -- MIDI Channel
  params:add{
    type = "number",
    id = "midi_channel",
    name = "MIDI Channel",
    min = 1,
    max = 16,
    default = 1,
    action = function(value)
      MidiCrowOutput.set_midi_channel(value)
      screen_dirty = true
    end
  }
  
  -- MIDI Velocity Scale
  params:add{
    type = "number",
    id = "midi_velocity",
    name = "MIDI Velocity",
    min = 1,
    max = 127,
    default = 100,
    action = function(value)
      MidiCrowOutput.set_velocity_scale(value)
      screen_dirty = true
    end
  }
  
  params:add_separator("CROW OUTPUT")
  
  -- Crow Enable
  params:add{
    type = "option",
    id = "crow_enable",
    name = "Crow Enable",
    options = {"Off", "On"},
    default = 2,
    action = function(value)
      MidiCrowOutput.set_crow_enabled(value == 2)
      screen_dirty = true
    end
  }
  
  -- Crow Note Mode (which note from chord to send)
  params:add{
    type = "option",
    id = "crow_note_mode",
    name = "Crow Note Mode",
    options = {"Root", "Highest", "Lowest", "Last Triggered"},
    default = 1,
    action = function(value)
      MidiCrowOutput.set_crow_note_mode(value)
      screen_dirty = true
    end
  }
  
  -- Crow Gate Length
  params:add{
    type = "control",
    id = "crow_gate_length",
    name = "Crow Gate Length",
    controlspec = controlspec.new(0.01, 2.0, "lin", 0.01, 0.1, "s"),
    action = function(value)
      MidiCrowOutput.set_crow_gate_length(value)
      screen_dirty = true
    end
  }
  
  -- Crow Velocity CV
  params:add{
    type = "option",
    id = "crow_velocity_cv",
    name = "Crow Out 3",
    options = {"Velocity CV", "Envelope", "Off"},
    default = 1,
    action = function(value)
      MidiCrowOutput.set_crow_out3_mode(value)
      screen_dirty = true
    end
  }
  
  -- Crow Out 4 Mode
  params:add{
    type = "option",
    id = "crow_out4_mode",
    name = "Crow Out 4",
    options = {"Trigger", "Clock", "Off"},
    default = 1,
    action = function(value)
      MidiCrowOutput.set_crow_out4_mode(value)
      screen_dirty = true
    end
  }
  
  print("Parameters initialized")
end

-----------------------------------
-- NORNS CONTROLS
-----------------------------------

function key(n, z)
  if not initialized then return end
  
  key_pressed[n] = (z == 1)
  
  if z == 1 then
    if n == 2 then
      -- K2: Play/Stop
      if GenerativeEngine.is_playing() then
        GenerativeEngine.stop()
        GridController.update_playing_state(false)
      else
        GenerativeEngine.play()
        GridController.update_playing_state(true)
      end
      
    elseif n == 3 then
      -- K3: Panic (stop all notes immediately)
      MidiCrowOutput.panic()
      print("PANIC: All notes stopped")
    end
    
    screen_dirty = true
  end
end

function enc(n, delta)
  if not initialized then return end
  
  if n == 1 then
    -- E1: Change tempo
    local current_tempo = GenerativeEngine.get_tempo()
    local new_tempo = util.clamp(current_tempo + delta, 40, 300)
    GenerativeEngine.set_tempo(new_tempo)
    if params:lookup_param("tempo") then
      params:set("tempo", new_tempo)
    end
    
  elseif n == 2 then
    -- E2: Change probability
    local current_prob = GenerativeEngine.get_probability()
    local new_prob = util.clamp(current_prob + delta, 0, 100)
    GenerativeEngine.set_probability(new_prob)
    if params:lookup_param("probability") then
      params:set("probability", new_prob)
    end
    
  elseif n == 3 then
    -- E3: Change MIDI channel
    local current_ch = params:get("midi_channel")
    local new_ch = util.clamp(current_ch + delta, 1, 16)
    params:set("midi_channel", new_ch)
  end
  
  screen_dirty = true
end

-----------------------------------
-- SCREEN DRAWING
-----------------------------------

function redraw()
  if not initialized then return end
  
  screen.clear()
  
  -- Header
  screen.level(15)
  screen.move(0, 10)
  screen.text("NEXUS v1.1")
  
  -- Current chord
  local current_chord = GenerativeEngine.get_current_chord()
  local chord_name = ChordEngine.get_chord_name(current_chord)
  local chord_numeral = ChordEngine.get_chord_numeral(current_chord)
  
  screen.level(15)
  screen.move(0, 25)
  screen.text("Chord: " .. chord_numeral)
  
  screen.level(10)
  screen.move(0, 35)
  screen.text(chord_name)
  
  -- Check for pending chord
  local pending = GenerativeEngine.get_pending_chord()
  if pending then
    screen.level(8)
    screen.move(0, 45)
    local pending_name = ChordEngine.get_chord_numeral(pending)
    screen.text("Next: " .. pending_name)
  end
  
  -- Transport state
  screen.level(10)
  screen.move(75, 10)
  if GenerativeEngine.is_playing() then
    screen.text("▶ Playing")
  else
    screen.text("■ Stopped")
  end
  
  -- Sequencer states
  screen.level(8)
  screen.move(75, 22)
  local seq_status = {}
  if GenerativeEngine.get_sequencer_enabled() then table.insert(seq_status, "SEQ") end
  if GenerativeEngine.get_bass_seq_enabled() then table.insert(seq_status, "BASS") end
  if GenerativeEngine.get_sub_bass_seq_enabled() then table.insert(seq_status, "SUB") end
  if #seq_status > 0 then
    screen.text(table.concat(seq_status, " "))
  end
  
  -- Output status
  screen.level(8)
  screen.move(75, 35)
  screen.text("MIDI Ch:" .. params:get("midi_channel"))
  
  if params:get("crow_enable") == 2 then
    screen.move(75, 45)
    screen.text("Crow: ON")
  end
  
  -- Parameters
  screen.level(8)
  screen.move(0, 55)
  screen.text("Tempo: " .. GenerativeEngine.get_tempo() .. " BPM")
  
  screen.move(0, 64)
  screen.text("Prob: " .. GenerativeEngine.get_probability() .. "%")
  
  -- Active notes indicator
  local active = MidiCrowOutput.get_active_notes()
  screen.move(75, 55)
  screen.text("Notes: " .. active)
  
  screen.update()
end

-----------------------------------
-- CLEANUP
-----------------------------------

function cleanup()
  print("Nexus: Cleanup")
  redraw_metro:stop()
  GridController.cleanup()
  GenerativeEngine.cleanup()
  MidiCrowOutput.cleanup()
  ChordEngine.cleanup()
end
