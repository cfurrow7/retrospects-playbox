-- RETROSPECTS PLAYBOX
-- MIDI jukebox for The Retrospects live rig
-- Auto-assigns any MIDI file to: M32(bass/ch2), OB-6(mono lead/ch4), PRO-800(chords/ch11), Drums(internal)
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
local PATCHES_FILE = _path.data .. "retrospects-playbox/patches.txt"

local patches = {}  -- filename -> { pc, ob6_pc }
local redraw_clock = nil

function load_patches()
  patches = {}
  local f = io.open(PATCHES_FILE, "r")
  if not f then return end
  for line in f:lines() do
    -- Format: filename|pc|ob6_pc|drum_remap
    local parts = {}
    for part in (line .. "|"):gmatch("(.-)%s*|") do
      table.insert(parts, part)
    end
    if #parts >= 2 then
      local name = parts[1]
      local p = {
        pc = tonumber(parts[2]),
        ob6_pc = tonumber(parts[3]),
        drum_remap = {},
      }
      -- Parse drum remap: "0:1,4:2,6:-1"
      if parts[4] and parts[4] ~= "" then
        for pair in parts[4]:gmatch("([^,]+)") do
          local from, to = pair:match("(%d+):(%-?%d+)")
          if from then p.drum_remap[tonumber(from)] = tonumber(to) end
        end
      end
      patches[name] = p
    end
  end
  f:close()
end

function save_patches()
  os.execute("mkdir -p " .. _path.data .. "retrospects-playbox")
  local f = io.open(PATCHES_FILE, "w")
  if not f then return end
  for name, p in pairs(patches) do
    local p1 = p.pc or 0
    local p2 = p.ob6_pc and tostring(p.ob6_pc) or ""
    -- Encode drum remap
    local dr_parts = {}
    if p.drum_remap then
      for from, to in pairs(p.drum_remap) do
        table.insert(dr_parts, from .. ":" .. to)
      end
    end
    local dr = table.concat(dr_parts, ",")
    f:write(name .. "|" .. p1 .. "|" .. p2 .. "|" .. dr .. "\n")
  end
  f:close()
end

-- Save current song settings to disk
function save_song_pc(song)
  if not song then return end
  local name = song.file:match(".*/(.+)$") or song.file
  if not patches[name] then patches[name] = {} end
  patches[name].pc = song.pc
  patches[name].ob6_pc = song.ob6_pc
  save_patches()
end

function save_song_drums()
  local song = queue:current()
  if not song then return end
  local name = song.file:match(".*/(.+)$") or song.file
  if not patches[name] then patches[name] = {} end
  patches[name].drum_remap = {}
  for k, v in pairs(seq.drum_remap) do
    patches[name].drum_remap[k] = v
  end
  save_patches()
end

-- Apply saved patches to a song entry
function apply_saved_patches(song)
  if not song then return end
  local name = song.file:match(".*/(.+)$") or song.file
  local p = patches[name]
  if p then
    if not song.pc then song.pc = p.pc end
    if not song.ob6_pc then song.ob6_pc = p.ob6_pc end
    -- Apply drum remap
    seq.drum_remap = {}
    if p.drum_remap then
      for k, v in pairs(p.drum_remap) do
        seq.drum_remap[k] = v
      end
    end
  else
    seq.drum_remap = {}
  end
end

function init()
  os.execute("mkdir -p " .. MIDI_DIR)

  load_patches()

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

  state.on_save_pc = function()
    save_song_pc(queue:current())
  end

  state.on_save_drums = function()
    save_song_drums()
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
  print("  M32(ch2/bass) OB6(ch4/mono lead) P800(ch11/chords) DRM(internal)")
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
  -- Apply saved patches (won't overwrite playlist-specified PCs)
  apply_saved_patches(song)
  -- Send program changes if song has them assigned
  if seq.midi_out then
    if song.pc then
      seq.midi_out:program_change(song.pc, TrackAssign.CHORD_CH)
    end
    if song.ob6_pc then
      seq.midi_out:program_change(song.ob6_pc, TrackAssign.LEAD_CH)
    end
  end
  local ok, err = seq:load(song.file)
  if ok then
    apply_locked_settings()
    local pc_info = ""
    if song.pc then pc_info = pc_info .. " P8:" .. song.pc end
    if song.ob6_pc then pc_info = pc_info .. " OB:" .. song.ob6_pc end
    print("Loaded: " .. song.name .. " (" .. seq:get_bpm() .. " BPM, " .. seq:track_count() .. " tracks, " .. seq.assign_mode .. pc_info .. ")")
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
