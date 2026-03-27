-- midimix.lua: Akai MIDIMIX for Retrospects Playbox
-- Simplified for 4 synths: GM (bass), OB-6 (chord), Rev2 (lead), Drums
--
-- LAYOUT:
--   Faders 1-4: track velocity (bass, chord, lead, drums)
--   Fader 5-8: unused
--   Master: BPM (20-300)
--   Knob Row 2 col 8: drum LPF filter
--   Knob Row 1 col 8: delay send/mix
--   Knob Row 3 col 8: delay time
--   Mute 1-4: track mute toggle
--   Bank Left/Right: prev/next song
--   SEND ALL: PANIC

local MidiMix = {}
MidiMix.__index = MidiMix

local FADER_CC = {19, 23, 27, 31, 49, 53, 57, 61}
local MASTER_CC = 62
local KNOB_ROW1 = {16, 20, 24, 28, 46, 50, 54, 58}
local KNOB_ROW2 = {17, 21, 25, 29, 47, 51, 55, 59}
local KNOB_ROW3 = {18, 22, 26, 30, 48, 52, 56, 60}

local MUTE_NOTES = {1, 4, 7, 10, 13, 16, 19, 22}
local REC_NOTES  = {3, 6, 9, 12, 15, 18, 21, 24}
local BANK_LEFT_NOTE = 25
local BANK_RIGHT_NOTE = 26
local BANK_LEFT_CC = 25
local BANK_RIGHT_CC = 26
local SEND_ALL_NOTE = 27

function MidiMix.new()
  local self = setmetatable({}, MidiMix)

  self.midi_in = nil

  self.on_velocity = nil
  self.on_mute_toggle = nil
  self.on_prev_song = nil
  self.on_next_song = nil
  self.on_filter = nil
  self.on_delay_mix = nil
  self.on_delay_time = nil
  self.on_panic = nil
  self.on_bpm = nil

  self._fader_map = {}
  self._knob1_map = {}
  self._knob2_map = {}
  self._knob3_map = {}
  self._mute_map = {}

  for i = 1, 8 do
    self._fader_map[FADER_CC[i]] = i
    self._knob1_map[KNOB_ROW1[i]] = i
    self._knob2_map[KNOB_ROW2[i]] = i
    self._knob3_map[KNOB_ROW3[i]] = i
    self._mute_map[MUTE_NOTES[i]] = i
  end

  return self
end

function MidiMix:connect(device_num)
  self.midi_in = midi.connect(device_num)
  self.midi_in.event = function(data)
    self:handle_event(data)
  end
  print("MIDIMIX connected on device " .. device_num)
  self:leds_off()
end

function MidiMix:handle_event(data)
  local msg = midi.to_msg(data)

  if msg.type == "cc" then
    self:handle_cc(msg.cc, msg.val)
  elseif msg.type == "note_on" and msg.vel > 0 then
    self:handle_note(msg.note)
  elseif msg.type == "note_off" or (msg.type == "note_on" and msg.vel == 0) then
    if self._pending_led_update then
      self._pending_led_update = false
      self:update_leds()
    end
  end
end

function MidiMix:handle_cc(cc, val)
  -- Faders 1-4: track velocity (ignore 5-8)
  local fader_idx = self._fader_map[cc]
  if fader_idx and fader_idx <= 4 then
    local vel = val / 127
    if self.on_velocity then self.on_velocity(fader_idx, vel) end
    return
  end

  -- Knob Row 1 col 8: delay mix
  local k1 = self._knob1_map[cc]
  if k1 and k1 == 8 then
    local mix = val / 127
    if self.on_delay_mix then self.on_delay_mix(mix) end
    return
  end

  -- Knob Row 2 col 8: drum LPF
  local k2 = self._knob2_map[cc]
  if k2 and k2 == 8 then
    local freq = 60 * math.pow(20000/60, val/127)
    if val == 127 then freq = 20000 end
    if self.on_filter then self.on_filter(freq) end
    return
  end

  -- Knob Row 3 col 8: delay time
  local k3 = self._knob3_map[cc]
  if k3 and k3 == 8 then
    local time = 0.01 * math.pow(200, val / 127)
    if val == 0 then time = 0.01 end
    if self.on_delay_time then self.on_delay_time(time) end
    return
  end

  -- Master fader: BPM
  if cc == MASTER_CC then
    local bpm = math.floor(20 + (val / 127) * 280)
    if self.on_bpm then self.on_bpm(bpm) end
    return
  end

  -- Bank buttons
  if cc == BANK_LEFT_CC and val == 127 then
    if self.on_prev_song then self.on_prev_song() end
    return
  end
  if cc == BANK_RIGHT_CC and val == 127 then
    if self.on_next_song then self.on_next_song() end
    return
  end
end

function MidiMix:handle_note(note)
  -- Mute buttons 1-4 only
  local mute_idx = self._mute_map[note]
  if mute_idx and mute_idx <= 4 then
    if self.on_mute_toggle then self.on_mute_toggle(mute_idx) end
    self._pending_led_update = true
    return
  end

  if note == SEND_ALL_NOTE then
    if self.on_panic then self.on_panic() end
    return
  end

  if note == BANK_LEFT_NOTE then
    if self.on_prev_song then self.on_prev_song() end
    return
  end
  if note == BANK_RIGHT_NOTE then
    if self.on_next_song then self.on_next_song() end
    return
  end
end

function MidiMix:update_leds(tracks)
  if not self.midi_in then return end
  -- Only light tracks 1-4
  for i = 1, 4 do
    local note = MUTE_NOTES[i]
    local track = tracks and tracks[i]
    local vel = track and (track.velocity_scale or 1)
    if track and not track.mute and vel > 0 then
      self.midi_in:note_on(note, 127, 1)
    else
      self.midi_in:note_on(note, 0, 1)
    end
  end
  -- Turn off LEDs 5-8
  for i = 5, 8 do
    self.midi_in:note_on(MUTE_NOTES[i], 0, 1)
    self.midi_in:note_on(REC_NOTES[i], 0, 1)
  end
end

function MidiMix:leds_off()
  if not self.midi_in then return end
  for i = 1, 8 do
    self.midi_in:note_on(MUTE_NOTES[i], 0, 1)
    self.midi_in:note_off(MUTE_NOTES[i], 0, 1)
    self.midi_in:note_on(REC_NOTES[i], 0, 1)
    self.midi_in:note_off(REC_NOTES[i], 0, 1)
  end
end

return MidiMix
