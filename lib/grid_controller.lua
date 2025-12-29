-- Nexus - Grid Controller Component
-- Row 1 = Chord selection (15 chords)
-- Row 2 = Chord notes (chromatic display)
-- Row 3 = Active note triggers (real-time)
-- Row 5 = Playable scale notes (lower octave)
-- Row 6 = Playable scale notes (upper octave)
-- Row 8 = Transport controls

local GridController = {}

-- Component references (set during init)
local GenerativeEngine = nil
local ChordEngine = nil
local OutputInterface = nil

-- LED brightness levels
local LED_OFF = 0
local LED_DIM = 4
local LED_MED = 8
local LED_BRIGHT = 10
local LED_MAX = 15

-- Grid state
local grid_state = {
  connected = false,
  playing = false,
  current_chord = 1,
  pending_chord = nil,
  sequencer_enabled = false,
  bass_seq_enabled = false,
  sub_bass_seq_enabled = false,
  
  -- Visualization state
  active_notes = {},             -- Map: midi_note -> {time, brightness}
  chord_notes = {},              -- Current chord notes for row 2
  held_scale_notes = {}          -- Map: "row:x" -> {voice_id, midi_note}
}

-- Grid device
local g = nil

-- LED buffer (16x8)
local led_buffer = {}
for y = 1, 8 do
  led_buffer[y] = {}
  for x = 1, 16 do
    led_buffer[y][x] = 0
  end
end

-- Dirty flag for LED refresh
local grid_dirty = true

-- Animation clock
local animation_clock = nil

-----------------------------------
-- INITIALIZATION
-----------------------------------

function GridController.init(generative_engine, chord_engine, output_interface, unused)
  print("GridController: Initializing...")
  
  -- Store component references
  GenerativeEngine = generative_engine
  ChordEngine = chord_engine
  OutputInterface = output_interface
  -- Fourth parameter is ignored
  
  -- Connect to Grid
  g = grid.connect()
  
  if g.device then
    grid_state.connected = true
    print("GridController: Grid connected - " .. g.device.name)
    
    -- Set up Grid key handler
    g.key = function(x, y, z)
      GridController.handle_key(x, y, z)
    end
    
    -- Start animation clock
    GridController.start_animation_clock()
    
    -- Initial LED update
    GridController.update_all_leds()
  else
    print("GridController: No Grid detected")
  end
  
  print("GridController: Ready!")
end

-----------------------------------
-- ANIMATION CLOCK
-----------------------------------

function GridController.start_animation_clock()
  if animation_clock then
    clock.cancel(animation_clock)
  end
  
  animation_clock = clock.run(function()
    while true do
      clock.sleep(1/30)  -- 30 fps
      
      -- Decay active notes
      local current_time = clock.get_beats()
      for note, data in pairs(grid_state.active_notes) do
        local age = current_time - data.time
        
        -- Fade over 2 beats
        if age > 2 then
          grid_state.active_notes[note] = nil
        else
          data.brightness = math.floor(LED_MAX * (1 - age / 2))
        end
      end
      
      grid_dirty = true
    end
  end)
end

-----------------------------------
-- GRID KEY HANDLER
-----------------------------------

function GridController.handle_key(x, y, z)
  -- Row 1: Chord selection (press only, 15 chords)
  if y == 1 and z == 1 and x <= 15 then
    GridController.handle_chord_select(x)
    
  -- Row 5: Playable scale notes - lower octave (press and release)
  elseif y == 5 then
    GridController.handle_scale_note(x, y, z, 0)  -- octave offset 0
    
  -- Row 6: Playable scale notes - upper octave (press and release)
  elseif y == 6 then
    GridController.handle_scale_note(x, y, z, 1)  -- octave offset 1
    
  -- Row 8: Transport controls (press only)
  elseif y == 8 and z == 1 then
    GridController.handle_transport(x)
  end
  
  grid_dirty = true
end

-----------------------------------
-- CHORD SELECT HANDLER (Row 1)
-----------------------------------

function GridController.handle_chord_select(x)
  if not GenerativeEngine then return end
  
  local chord_slot = x
  if chord_slot > 15 then return end  -- Only 15 chords
  
  -- Queue chord change
  GenerativeEngine.set_chord(chord_slot)
  grid_state.pending_chord = chord_slot
  
  -- Get chord name for feedback
  if ChordEngine then
    local chord_name = ChordEngine.get_chord_name(chord_slot)
    local numeral = ChordEngine.get_chord_numeral(chord_slot)
    print("GridController: Chord " .. numeral .. " (" .. chord_name .. ") queued")
  end
  
  grid_dirty = true
end

-----------------------------------
-- SCALE NOTE HANDLER (Rows 5 & 6)
-----------------------------------

function GridController.handle_scale_note(x, y, z, octave_offset)
  if not ChordEngine or not OutputInterface then return end
  
  -- Get current scale info
  local scale_info = ChordEngine.get_scale()
  local scale_intervals = scale_info.scale_intervals
  local root_note = scale_info.root_note
  
  if not scale_intervals or #scale_intervals == 0 then return end
  
  -- Map grid position to scale degree
  -- x=1 plays scale degree 1 (root), x=2 plays degree 2, etc.
  -- Wraps around for grids wider than scale length
  local scale_degree_index = ((x - 1) % #scale_intervals) + 1
  local position_octave = math.floor((x - 1) / #scale_intervals)
  
  -- Calculate MIDI note: root + base octave + scale interval + position octaves + row octave offset
  -- Row 5 (octave_offset=0): starts at root + 12 (one octave up)
  -- Row 6 (octave_offset=1): starts at root + 24 (two octaves up)
  local midi_note = root_note + 12 + scale_intervals[scale_degree_index] + (position_octave * 12) + (octave_offset * 12)
  
  -- Clamp to valid MIDI range
  if midi_note < 0 or midi_note > 127 then return end
  
  -- Create unique key for this grid position
  local key = y .. ":" .. x
  
  if z == 1 then
    -- Note on (slightly quieter than sequencer)
    local velocity = 80
    local voice_id = OutputInterface.trigger_note(midi_note, velocity)
    grid_state.held_scale_notes[key] = {voice_id = voice_id, midi_note = midi_note}
    
    -- Add to active notes for visualization
    GridController.note_on(midi_note, velocity)
    
  else
    -- Note off
    local held = grid_state.held_scale_notes[key]
    if held then
      OutputInterface.release_note(held.voice_id)
      grid_state.held_scale_notes[key] = nil
    end
  end
end

-----------------------------------
-- TRANSPORT HANDLER (Row 8)
-----------------------------------

function GridController.handle_transport(x)
  if not GenerativeEngine then return end
  
  if x == 1 then
    -- Play/Stop toggle
    if grid_state.playing then
      GenerativeEngine.stop()
      grid_state.playing = false
      print("GridController: Stop")
    else
      GenerativeEngine.play()
      grid_state.playing = true
      print("GridController: Play")
    end
    
  elseif x == 2 then
    -- Sequencer toggle
    grid_state.sequencer_enabled = not grid_state.sequencer_enabled
    GenerativeEngine.set_sequencer(grid_state.sequencer_enabled)
    
    -- Update params
    if params and params.lookup_param and params:lookup_param("sequencer") then
      params:set("sequencer", grid_state.sequencer_enabled and 2 or 1, true)
    end
    
    print("GridController: Sequencer " .. (grid_state.sequencer_enabled and "ON" or "OFF"))
    
  elseif x == 4 then
    -- Bass sequencer toggle
    grid_state.bass_seq_enabled = not grid_state.bass_seq_enabled
    GenerativeEngine.set_bass_sequencer(grid_state.bass_seq_enabled)
    
    -- Update params
    if params and params.lookup_param and params:lookup_param("bass_sequencer") then
      params:set("bass_sequencer", grid_state.bass_seq_enabled and 2 or 1, true)
    end
    
    print("GridController: Bass Sequencer " .. (grid_state.bass_seq_enabled and "ON" or "OFF"))
    
  elseif x == 5 then
    -- Sub-bass sequencer toggle
    grid_state.sub_bass_seq_enabled = not grid_state.sub_bass_seq_enabled
    GenerativeEngine.set_sub_bass_sequencer(grid_state.sub_bass_seq_enabled)
    
    -- Update params
    if params and params.lookup_param and params:lookup_param("sub_bass_sequencer") then
      params:set("sub_bass_sequencer", grid_state.sub_bass_seq_enabled and 2 or 1, true)
    end
    
    print("GridController: Sub-Bass Sequencer " .. (grid_state.sub_bass_seq_enabled and "ON" or "OFF"))
  end
  
  grid_dirty = true
end

-----------------------------------
-- LED UPDATE FUNCTIONS
-----------------------------------

function GridController.update_all_leds()
  if not grid_state.connected then return end
  
  -- Clear buffer
  for y = 1, 8 do
    for x = 1, 16 do
      led_buffer[y][x] = 0
    end
  end
  
  -- Update all active rows
  GridController.update_chord_row()
  GridController.update_chord_notes_row()      -- Row 2: Chord notes
  GridController.update_active_notes_row()     -- Row 3: Active notes
  -- Row 4: Available for future use
  GridController.update_scale_notes_row(5, 0)  -- Row 5: Lower octave
  GridController.update_scale_notes_row(6, 1)  -- Row 6: Upper octave
  GridController.update_transport_row()
  
  -- Send to Grid
  GridController.refresh_grid()
  grid_dirty = false
end

function GridController.update_chord_row()
  if not GenerativeEngine then return end
  
  -- Row 1: Show chord slots (15 chords)
  local current = GenerativeEngine.get_current_chord()
  local pending = GenerativeEngine.get_pending_chord()
  
  for x = 1, 15 do
    if pending and x == pending then
      led_buffer[1][x] = LED_BRIGHT  -- Queued chord (brighter)
    elseif x == current then
      led_buffer[1][x] = LED_MAX  -- Active chord (brightest)
    else
      led_buffer[1][x] = LED_DIM  -- Available chord
    end
  end
  -- Pad 16 is off (only 15 chords)
  led_buffer[1][16] = LED_OFF
end

-----------------------------------
-- ROW 2: CHORD NOTES (CHROMATIC)
-----------------------------------

function GridController.update_chord_notes_row()
  if not ChordEngine or not GenerativeEngine then return end
  
  -- Get current chord notes
  local current_chord = GenerativeEngine.get_current_chord()
  local chord_notes = ChordEngine.get_chord(current_chord)
  
  if #chord_notes == 0 then return end
  
  -- Create a set of chromatic positions (0-11 = C to B)
  local chromatic_map = {}
  for _, midi_note in ipairs(chord_notes) do
    local chroma = midi_note % 12  -- 0=C, 1=C#, 2=D, etc.
    chromatic_map[chroma] = true
  end
  
  -- Light up pads for notes in chord (wrapping every 12 pads)
  for x = 1, 16 do
    local chroma = (x - 1) % 12
    if chromatic_map[chroma] then
      led_buffer[2][x] = LED_BRIGHT
    else
      led_buffer[2][x] = LED_OFF
    end
  end
end

-----------------------------------
-- ROW 3: ACTIVE NOTE TRIGGERS
-----------------------------------

function GridController.update_active_notes_row()
  -- Show which notes are currently playing/recently triggered
  for midi_note, data in pairs(grid_state.active_notes) do
    local chroma = midi_note % 12
    
    -- Map to grid x position (chromatic, wrapping)
    for x = 1, 16 do
      if (x - 1) % 12 == chroma then
        -- Use the brightest value if multiple notes at same chroma
        led_buffer[3][x] = math.max(led_buffer[3][x], data.brightness)
      end
    end
  end
end

-----------------------------------
-- ROWS 5 & 6: PLAYABLE SCALE NOTES
-----------------------------------

function GridController.update_scale_notes_row(row, octave_offset)
  if not ChordEngine then return end
  
  -- Get current scale info
  local scale_info = ChordEngine.get_scale()
  local scale_intervals = scale_info.scale_intervals
  local root_note = scale_info.root_note
  
  if not scale_intervals or #scale_intervals == 0 then return end
  
  -- Light up scale notes
  for x = 1, 16 do
    local scale_degree_index = ((x - 1) % #scale_intervals) + 1
    local position_octave = math.floor((x - 1) / #scale_intervals)
    local midi_note = root_note + 12 + scale_intervals[scale_degree_index] + (position_octave * 12) + (octave_offset * 12)
    
    -- Create unique key for this grid position
    local key = row .. ":" .. x
    
    -- Check if this note is being held
    if grid_state.held_scale_notes[key] then
      led_buffer[row][x] = LED_MAX  -- Bright when held
    else
      -- Check if this note is in active_notes (triggered by sequencer or other row)
      if grid_state.active_notes[midi_note] then
        led_buffer[row][x] = grid_state.active_notes[midi_note].brightness
      else
        -- Highlight root notes brighter, other scale notes dimmer
        if scale_degree_index == 1 then
          led_buffer[row][x] = LED_MED  -- Root note slightly brighter
        else
          led_buffer[row][x] = LED_DIM  -- Other scale notes dim
        end
      end
    end
  end
end

-----------------------------------
-- ROW 8: TRANSPORT
-----------------------------------

function GridController.update_transport_row()
  -- Row 8: Transport controls
  
  -- Pad 1: Play/Stop
  led_buffer[8][1] = grid_state.playing and LED_MAX or LED_MED
  
  -- Pad 2: Sequencer on/off
  led_buffer[8][2] = grid_state.sequencer_enabled and LED_MAX or LED_DIM
  
  -- Pad 3: (available)
  led_buffer[8][3] = LED_OFF
  
  -- Pad 4: Bass sequencer on/off
  led_buffer[8][4] = grid_state.bass_seq_enabled and LED_MAX or LED_DIM
  
  -- Pad 5: Sub-bass sequencer on/off
  led_buffer[8][5] = grid_state.sub_bass_seq_enabled and LED_MAX or LED_DIM
  
  -- Pads 6-16: Available for future use
end

function GridController.refresh_grid()
  if not g or not grid_state.connected then return end
  
  -- Send entire LED buffer to Grid
  for y = 1, 8 do
    for x = 1, 16 do
      g:led(x, y, led_buffer[y][x])
    end
  end
  
  g:refresh()
end

-----------------------------------
-- EXTERNAL UPDATE FUNCTIONS
-----------------------------------

function GridController.update_current_chord(chord_slot)
  grid_state.current_chord = chord_slot
  grid_state.pending_chord = nil
  grid_dirty = true
end

function GridController.update_playing_state(playing)
  grid_state.playing = playing
  grid_dirty = true
end

function GridController.update_sequencer_state(enabled)
  grid_state.sequencer_enabled = enabled
  grid_dirty = true
end

function GridController.update_bass_seq_state(enabled)
  grid_state.bass_seq_enabled = enabled
  grid_dirty = true
end

function GridController.update_sub_bass_seq_state(enabled)
  grid_state.sub_bass_seq_enabled = enabled
  grid_dirty = true
end

-- Stub for compatibility
function GridController.update_delay_rate_seq_state(enabled) end
function GridController.update_delay_rate(rate_index) end

function GridController.set_generative_engine(gen_engine)
  GenerativeEngine = gen_engine
  print("GridController: GenerativeEngine reference updated")
end

-----------------------------------
-- NOTE VISUALIZATION API
-----------------------------------

-- Call this when a note is triggered
function GridController.note_on(midi_note, velocity)
  velocity = velocity or 100
  
  -- Add to active notes with full brightness
  grid_state.active_notes[midi_note] = {
    time = clock.get_beats(),
    brightness = LED_MAX
  }
  
  grid_dirty = true
end

-- Call this when a note is released (optional, decay handles it automatically)
function GridController.note_off(midi_note)
  -- We let the animation clock handle decay naturally
end

-----------------------------------
-- REFRESH LOOP
-----------------------------------

function GridController.redraw()
  if grid_dirty and grid_state.connected then
    GridController.update_all_leds()
  end
end

-----------------------------------
-- CLEANUP
-----------------------------------

function GridController.cleanup()
  -- Release any held scale notes
  for key, held in pairs(grid_state.held_scale_notes) do
    if OutputInterface and held.voice_id then
      OutputInterface.release_note(held.voice_id)
    end
  end
  grid_state.held_scale_notes = {}
  
  -- Stop animation clock
  if animation_clock then
    clock.cancel(animation_clock)
    animation_clock = nil
  end
  
  if g and grid_state.connected then
    -- Clear all LEDs
    g:all(0)
    g:refresh()
  end
  print("GridController: Cleanup")
end

return GridController
