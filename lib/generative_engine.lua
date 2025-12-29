-- Nexus - Generative Engine Component
-- Probabilistic note retriggering on clock beats
-- With bass and sub-bass sequencers

local GenerativeEngine = {}

-- Component references (set during init)
local OutputInterface = nil  -- MidiCrowOutput (or any engine interface)
local ChordEngine = nil
local GridController = nil

-- Generative state
local gen_state = {
  playing = false,
  tempo = 80,  -- BPM (slower default)
  probability = 25,  -- % chance per note per beat (lower for more space)
  
  current_chord_slot = 1,  -- Active chord (1-15)
  pending_chord_slot = nil,  -- Queued chord change (waits for next beat)
  
  active_note_voices = {},  -- Map: midi_note -> voice_id
  
  sequencer_enabled = false,  -- Random chord sequencer on/off
  sequencer_counter = 0,      -- Count whole notes for sequencer
  
  bass_seq_enabled = false,   -- Bass note on chord changes (-1 octave)
  bass_voice_id = nil,        -- Current bass note voice
  
  sub_bass_seq_enabled = false,  -- Sub-bass note on chord changes (-2 octaves)
  sub_bass_voice_id = nil,       -- Current sub-bass note voice
  
  clock_id = nil  -- Clock routine ID
}

-----------------------------------
-- INITIALIZATION
-----------------------------------

function GenerativeEngine.init(output_interface, chord_engine, grid_controller, unused)
  print("GenerativeEngine: Initializing...")
  
  -- Store component references
  OutputInterface = output_interface
  ChordEngine = chord_engine
  GridController = grid_controller
  -- Fourth parameter is ignored
  
  print("GenerativeEngine: Ready!")
end

-----------------------------------
-- PLAYBACK CONTROL
-----------------------------------

function GenerativeEngine.play()
  if gen_state.playing then return end
  
  gen_state.playing = true
  clock.tempo = gen_state.tempo / 60
  print("GenerativeEngine: Play (Tempo: " .. gen_state.tempo .. " BPM, Probability: " .. gen_state.probability .. "%)")
  
  -- Start clock (every whole note / 4 beats)
  gen_state.clock_id = clock.run(function()
    while true do
      clock.sync(1)  -- Every whole note (4 quarter notes)
      
      if gen_state.playing then
        GenerativeEngine.on_beat()
      end
    end
  end)
end

function GenerativeEngine.stop()
  gen_state.playing = false
  
  if gen_state.clock_id then
    clock.cancel(gen_state.clock_id)
    gen_state.clock_id = nil
  end
  
  -- Release all playing notes
  if OutputInterface then
    OutputInterface.release_all()
  end
  gen_state.active_note_voices = {}
  gen_state.bass_voice_id = nil
  gen_state.sub_bass_voice_id = nil
  
  print("GenerativeEngine: Stop")
end

function GenerativeEngine.is_playing()
  return gen_state.playing
end

-----------------------------------
-- BEAT HANDLER (Core Logic)
-----------------------------------

function GenerativeEngine.on_beat()
  -- Handle sequencer (every 4 whole notes = 16 beats)
  if gen_state.sequencer_enabled then
    gen_state.sequencer_counter = gen_state.sequencer_counter + 1
    
    if gen_state.sequencer_counter >= 4 then
      -- Pick random chord from 1-15
      local random_chord = math.random(1, 15)
      gen_state.pending_chord_slot = random_chord
      gen_state.sequencer_counter = 0
      print("GenerativeEngine: Sequencer picked chord " .. random_chord)
    end
  end
  
  -- Handle pending chord change
  local chord_changed = false
  if gen_state.pending_chord_slot then
    gen_state.current_chord_slot = gen_state.pending_chord_slot
    gen_state.pending_chord_slot = nil
    chord_changed = true
    print("GenerativeEngine: Chord changed to slot " .. gen_state.current_chord_slot)
  end
  
  -- Get current chord notes
  local chord_notes = ChordEngine.get_chord(gen_state.current_chord_slot)
  
  if #chord_notes == 0 then
    print("GenerativeEngine: Warning - no notes in chord slot " .. gen_state.current_chord_slot)
    return
  end
  
  -- Send clock pulse to Crow (if available)
  if OutputInterface and OutputInterface.send_clock_pulse then
    OutputInterface.send_clock_pulse()
  end
  
  -- Trigger bass note on chord change (if bass sequencer enabled)
  if gen_state.bass_seq_enabled and chord_changed then
    -- Release previous bass note if still playing
    if gen_state.bass_voice_id then
      OutputInterface.release_note(gen_state.bass_voice_id)
      gen_state.bass_voice_id = nil
    end
    
    -- Get root note (first note in chord) and drop one octave
    local bass_note = chord_notes[1] - 12
    
    -- Trigger bass note with high velocity
    local bass_voice = OutputInterface.trigger_note(bass_note, 110)
    gen_state.bass_voice_id = bass_voice
    
    -- Notify grid controller
    if GridController then
      GridController.note_on(bass_note, 110)
    end
    
    -- Schedule bass release (2x longer than regular notes)
    clock.run(function()
      local hold_beats = math.random(4, 10)  -- 4-10 beats
      clock.sync(hold_beats / 4)
      
      if gen_state.bass_voice_id == bass_voice then
        OutputInterface.release_note(bass_voice)
        gen_state.bass_voice_id = nil
      end
    end)
  end
  
  -- Trigger sub-bass note on chord change (if sub-bass sequencer enabled)
  if gen_state.sub_bass_seq_enabled and chord_changed then
    -- Release previous sub-bass note if still playing
    if gen_state.sub_bass_voice_id then
      OutputInterface.release_note(gen_state.sub_bass_voice_id)
      gen_state.sub_bass_voice_id = nil
    end
    
    -- Get root note (first note in chord) and drop TWO octaves
    local sub_bass_note = chord_notes[1] - 24
    
    -- Trigger sub-bass note with very high velocity
    local sub_bass_voice = OutputInterface.trigger_note(sub_bass_note, 120)
    gen_state.sub_bass_voice_id = sub_bass_voice
    
    -- Notify grid controller
    if GridController then
      GridController.note_on(sub_bass_note, 120)
    end
    
    -- Schedule sub-bass release (3x longer than regular notes)
    clock.run(function()
      local hold_beats = math.random(6, 12)  -- 6-12 beats
      clock.sync(hold_beats / 4)
      
      if gen_state.sub_bass_voice_id == sub_bass_voice then
        OutputInterface.release_note(sub_bass_voice)
        gen_state.sub_bass_voice_id = nil
      end
    end)
  end
  
  -- Stagger note triggers evenly across the trigger window
  local num_notes = #chord_notes
  local stagger_time = 3.5 / num_notes  -- Spread across 3.5 beats
  
  -- For each note in chord, roll probability with staggered timing
  for i, midi_note in ipairs(chord_notes) do
    local roll = math.random(0, 100)
    
    if roll < gen_state.probability then
      -- Schedule this note trigger with even stagger
      local delay = (i - 1) * stagger_time + math.random() * 0.1  -- Small jitter
      
      clock.run(function()
        clock.sleep(delay)
        
        -- If this note is already playing, release it first
        if gen_state.active_note_voices[midi_note] then
          OutputInterface.release_note(gen_state.active_note_voices[midi_note])
        end
        
        -- Trigger new note with random velocity variation
        local velocity = math.random(70, 110)
        local voice_id = OutputInterface.trigger_note(midi_note, velocity)
        gen_state.active_note_voices[midi_note] = voice_id
        
        -- Notify grid controller for visualization
        if GridController then
          GridController.note_on(midi_note, velocity)
        end
        
        -- Schedule release
        clock.run(function()
          -- Hold note for 2-5 beats
          local hold_beats = math.random(2, 5)
          clock.sync(hold_beats / 4)
          
          if gen_state.active_note_voices[midi_note] == voice_id then
            OutputInterface.release_note(voice_id)
            gen_state.active_note_voices[midi_note] = nil
          end
        end)
      end)
    end
  end
end

-----------------------------------
-- CHORD SELECTION
-----------------------------------

-- Change chord (queued, takes effect on next beat)
function GenerativeEngine.set_chord(chord_slot)
  if chord_slot < 1 or chord_slot > 15 then
    print("GenerativeEngine: Invalid chord slot " .. chord_slot)
    return
  end
  
  -- Manual chord change resets sequencer counter
  if gen_state.sequencer_enabled then
    gen_state.sequencer_counter = 0
  end
  
  gen_state.pending_chord_slot = chord_slot
  print("GenerativeEngine: Chord " .. chord_slot .. " queued (changes next beat)")
end

-- Get current chord slot
function GenerativeEngine.get_current_chord()
  return gen_state.current_chord_slot
end

-- Get pending chord slot
function GenerativeEngine.get_pending_chord()
  return gen_state.pending_chord_slot
end

-----------------------------------
-- PARAMETER CONTROL
-----------------------------------

-- Set tempo (BPM)
function GenerativeEngine.set_tempo(bpm)
  gen_state.tempo = util.clamp(bpm, 40, 300)
  clock.tempo = gen_state.tempo / 60
  print("GenerativeEngine: Tempo = " .. gen_state.tempo .. " BPM")
end

function GenerativeEngine.get_tempo()
  return gen_state.tempo
end

-- Set probability (0-100%)
function GenerativeEngine.set_probability(percent)
  gen_state.probability = util.clamp(percent, 0, 100)
  print("GenerativeEngine: Probability = " .. gen_state.probability .. "%")
end

function GenerativeEngine.get_probability()
  return gen_state.probability
end

-- Enable/disable sequencer
function GenerativeEngine.set_sequencer(enabled)
  gen_state.sequencer_enabled = enabled
  if enabled then
    gen_state.sequencer_counter = 0
    print("GenerativeEngine: Sequencer ENABLED (random chord every 4 whole notes)")
  else
    print("GenerativeEngine: Sequencer DISABLED")
  end
end

function GenerativeEngine.get_sequencer_enabled()
  return gen_state.sequencer_enabled
end

-- Enable/disable bass sequencer
function GenerativeEngine.set_bass_sequencer(enabled)
  gen_state.bass_seq_enabled = enabled
  if enabled then
    print("GenerativeEngine: Bass Sequencer ENABLED (root -1 octave on chord changes)")
  else
    -- Release current bass note if disabling
    if gen_state.bass_voice_id and OutputInterface then
      OutputInterface.release_note(gen_state.bass_voice_id)
      gen_state.bass_voice_id = nil
    end
    print("GenerativeEngine: Bass Sequencer DISABLED")
  end
end

function GenerativeEngine.get_bass_seq_enabled()
  return gen_state.bass_seq_enabled
end

-- Enable/disable sub-bass sequencer
function GenerativeEngine.set_sub_bass_sequencer(enabled)
  gen_state.sub_bass_seq_enabled = enabled
  if enabled then
    print("GenerativeEngine: Sub-Bass Sequencer ENABLED (root -2 octaves on chord changes)")
  else
    -- Release current sub-bass note if disabling
    if gen_state.sub_bass_voice_id and OutputInterface then
      OutputInterface.release_note(gen_state.sub_bass_voice_id)
      gen_state.sub_bass_voice_id = nil
    end
    print("GenerativeEngine: Sub-Bass Sequencer DISABLED")
  end
end

function GenerativeEngine.get_sub_bass_seq_enabled()
  return gen_state.sub_bass_seq_enabled
end

-- Stub functions for compatibility
function GenerativeEngine.set_delay_rate_sequencer(enabled) end
function GenerativeEngine.get_delay_rate_seq_enabled() return false end

-----------------------------------
-- CLEANUP
-----------------------------------

function GenerativeEngine.cleanup()
  GenerativeEngine.stop()
  print("GenerativeEngine: Cleanup")
end

return GenerativeEngine
