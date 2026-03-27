-- RETROSPECTS PLAYBOX
-- MIDI jukebox for The Retrospects live rig
-- Auto-assigns any MIDI file to: GM(bass/ch2), OB-6(mono lead/ch4), Rev2(chords/ch11), Drums(internal)
-- Two modes: GREEDY (all tracks play) / SMART (best 3 + drums, rest muted)
--
-- E1: page select | E2/E3: context-sensitive
-- K2: play/stop | K3: restart
--
-- v2.0 @clf

engine.name = "RetroBox"

local Sequencer = include("retrospects-playbox/lib/sequencer")
local Queue = include("retrospects-playbox/lib/queue")
local UILib = include("retrospects-playbox/lib/ui")
local TrackAssign = include("retrospects-playbox/lib/track_assign")
local DrumKits = include("retrospects-playbox/lib/drum_kits")

local seq = Sequencer.new()
local queue = Queue.new()
local ui
local state = {}

local MIDI_DIR = _path.data .. "midi"
local PLAYLIST_DIR = _path.code .. "retrospects-playbox/playlists"

local redraw_clock = nil

function init()
  os.execute("mkdir -p " .. MIDI_DIR)

  state.kit = 1
  state.midi_dir = MIDI_DIR
  state.lock = false
  state.locked_settings = {}

  state.on_next = function()
    advance_queue()
  end

  state.on_load_current = function()
    load_current()
  end

  state.on_play_file = function(entry)
    queue:clear()
    queue:add(entry.display, entry.file)
    queue.position = 1
    load_current()
  end

  ui = UILib.new(seq, queue, state)
  ui:refresh_library(MIDI_DIR)

  seq:connect_midi(1)
  DrumKits.load(1)

  -- Sequencer callbacks
  seq.on_note = function(track_idx, note, vel, drum_voice)
    ui:note_flash(track_idx)
    if drum_voice then
      ui:drum_voice_flash(drum_voice)
    end
  end

  seq.on_end = function()
    advance_queue()
  end

  -- ===== PARAMS =====
  params:add_separator("RETROSPECTS PLAYBOX")

  params:add_number("midi_out_device", "MIDI Out Device", 1, 16, 1)
  params:set_action("midi_out_device", function(val)
    seq:connect_midi(val)
  end)

  params:add_option("assign_mode", "Assign Mode", {"Greedy", "Smart"}, 1)
  params:set_action("assign_mode", function(val)
    local mode = val == 1 and "greedy" or "smart"
    seq:reload_mode(mode)
  end)

  params:add_option("drum_kit", "Drum Kit", DrumKits.names(), 1)
  params:set_action("drum_kit", function(val)
    state.kit = val
    DrumKits.load(val)
  end)

  params:add_separator("DRUM FX")

  params:add_control("drum_lpf", "Drum LPF", controlspec.new(20, 20000, "exp", 0, 20000, "Hz"))
  params:set_action("drum_lpf", function(val) engine.lpf(val) end)

  params:add_control("drum_res", "Drum Resonance", controlspec.new(0.05, 1.0, "lin", 0, 0.3))
  params:set_action("drum_res", function(val) engine.res(val) end)

  params:add_control("delay_time", "Delay Time", controlspec.new(0.01, 2.0, "exp", 0, 0.3, "s"))
  params:set_action("delay_time", function(val) engine.delay_time(val) end)

  params:add_control("delay_feedback", "Delay Feedback", controlspec.new(0, 0.95, "lin", 0, 0.0))
  params:set_action("delay_feedback", function(val) engine.delay_feedback(val) end)

  params:add_control("delay_mix", "Delay Mix", controlspec.new(0, 1, "lin", 0, 0.0))
  params:set_action("delay_mix", function(val) engine.delay_mix(val) end)

  params:add_option("track_lock", "Track Lock", {"Off", "On"}, 1)
  params:set_action("track_lock", function(val)
    state.lock = (val == 2)
    if state.lock and #seq.tracks > 0 then
      save_track_settings()
    end
  end)

  params:add_separator("MIDI FILTER")

  params:add_option("quantize", "Quantize", {"Off", "1/4", "1/8", "1/16", "1/32"}, 3)
  params:set_action("quantize", function(val)
    local divs = {0, 4, 8, 16, 32}
    seq.quantize_div = divs[val]
    seq:rebuild_timeline()
  end)

  params:add_number("min_velocity", "Min Velocity", 0, 60, 25)
  params:set_action("min_velocity", function(val)
    seq.min_velocity = val
    seq:rebuild_timeline()
  end)

  params:add_option("min_duration", "Min Duration", {"Off", "25ms", "50ms", "100ms"}, 3)
  params:set_action("min_duration", function(val)
    local durs = {0, 0.025, 0.05, 0.1}
    seq.min_duration = durs[val]
    seq:rebuild_timeline()
  end)

  -- Load playlists
  check_playlists()

  -- Redraw clock (10 fps)
  redraw_clock = clock.run(function()
    while true do
      clock.sleep(1/10)
      ui:decay_flash()
      redraw()
    end
  end)

  print("RETROSPECTS PLAYBOX v2.0")
  print("  GM(ch2/bass) OB6(ch4/mono lead) REV2(ch11/chords) DRM(internal)")
  print("  Mode: " .. seq.assign_mode:upper())
  print("  MIDI dir: " .. MIDI_DIR)
  print("  Files: " .. #ui.lib_files)
end

function save_track_settings()
  state.locked_settings = {}
  for i, track in ipairs(seq.tracks) do
    local role = track.role
    if not state.locked_settings[role] then
      state.locked_settings[role] = {
        output = track.output,
        out_channels = {table.unpack(track.out_channels or {})},
        velocity_scale = track.velocity_scale,
        mute = track.mute,
      }
    end
    state.locked_settings[i] = {
      velocity_scale = track.velocity_scale,
      mute = track.mute,
    }
  end
end

function apply_locked_settings()
  if not state.lock or not next(state.locked_settings) then return end
  for i, track in ipairs(seq.tracks) do
    local role_settings = state.locked_settings[track.role]
    local idx_settings = state.locked_settings[i]
    if role_settings then
      track.output = role_settings.output
      track.out_channels = {table.unpack(role_settings.out_channels)}
    end
    if idx_settings then
      track.velocity_scale = idx_settings.velocity_scale
      track.mute = idx_settings.mute
    end
  end
end

function load_current()
  local song = queue:current()
  if not song then return end

  if state.lock and #seq.tracks > 0 then
    save_track_settings()
  end

  seq:stop()
  local ok, err = seq:load(song.file)
  if ok then
    apply_locked_settings()
    print("Loaded: " .. song.name .. " (" .. seq:get_bpm() .. " BPM, " .. seq:track_count() .. " tracks, " .. seq.assign_mode .. ")")
    seq:play()
  else
    print("Error: " .. (err or "unknown"))
  end
end

function advance_queue()
  local next_song = queue:advance()
  if next_song then
    load_current()
  else
    print("Queue finished")
  end
end

function check_playlists()
  local files = util.scandir(PLAYLIST_DIR)
  if files then
    for _, f in ipairs(files) do
      if f:match("%.txt$") then
        if queue:count() == 0 then
          local ok = queue:load_playlist(PLAYLIST_DIR .. "/" .. f, MIDI_DIR)
          if ok then
            print("Loaded playlist: " .. f .. " (" .. queue:count() .. " songs)")
          end
        end
      end
    end
  end
end

function redraw()
  if ui then ui:draw() end
end

function enc(n, d)
  if ui then
    ui:enc(n, d)
    redraw()
  end
end

function key(n, z)
  if ui then
    ui:key(n, z)
    redraw()
  end
end

function cleanup()
  if redraw_clock then clock.cancel(redraw_clock) end
  seq:stop()
end
