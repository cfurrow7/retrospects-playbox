-- sequencer.lua: MIDI playback engine for Retrospects
-- Routes to GM(ch2), OB-6(ch4, mono), PRO-800(ch11, poly), Drums(internal)
-- OB-6 mono filter: latest note wins, OB-6 handles legato naturally

local MidiParser = include("retrospects-playbox/lib/midi_parser")
local TrackAssign = include("retrospects-playbox/lib/track_assign")

local Sequencer = {}
Sequencer.__index = Sequencer

function Sequencer.new()
  local self = setmetatable({}, Sequencer)

  self.midi_out = nil
  self.parsed = nil
  self.timeline = nil
  self.duration = 0

  self.playing = false
  self.clock_id = nil
  self.position = 1
  self.elapsed = 0

  self.tracks = {}

  self.original_bpm = 120
  self.bpm_override = nil

  -- Assignment mode: "greedy" or "smart"
  self.assign_mode = "greedy"

  -- MIDI filter settings
  self.quantize_div = 0
  self.min_velocity = 0
  self.min_duration = 0

  -- OB-6 mono state
  self.ob6_current = nil   -- the one note currently sounding
  self.ob6_held = {}       -- all notes with note-on still active (for release tracking)

  -- Callbacks
  self.on_note = nil
  self.on_end = nil
  self.on_progress = nil

  -- Active notes for cleanup
  self.active_notes = {}

  return self
end

function Sequencer:connect_midi(device_num)
  self.midi_out = midi.connect(device_num or 1)
end

function Sequencer:load(filepath)
  local parsed, err = MidiParser.parse(filepath)
  if not parsed then return false, err end

  self.parsed = parsed
  self.original_bpm = parsed.bpm

  self.tracks = TrackAssign.build_tracks(parsed.channels, self.assign_mode)
  self:rebuild_timeline()

  return true
end

-- Reload tracks with new mode (smart/greedy) without re-parsing
function Sequencer:reload_mode(mode)
  self.assign_mode = mode
  if not self.parsed then return end
  local was_playing = self.playing
  if was_playing then self:stop() end
  self.tracks = TrackAssign.build_tracks(self.parsed.channels, mode)
  self:rebuild_timeline()
  if was_playing then self:play() end
end

function Sequencer:rebuild_timeline()
  if not self.parsed then return end
  local bpm = self.bpm_override or self.original_bpm
  self.timeline, self.duration = MidiParser.to_timeline(self.parsed, bpm)
  self.timeline = MidiParser.filter_timeline(
    self.timeline, bpm,
    self.quantize_div, self.min_velocity, self.min_duration
  )
  self:build_note_bars()
  self.position = 1
  self.elapsed = 0
end

-- Build note bars (start/end pairs) for tracker display
function Sequencer:build_note_bars()
  self.note_bars = {}
  if not self.timeline then return end
  local open = {}  -- key -> index in note_bars
  for _, ev in ipairs(self.timeline) do
    local key = ev.channel .. ":" .. ev.note
    if ev.type == "note_on" and ev.velocity > 0 then
      local bar = { t1 = ev.time, t2 = ev.time + 0.1, ch = ev.channel, note = ev.note, vel = ev.velocity }
      table.insert(self.note_bars, bar)
      open[key] = #self.note_bars
    elseif ev.type == "note_off" or (ev.type == "note_on" and ev.velocity == 0) then
      if open[key] then
        self.note_bars[open[key]].t2 = ev.time
        open[key] = nil
      end
    end
  end
end

function Sequencer:get_bpm()
  return self.bpm_override or self.original_bpm
end

function Sequencer:set_bpm(bpm)
  local old_bpm = self.bpm_override or self.original_bpm
  if bpm then
    self.bpm_override = math.max(20, math.min(300, bpm))
  else
    self.bpm_override = nil
  end
  local new_bpm = self.bpm_override or self.original_bpm
  if not self.timeline or old_bpm == new_bpm then return end

  -- Scale all event times and duration by the BPM ratio
  local ratio = old_bpm / new_bpm
  for _, event in ipairs(self.timeline) do
    event.time = event.time * ratio
  end
  if self.note_bars then
    for _, bar in ipairs(self.note_bars) do
      bar.t1 = bar.t1 * ratio
      bar.t2 = bar.t2 * ratio
    end
  end
  self.duration = self.duration * ratio
  self.elapsed = self.elapsed * ratio
end

function Sequencer:play()
  if not self.timeline or #self.timeline == 0 then return end
  if self.playing then return end

  self.playing = true
  self.ob6_current = nil
  self.ob6_held = {}

  self.clock_id = clock.run(function()
    local start_time = util.time()
    local start_elapsed = self.elapsed

    while self.playing and self.position <= #self.timeline do
      local event = self.timeline[self.position]
      local target_time = event.time - start_elapsed

      local now = util.time() - start_time
      if target_time > now then
        clock.sleep(target_time - now)
      end

      if not self.playing then break end

      self:route_event(event)

      self.elapsed = start_elapsed + (util.time() - start_time)
      self.position = self.position + 1

      if self.on_progress then
        self.on_progress(self.elapsed, self.duration)
      end
    end

    if self.playing and self.position > #self.timeline then
      self.playing = false
      self:all_notes_off()
      if self.on_end then self.on_end() end
    end
  end)
end

function Sequencer:stop()
  self.playing = false
  if self.clock_id then
    clock.cancel(self.clock_id)
    self.clock_id = nil
  end
  self:all_notes_off()
  self.ob6_current = nil
  self.ob6_held = {}
end

function Sequencer:restart()
  self:stop()
  self.position = 1
  self.elapsed = 0
  self:play()
end

function Sequencer:track_for_channel(ch)
  for i, track in ipairs(self.tracks) do
    if track.source_ch == ch then
      return i, track
    end
  end
  return nil, nil
end

function Sequencer:route_event(event)
  local track_idx, track = self:track_for_channel(event.channel)
  if not track then return end
  if track.mute then return end
  if track.output == "off" then return end

  if track.output == "internal" then
    -- Internal drum engine
    if event.type == "note_on" and event.velocity > 0 then
      local voice = TrackAssign.map_drum_note(event.note)
      if voice then
        local vel = (event.velocity / 127) * (track.velocity_scale or 1.0)
        engine.trig_kit(voice, vel)
        if self.on_note then
          self.on_note(track_idx, event.note, event.velocity, voice)
        end
      end
    end
  elseif track.output == "midi" then
    if self.midi_out then
      local channels = track.out_channels or {1}
      local note = event.note + (track.octave or 0) * 12
      note = math.max(0, math.min(127, note))

      -- OB-6 mono filter: latest note wins
      if track.role == "lead" then
        self:route_mono_lead(event, track, track_idx, note)
      else
        -- Bass and chord: send everything, synths handle overflow
        self:route_poly(event, track, track_idx, note)
      end
    end
  end
end

-- OB-6 mono lead: strict mono, latest note wins
-- Norns enforces one note at a time so OB-6 never stacks notes
function Sequencer:route_mono_lead(event, track, track_idx, note)
  local ch = TrackAssign.LEAD_CH
  local scale = track.velocity_scale or 1.0

  if event.type == "note_on" and event.velocity > 0 then
    if scale <= 0.01 then return end
    local scaled_vel = math.floor(event.velocity * scale)
    scaled_vel = math.max(1, math.min(127, scaled_vel))

    -- Kill any currently sounding note before sending the new one
    if self.ob6_current then
      self.midi_out:note_off(self.ob6_current, 0, ch)
    end

    self.midi_out:note_on(note, scaled_vel, ch)
    self.ob6_current = note
    self.ob6_held[note] = true  -- track all held notes for proper release

    if self.on_note then
      self.on_note(track_idx, note, scaled_vel)
    end
  elseif event.type == "note_off" or (event.type == "note_on" and event.velocity == 0) then
    self.ob6_held[note] = nil
    if note == self.ob6_current then
      self.midi_out:note_off(note, 0, ch)
      self.ob6_current = nil
    end
    -- If other notes are still held, don't re-trigger (just let silence)
  end
end

-- Bass and chord: normal poly routing
function Sequencer:route_poly(event, track, track_idx, note)
  local channels = track.out_channels or {1}
  local scale = track.velocity_scale or 1.0

  if event.type == "note_on" and event.velocity > 0 then
    if scale <= 0.01 then return end
    local scaled_vel = math.floor(event.velocity * scale)
    scaled_vel = math.max(1, math.min(127, scaled_vel))
    for _, out_ch in ipairs(channels) do
      self.midi_out:note_on(note, scaled_vel, out_ch)
      -- Track active notes using channel*256+note key to avoid duplicates
      local key = out_ch * 256 + note
      self.active_notes[key] = true
    end
    if self.on_note then
      self.on_note(track_idx, note, scaled_vel)
    end
  elseif event.type == "note_off" or (event.type == "note_on" and event.velocity == 0) then
    for _, out_ch in ipairs(channels) do
      self.midi_out:note_off(note, 0, out_ch)
      local key = out_ch * 256 + note
      self.active_notes[key] = nil
    end
  end
end

function Sequencer:all_notes_off()
  if self.midi_out then
    -- Clear active poly notes
    for key, _ in pairs(self.active_notes) do
      local ch = math.floor(key / 256)
      local note = key % 256
      self.midi_out:note_off(note, 0, ch)
    end
    self.active_notes = {}
    -- Clear OB-6 mono note
    if self.ob6_current then
      self.midi_out:note_off(self.ob6_current, 0, TrackAssign.LEAD_CH)
      self.ob6_current = nil
    end
    self.ob6_held = {}
    -- Reset all Retrospects channels: sustain off, all notes off, all sound off
    for _, ch in ipairs({TrackAssign.BASS_CH, TrackAssign.LEAD_CH, TrackAssign.CHORD_CH}) do
      self.midi_out:cc(64, 0, ch)   -- sustain pedal off
      self.midi_out:cc(123, 0, ch)  -- all notes off
      self.midi_out:cc(120, 0, ch)  -- all sound off (kills tails immediately)
    end
  end
end

function Sequencer:toggle_mute(track_idx)
  local track = self.tracks[track_idx]
  if not track then return end
  track.mute = not track.mute
  if track.mute and track.output == "midi" and self.midi_out then
    for _, ch in ipairs(track.out_channels or {}) do
      self.midi_out:cc(123, 0, ch)
    end
  end
end

function Sequencer:reassign_channels()
  TrackAssign.reassign_channels(self.tracks)
end

function Sequencer:track_count()
  return #self.tracks
end

return Sequencer
