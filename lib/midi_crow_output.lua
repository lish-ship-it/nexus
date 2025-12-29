-- Nexus - MIDI + Crow Output Module
-- Handles all note output via MIDI and Crow CV/Gate

local MidiCrowOutput = {}

-- MIDI state
local midi_device = nil
local midi_device_id = 1
local midi_channel = 1
local velocity_scale = 100

-- Crow state
local crow_enabled = true
local crow_note_mode = 1  -- 1=Root, 2=Highest, 3=Lowest, 4=Last Triggered
local crow_gate_length = 0.1
local crow_out3_mode = 1  -- 1=Velocity CV, 2=Envelope, 3=Off
local crow_out4_mode = 1  -- 1=Trigger, 2=Clock, 3=Off

-- Active notes tracking
local active_notes = {}  -- Map: voice_id -> {midi_note, velocity}
local voice_counter = 0
local last_triggered_note = 60

-----------------------------------
-- INITIALIZATION
-----------------------------------

function MidiCrowOutput.init()
  print("MidiCrowOutput: Initializing...")
  
  -- Connect to MIDI device
  midi_device = midi.connect(midi_device_id)
  if midi_device then
    print("MidiCrowOutput: MIDI device " .. midi_device_id .. " connected")
  else
    print("MidiCrowOutput: No MIDI device found")
  end
  
  -- Initialize Crow
  if crow then
    -- Output 1: V/Oct (pitch)
    crow.output[1].slew = 0.01
    
    -- Output 2: Gate
    crow.output[2].slew = 0
    crow.output[2].volts = 0
    
    -- Output 3: Velocity CV or Envelope
    crow.output[3].slew = 0.01
    crow.output[3].volts = 0
    
    -- Output 4: Trigger or Clock
    crow.output[4].slew = 0
    crow.output[4].volts = 0
    
    print("MidiCrowOutput: Crow initialized")
    print("  Out 1: V/Oct (pitch)")
    print("  Out 2: Gate")
    print("  Out 3: Velocity CV / Envelope")
    print("  Out 4: Trigger / Clock")
  else
    print("MidiCrowOutput: Crow not available")
  end
  
  print("MidiCrowOutput: Ready!")
end

-----------------------------------
-- NOTE TRIGGERING
-----------------------------------

-- Trigger a note (called by GenerativeEngine)
-- Returns a voice_id for tracking
function MidiCrowOutput.trigger_note(midi_note, velocity)
  velocity = velocity or 100
  
  -- Scale velocity
  local scaled_velocity = math.floor((velocity / 127) * velocity_scale)
  scaled_velocity = util.clamp(scaled_velocity, 1, 127)
  
  -- Generate voice ID
  voice_counter = voice_counter + 1
  local voice_id = voice_counter
  
  -- Store active note
  active_notes[voice_id] = {
    midi_note = midi_note,
    velocity = scaled_velocity
  }
  
  -- Track last triggered note for Crow
  last_triggered_note = midi_note
  
  -- Send MIDI note on
  if midi_device then
    midi_device:note_on(midi_note, scaled_velocity, midi_channel)
  end
  
  -- Send to Crow
  if crow_enabled and crow then
    MidiCrowOutput.update_crow(midi_note, scaled_velocity, true)
  end
  
  return voice_id
end

-- Release a note by voice_id
function MidiCrowOutput.release_note(voice_id)
  local note_data = active_notes[voice_id]
  
  if note_data then
    -- Send MIDI note off
    if midi_device then
      midi_device:note_off(note_data.midi_note, 0, midi_channel)
    end
    
    -- Remove from active notes
    active_notes[voice_id] = nil
    
    -- Update Crow gate if no notes remain
    if crow_enabled and crow then
      local remaining = MidiCrowOutput.get_active_notes()
      if remaining == 0 then
        crow.output[2].volts = 0  -- Gate off
      end
    end
  end
end

-- Release all notes
function MidiCrowOutput.release_all()
  for voice_id, note_data in pairs(active_notes) do
    if midi_device then
      midi_device:note_off(note_data.midi_note, 0, midi_channel)
    end
  end
  
  active_notes = {}
  
  -- Crow gate off
  if crow and crow_enabled then
    crow.output[2].volts = 0
  end
end

-- Panic - stop all notes immediately
function MidiCrowOutput.panic()
  -- Send all notes off on all channels
  if midi_device then
    for ch = 1, 16 do
      midi_device:cc(123, 0, ch)  -- All notes off
      midi_device:cc(120, 0, ch)  -- All sound off
    end
  end
  
  active_notes = {}
  
  -- Crow gate off
  if crow and crow_enabled then
    crow.output[2].volts = 0
    crow.output[3].volts = 0
    crow.output[4].volts = 0
  end
  
  print("MidiCrowOutput: PANIC - All notes off")
end

-----------------------------------
-- CROW OUTPUT
-----------------------------------

function MidiCrowOutput.update_crow(midi_note, velocity, gate_on)
  if not crow then return end
  
  -- Determine which note to send based on mode
  local note_to_send = midi_note
  
  if crow_note_mode == 1 then
    -- Root: use the note as-is (first note of chord typically)
    note_to_send = midi_note
  elseif crow_note_mode == 2 then
    -- Highest: find highest active note
    note_to_send = MidiCrowOutput.get_highest_note() or midi_note
  elseif crow_note_mode == 3 then
    -- Lowest: find lowest active note
    note_to_send = MidiCrowOutput.get_lowest_note() or midi_note
  elseif crow_note_mode == 4 then
    -- Last triggered
    note_to_send = last_triggered_note
  end
  
  -- Output 1: V/Oct (1V per octave, C4 = 0V)
  local volts = (note_to_send - 60) / 12
  crow.output[1].volts = volts
  
  -- Output 2: Gate
  if gate_on then
    crow.output[2].volts = 5
  end
  
  -- Output 3: Velocity CV or Envelope
  if crow_out3_mode == 1 then
    -- Velocity CV (0-5V)
    local vel_volts = (velocity / 127) * 5
    crow.output[3].volts = vel_volts
  elseif crow_out3_mode == 2 then
    -- Simple AR envelope
    crow.output[3].action = "ar(" .. crow_gate_length .. ", " .. (crow_gate_length * 2) .. ", 5)"
    crow.output[3]()
  end
  
  -- Output 4: Trigger or Clock
  if crow_out4_mode == 1 then
    -- Trigger pulse
    crow.output[4].action = "pulse(" .. crow_gate_length .. ", 5, 1)"
    crow.output[4]()
  end
end

-- Get highest active note
function MidiCrowOutput.get_highest_note()
  local highest = nil
  for _, note_data in pairs(active_notes) do
    if highest == nil or note_data.midi_note > highest then
      highest = note_data.midi_note
    end
  end
  return highest
end

-- Get lowest active note
function MidiCrowOutput.get_lowest_note()
  local lowest = nil
  for _, note_data in pairs(active_notes) do
    if lowest == nil or note_data.midi_note < lowest then
      lowest = note_data.midi_note
    end
  end
  return lowest
end

-----------------------------------
-- CLOCK OUTPUT (for Crow out 4)
-----------------------------------

function MidiCrowOutput.send_clock_pulse()
  if crow and crow_enabled and crow_out4_mode == 2 then
    crow.output[4].action = "pulse(0.01, 5, 1)"
    crow.output[4]()
  end
end

-----------------------------------
-- PARAMETER SETTERS
-----------------------------------

function MidiCrowOutput.set_midi_device(device_id)
  midi_device_id = device_id
  midi_device = midi.connect(device_id)
  print("MidiCrowOutput: MIDI device set to " .. device_id)
end

function MidiCrowOutput.set_midi_channel(channel)
  midi_channel = util.clamp(channel, 1, 16)
  print("MidiCrowOutput: MIDI channel set to " .. midi_channel)
end

function MidiCrowOutput.set_velocity_scale(vel)
  velocity_scale = util.clamp(vel, 1, 127)
end

function MidiCrowOutput.set_crow_enabled(enabled)
  crow_enabled = enabled
  if not enabled and crow then
    -- Turn off all Crow outputs
    for i = 1, 4 do
      crow.output[i].volts = 0
    end
  end
  print("MidiCrowOutput: Crow " .. (enabled and "enabled" or "disabled"))
end

function MidiCrowOutput.set_crow_note_mode(mode)
  crow_note_mode = mode
  local mode_names = {"Root", "Highest", "Lowest", "Last Triggered"}
  print("MidiCrowOutput: Crow note mode = " .. mode_names[mode])
end

function MidiCrowOutput.set_crow_gate_length(length)
  crow_gate_length = length
end

function MidiCrowOutput.set_crow_out3_mode(mode)
  crow_out3_mode = mode
  local mode_names = {"Velocity CV", "Envelope", "Off"}
  print("MidiCrowOutput: Crow out 3 = " .. mode_names[mode])
end

function MidiCrowOutput.set_crow_out4_mode(mode)
  crow_out4_mode = mode
  local mode_names = {"Trigger", "Clock", "Off"}
  print("MidiCrowOutput: Crow out 4 = " .. mode_names[mode])
end

-----------------------------------
-- GETTERS (for compatibility with EngineInterface API)
-----------------------------------

function MidiCrowOutput.get_active_notes()
  local count = 0
  for _ in pairs(active_notes) do
    count = count + 1
  end
  return count
end

-- Alias for compatibility
function MidiCrowOutput.get_active_voices()
  return MidiCrowOutput.get_active_notes()
end

-- Dummy functions for compatibility with GenerativeEngine
function MidiCrowOutput.set_attack(value) end
function MidiCrowOutput.set_release(value) end
function MidiCrowOutput.get_mod1() return 0 end
function MidiCrowOutput.set_mod1(value) end

-----------------------------------
-- CLEANUP
-----------------------------------

function MidiCrowOutput.cleanup()
  MidiCrowOutput.panic()
  print("MidiCrowOutput: Cleanup")
end

return MidiCrowOutput
