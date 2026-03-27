-- ui.lua: Screen drawing for Retrospects Playbox
-- 5 pages: Now Playing, Tracks, Drums, Queue, Library
-- Same layout as midi-playbox with Retrospects rig display

local UI = {}
UI.__index = UI

local TrackAssign = include("retrospects-playbox/lib/track_assign")

local PAGES = { "PLAY", "TRACKS", "DRUMS", "QUEUE", "LIBRARY" }
local KIT_NAMES = { "808", "909", "606" }
local DRUM_VOICE_NAMES = { "KICK", "SNRE", "CHH", "OHH", "CLAP", "LTOM", "HTOM", "CRSH" }

-- Rig display order
local RIG = {
  { role = "bass",  label = "GM" },
  { role = "lead",  label = "OB6" },
  { role = "chord", label = "REV2" },
  { role = "drum",  label = "DRM" },
}

function UI.new(sequencer, queue, state)
  local self = setmetatable({}, UI)
  self.seq = sequencer
  self.queue = queue
  self.state = state

  self.page = 1
  self.k1_held = false
  self.mute_cursor = 1

  -- Track setup
  self.track_cursor = 1
  self.track_scroll = 0
  self.track_field = 1  -- 1=role, 2=octave

  -- Drums page
  self.drum_cursor = 1
  self.drum_vol = 0.8
  self.filter_freq = 20000
  self.filter_res = 0.3
  self.random_amt = 0.0

  -- Library state
  self.lib_files = {}
  self.lib_scroll = 0
  self.lib_cursor = 1

  -- Queue state
  self.queue_cursor = 1
  self.queue_scroll = 0

  -- Note flash per track
  self.flash = {}
  self.drum_flash = { 0, 0, 0, 0, 0, 0, 0, 0 }

  -- Favorites
  self.favorites = {}
  self:load_favorites()

  -- Animation
  self.anim_t = 0
  self.pyramid_rot = 0
  self.energy = 0
  self.energy_peak = 0
  self.note_hits = 0

  return self
end

function UI:refresh_library(midi_dir)
  self.lib_files = {}
  self:scan_dir_recursive(midi_dir, midi_dir)
  table.sort(self.lib_files, function(a, b)
    return a.display < b.display
  end)
end

function UI:scan_dir_recursive(dir, base_dir)
  local entries = util.scandir(dir)
  if not entries then return end
  for _, entry in ipairs(entries) do
    if entry:match("/$") then
      local dirname = entry:sub(1, -2)
      self:scan_dir_recursive(dir .. "/" .. dirname, base_dir)
    elseif entry:match("%.mid$") or entry:match("%.midi$") or entry:match("%.MID$") then
      local full_path = dir .. "/" .. entry
      local rel = dir:sub(#base_dir + 2)
      local display = entry:match("(.+)%.[Mm][Ii][Dd][Ii]?$") or entry
      if rel and #rel > 0 then
        display = rel .. "/" .. display
      end
      table.insert(self.lib_files, { file = full_path, name = entry, display = display })
    end
  end
end

-- ===== FAVORITES =====

local FAVORITES_PATH = _path.data .. "retrospects-playbox/favorites.txt"

function UI:load_favorites()
  self.favorites = {}
  local f = io.open(FAVORITES_PATH, "r")
  if not f then return end
  for line in f:lines() do
    line = line:match("^%s*(.-)%s*$")
    if line ~= "" then
      self.favorites[line] = true
    end
  end
  f:close()
end

function UI:save_favorites()
  os.execute("mkdir -p " .. _path.data .. "retrospects-playbox")
  local f = io.open(FAVORITES_PATH, "w")
  if not f then return end
  for name, _ in pairs(self.favorites) do
    f:write(name .. "\n")
  end
  f:close()
end

function UI:toggle_favorite(display_name)
  if self.favorites[display_name] then
    self.favorites[display_name] = nil
  else
    self.favorites[display_name] = true
  end
  self:save_favorites()
end

function UI:is_favorite(display_name)
  return self.favorites[display_name] == true
end

function UI:note_flash(track_idx)
  self.flash[track_idx] = 4
  self.note_hits = self.note_hits + 1
end

function UI:drum_voice_flash(voice)
  if voice >= 0 and voice < 8 then
    self.drum_flash[voice + 1] = 4
  end
end

function UI:decay_flash()
  for k, v in pairs(self.flash) do
    if v > 0 then self.flash[k] = v - 1 end
  end
  for i = 1, 8 do
    if self.drum_flash[i] > 0 then self.drum_flash[i] = self.drum_flash[i] - 1 end
  end
  local target = math.min(1.0, self.note_hits * 0.15)
  if target > self.energy then
    self.energy = self.energy + (target - self.energy) * 0.6
  else
    self.energy = self.energy * 0.92
  end
  self.energy_peak = math.max(self.energy, self.energy_peak * 0.95)
  self.note_hits = 0
  self.anim_t = self.anim_t + 0.04 + self.energy * 0.2
  self.pyramid_rot = self.pyramid_rot + 0.015 + self.energy * 0.08
end

-- ===== EYE CANDY =====

function UI:draw_pyramid()
  local cx, cy = 118, 14
  local e = self.energy_peak
  local size = 5 + e * 4
  local r = self.pyramid_rot

  local ax, ay = cx, cy - size * 1.4
  local base = {}
  for i = 0, 3 do
    local angle = (i * math.pi / 2) + r
    local bx = math.cos(angle) * size
    local bz = math.sin(angle) * size
    base[i + 1] = { cx + bx, cy + bz * 0.4 }
  end

  screen.level(math.floor(2 + e * 6))
  for i = 1, 4 do
    local j = (i % 4) + 1
    screen.move(base[i][1], base[i][2])
    screen.line(base[j][1], base[j][2])
    screen.stroke()
    screen.move(base[i][1], base[i][2])
    screen.line(ax, ay)
    screen.stroke()
  end
end

function UI:draw_lissajous()
  local cx, cy = 108, 14
  local e = self.energy
  local ep = self.energy_peak
  local t = self.anim_t

  local rx = 4 + ep * 10
  local ry = 3 + ep * 7
  local points = 20 + math.floor(e * 40)
  screen.level(math.min(15, 1 + math.floor(e * 6)))

  local fx = 3 + e * 0.5
  local fy = 2 + e * 0.3

  for i = 0, points do
    local angle = (i / points) * math.pi * 2
    local x = cx + math.sin(angle * fx + t) * rx
    local y = cy + math.cos(angle * fy + t * 0.7) * ry
    screen.pixel(x, y)
    screen.fill()
  end

  if e > 0.3 then
    screen.level(math.floor(e * 8))
    local irx = rx * 0.5
    local iry = ry * 0.5
    for i = 0, 15 do
      local angle = (i / 15) * math.pi * 2
      local x = cx + math.sin(angle * 5 + t * 1.3) * irx
      local y = cy + math.cos(angle * 3 + t * 0.9) * iry
      screen.pixel(x, y)
      screen.fill()
    end
  end
end

-- ===== DRAWING =====

function UI:draw()
  screen.clear()
  screen.aa(0)
  screen.font_face(1)
  screen.font_size(8)

  -- Page header
  screen.level(3)
  screen.move(0, 6)
  screen.text(PAGES[self.page])

  -- Mode indicator
  local mode_label = self.seq.assign_mode == "smart" and "S" or "G"
  screen.level(6)
  screen.move(78, 6)
  screen.text(mode_label)

  -- Page dots
  for i = 1, 5 do
    screen.level(i == self.page and 15 or 2)
    screen.rect(88 + (i - 1) * 5, 1, 3, 3)
    screen.fill()
  end

  -- Mute overlay
  if self.k1_held and self.page ~= 4 and self.page ~= 5 then
    self:draw_mute_overlay()
    screen.update()
    return
  end

  if self.page == 1 then
    self:draw_play()
  elseif self.page == 2 then
    self:draw_tracks()
  elseif self.page == 3 then
    self:draw_drums()
  elseif self.page == 4 then
    self:draw_queue()
  elseif self.page == 5 then
    self:draw_library()
  end

  self:draw_lissajous()
  self:draw_pyramid()

  screen.update()
end

function UI:draw_mute_overlay()
  local tc = self.seq:track_count()
  if tc == 0 then
    screen.level(4)
    screen.move(64, 35)
    screen.text_center("No tracks loaded")
    return
  end

  screen.level(15)
  screen.move(64, 12)
  screen.text_center("MUTE SELECT")

  local visible = math.min(tc, 4)
  local scroll = math.max(0, self.mute_cursor - visible)

  for i = 1, visible do
    local idx = scroll + i
    if idx > tc then break end
    local track = self.seq.tracks[idx]
    local y = 14 + (i - 1) * 12
    local selected = (self.mute_cursor == idx)

    screen.level(selected and 15 or 5)
    screen.move(4, y + 8)
    local synth = TrackAssign.role_label(track.role)
    local label = synth .. " " .. track.name
    if #label > 16 then label = label:sub(1, 15) .. "." end
    screen.text(label)

    screen.level(track.mute and 15 or 3)
    screen.move(100, y + 8)
    screen.text(track.mute and "MUTED" or "on")

    if selected then
      screen.level(8)
      screen.rect(2, y, 124, 11)
      screen.stroke()
    end
  end

  screen.level(3)
  screen.move(64, 63)
  screen.text_center("E2:select  K3:toggle")
end

function UI:draw_play()
  local song = self.queue:current()
  screen.level(15)
  screen.move(0, 18)
  if song then
    local name = song.name
    if #name > 21 then name = name:sub(1, 20) .. "." end
    screen.text(name)
  else
    screen.text("No song loaded")
  end

  -- BPM
  screen.level(10)
  screen.move(0, 28)
  local bpm = self.seq:get_bpm()
  local bpm_str = string.format("BPM: %d", bpm)
  if self.seq.bpm_override then bpm_str = bpm_str .. "*" end
  screen.text(bpm_str)

  -- Play state
  screen.level(15)
  screen.move(70, 28)
  screen.text(self.seq.playing and "> PLAY" or "  STOP")

  -- Progress bar
  local progress = 0
  if self.seq.duration > 0 then
    progress = self.seq.elapsed / self.seq.duration
  end
  screen.level(2)
  screen.rect(0, 33, 128, 4)
  screen.fill()
  screen.level(12)
  screen.rect(0, 33, math.floor(128 * progress), 4)
  screen.fill()

  -- Time + queue position
  screen.level(6)
  screen.move(0, 45)
  screen.text(format_time(self.seq.elapsed) .. " / " .. format_time(self.seq.duration))

  if self.queue:count() > 0 then
    screen.level(4)
    screen.move(90, 45)
    screen.text(self.queue.position .. "/" .. self.queue:count())
  end

  -- Rig status: 4 synth activity bars
  local synth_x = {0, 32, 64, 96}
  for si, rig in ipairs(RIG) do
    local lit = false
    local muted = true
    local active = false
    for ti, track in ipairs(self.seq.tracks) do
      if track.role == rig.role then
        active = true
        if not track.mute then muted = false end
        if self.flash[ti] and self.flash[ti] > 0 then lit = true end
      end
    end
    if not active then muted = true end

    local x = synth_x[si]
    screen.level(muted and 2 or (lit and 15 or 8))
    screen.move(x + 2, 55)
    screen.text(rig.label)

    if muted then
      screen.level(1)
    else
      screen.level(lit and 12 or 2)
    end
    screen.rect(x, 57, 28, 4)
    screen.fill()
  end
end

function UI:draw_tracks()
  local tc = self.seq:track_count()
  if tc == 0 then
    screen.level(4)
    screen.move(64, 35)
    screen.text_center("No song loaded")
    return
  end

  -- Header
  screen.level(4)
  screen.move(0, 14)
  screen.text("SYNTH  NAME       CH   OCT")

  local visible = 4
  for i = 1, visible do
    local idx = self.track_scroll + i
    if idx > tc then break end

    local track = self.seq.tracks[idx]
    local y = 14 + i * 11
    local selected = (self.track_cursor == idx)
    local muted = track.mute

    -- Synth assignment
    screen.level(muted and 3 or (selected and self.track_field == 1 and 15 or 6))
    screen.move(0, y + 6)
    if track.output == "off" then
      screen.text("OFF")
    else
      screen.text(TrackAssign.role_label(track.role))
    end

    -- Track name
    screen.level(muted and 3 or (selected and 12 or 5))
    screen.move(28, y + 6)
    local name = track.name
    if #name > 8 then name = name:sub(1, 7) .. "." end
    screen.text(name)

    -- Output channel
    screen.level(6)
    screen.move(80, y + 6)
    if track.output == "internal" then
      screen.text("DRM")
    elseif track.output == "off" then
      screen.text("--")
    else
      screen.text("ch" .. (track.out_channels[1] or "?"))
    end

    -- Octave
    screen.level(selected and self.track_field == 2 and 15 or 6)
    screen.move(110, y + 6)
    if track.output ~= "internal" and track.output ~= "off" then
      local oct = track.octave or 0
      screen.text(oct >= 0 and "+" .. oct or tostring(oct))
    end

    -- Mute indicator
    if muted then
      screen.level(3)
      screen.move(124, y + 6)
      screen.text("M")
    end
  end

  if tc > visible then
    screen.level(3)
    screen.move(128, 63)
    screen.text_right(self.track_scroll + 1 .. "-" .. math.min(self.track_scroll + visible, tc) .. "/" .. tc)
  end
end

function UI:draw_drums()
  screen.level(self.drum_cursor == 1 and 15 or 6)
  screen.move(0, 14)
  screen.text("Kit: " .. KIT_NAMES[self.state.kit or 1])

  screen.level(self.drum_cursor == 2 and 15 or 6)
  screen.move(0, 24)
  screen.text("Vol:" .. math.floor((self.drum_vol or 0.8) * 100) .. "%")

  screen.level(self.drum_cursor == 3 and 15 or 6)
  screen.move(50, 24)
  local freq_display
  if self.filter_freq >= 20000 then
    freq_display = "OFF"
  elseif self.filter_freq >= 1000 then
    freq_display = string.format("%.1fk", self.filter_freq / 1000)
  else
    freq_display = string.format("%dHz", math.floor(self.filter_freq))
  end
  screen.text("LPF:" .. freq_display)

  screen.level(self.drum_cursor == 4 and 15 or 6)
  screen.move(0, 34)
  screen.text("Res:" .. string.format("%.1f", self.filter_res))

  screen.level(self.drum_cursor == 5 and 15 or 6)
  screen.move(50, 34)
  screen.text("Rnd:" .. math.floor(self.random_amt * 100) .. "%")

  for i = 1, 8 do
    local x = ((i - 1) % 4) * 32
    local y = 40 + math.floor((i - 1) / 4) * 12
    screen.level(self.drum_flash[i] > 0 and 15 or 4)
    screen.move(x + 2, y + 8)
    screen.text(DRUM_VOICE_NAMES[i])
    screen.level(self.drum_flash[i] > 0 and 12 or 1)
    screen.rect(x, y + 10, 28, 2)
    screen.fill()
  end
end

function UI:draw_queue()
  screen.level(8)
  screen.move(64, 6)
  screen.text_center(self.queue:count() .. " songs")

  if self.queue:count() == 0 then
    screen.level(4)
    screen.move(64, 35)
    screen.text_center("Add songs from Library")
    return
  end

  local visible = 5
  for i = 1, visible do
    local idx = self.queue_scroll + i
    if idx > self.queue:count() then break end

    local song = self.queue.songs[idx]
    local y = 8 + i * 10
    local is_current = (idx == self.queue.position)
    local is_selected = (idx == self.queue_cursor)

    if is_selected then
      screen.level(1)
      screen.rect(0, y - 6, 128, 10)
      screen.fill()
    end

    screen.level(is_current and 15 or (is_selected and 12 or 5))
    screen.move(2, y + 2)
    local prefix = is_current and "> " or "  "
    local name = song.name
    if #name > 20 then name = name:sub(1, 19) .. "." end
    screen.text(prefix .. name)
  end

  screen.level(3)
  screen.move(128, 62)
  if self._save_flash and self._save_flash > 0 then
    screen.text_right("SAVED!")
    self._save_flash = self._save_flash - 1
  else
    screen.text_right("K2:del K3:play K1+K3:save")
  end
end

function UI:draw_library()
  if #self.lib_files == 0 then
    screen.level(4)
    screen.move(64, 35)
    screen.text_center("No MIDI files found")
    screen.move(64, 47)
    screen.text_center("Add .mid to midi/ folder")
    return
  end

  local fav_count = 0
  for _ in pairs(self.favorites) do fav_count = fav_count + 1 end
  screen.level(8)
  screen.move(64, 6)
  local header = #self.lib_files .. " files"
  if fav_count > 0 then header = header .. " / " .. fav_count .. " fav" end
  screen.text_center(header)

  local visible = 5
  for i = 1, visible do
    local idx = self.lib_scroll + i
    if idx > #self.lib_files then break end

    local entry = self.lib_files[idx]
    local y = 8 + i * 10
    local is_selected = (idx == self.lib_cursor)

    if is_selected then
      screen.level(1)
      screen.rect(0, y - 6, 128, 10)
      screen.fill()
    end

    local star = self:is_favorite(entry.display) and "*" or " "
    screen.level(is_selected and 15 or 5)
    screen.move(2, y + 2)
    screen.text(star)
    screen.move(8, y + 2)
    local name = entry.display
    if #name > 20 then name = name:sub(1, 19) .. "." end
    screen.text(name)
  end

  screen.level(3)
  screen.move(128, 62)
  screen.text_right("K3:add K1+K3:fav K2:play")
end

-- ===== INPUT HANDLING =====

function UI:enc(n, d)
  if self.k1_held then
    if n == 2 then
      self.mute_cursor = util.clamp(self.mute_cursor + d, 1, math.max(1, self.seq:track_count()))
    end
    return
  end

  if n == 1 then
    self.page = util.clamp(self.page + d, 1, 5)
  elseif self.page == 1 then
    self:enc_play(n, d)
  elseif self.page == 2 then
    self:enc_tracks(n, d)
  elseif self.page == 3 then
    self:enc_drums(n, d)
  elseif self.page == 4 then
    self:enc_queue(n, d)
  elseif self.page == 5 then
    self:enc_library(n, d)
  end
end

function UI:enc_play(n, d)
  if n == 2 then
    local bpm = self.seq:get_bpm() + d
    self.seq:set_bpm(bpm)
  elseif n == 3 then
    if d > 0 and self.queue:has_next() then
      if self.state.on_next then self.state.on_next() end
    end
  end
end

function UI:enc_tracks(n, d)
  local tc = self.seq:track_count()
  if tc == 0 then return end

  if n == 2 then
    self.track_cursor = util.clamp(self.track_cursor + d, 1, tc)
    if self.track_cursor > self.track_scroll + 4 then
      self.track_scroll = self.track_cursor - 4
    elseif self.track_cursor <= self.track_scroll then
      self.track_scroll = self.track_cursor - 1
    end
  elseif n == 3 then
    local track = self.seq.tracks[self.track_cursor]
    if not track then return end

    if self.track_field == 1 then
      -- Cycle role: bass -> lead -> chord -> drum -> off -> bass
      local roles = TrackAssign.cycle_roles()
      local cur = 1
      for i, r in ipairs(roles) do
        if r == "off" and track.output == "off" then cur = i; break end
        if track.role == r and track.output ~= "off" then cur = i; break end
      end
      cur = cur + d
      if cur < 1 then cur = #roles end
      if cur > #roles then cur = 1 end
      local new_role = roles[cur]
      if new_role == "off" then
        track.output = "off"
        track.out_channels = {0}
      elseif new_role == "drum" then
        track.role = "drum"
        track.output = "internal"
        track.out_channels = {0}
      else
        track.role = new_role
        track.output = "midi"
        TrackAssign.reassign_channels({track})
      end
    elseif self.track_field == 2 then
      if track.output ~= "internal" and track.output ~= "off" then
        track.octave = util.clamp((track.octave or 0) + d, -3, 3)
      end
    end
  end
end

function UI:enc_drums(n, d)
  if n == 2 then
    self.drum_cursor = util.clamp(self.drum_cursor + d, 1, 5)
  elseif n == 3 then
    if self.drum_cursor == 1 then
      self.state.kit = util.clamp((self.state.kit or 1) + d, 1, 3)
      params:set("drum_kit", self.state.kit)
    elseif self.drum_cursor == 2 then
      self.drum_vol = util.clamp((self.drum_vol or 0.8) + d * 0.05, 0, 1)
      engine.amp(self.drum_vol)
    elseif self.drum_cursor == 3 then
      local freq = self.filter_freq
      if d > 0 then freq = math.min(20000, freq * 1.08)
      else freq = math.max(60, freq / 1.08) end
      self.filter_freq = freq
      engine.lpf(freq)
    elseif self.drum_cursor == 4 then
      self.filter_res = util.clamp(self.filter_res + d * 0.05, 0.1, 1.0)
      engine.res(self.filter_res)
    elseif self.drum_cursor == 5 then
      self.random_amt = util.clamp(self.random_amt + d * 0.02, 0, 1)
      engine.random_amt(self.random_amt)
    end
  end
end

function UI:enc_queue(n, d)
  if n == 2 then
    self.queue_cursor = util.clamp(self.queue_cursor + d, 1, math.max(1, self.queue:count()))
    if self.queue_cursor > self.queue_scroll + 5 then
      self.queue_scroll = self.queue_cursor - 5
    elseif self.queue_cursor <= self.queue_scroll then
      self.queue_scroll = self.queue_cursor - 1
    end
  elseif n == 3 then
    if d > 0 then
      self.queue:move_down(self.queue_cursor)
      self.queue_cursor = util.clamp(self.queue_cursor + 1, 1, self.queue:count())
    else
      self.queue:move_up(self.queue_cursor)
      self.queue_cursor = util.clamp(self.queue_cursor - 1, 1, self.queue:count())
    end
  end
end

function UI:enc_library(n, d)
  if n == 2 or n == 3 then
    self.lib_cursor = util.clamp(self.lib_cursor + d, 1, math.max(1, #self.lib_files))
    if self.lib_cursor > self.lib_scroll + 5 then
      self.lib_scroll = self.lib_cursor - 5
    elseif self.lib_cursor <= self.lib_scroll then
      self.lib_scroll = self.lib_cursor - 1
    end
  end
end

function UI:key(n, z)
  if n == 1 then
    self.k1_held = (z == 1)
    return
  end

  if z ~= 1 then return end

  if self.k1_held then
    if self.page == 4 then
      self:key_queue(n)
      return
    elseif self.page == 5 then
      self:key_library(n)
      return
    else
      if n == 3 then
        self.seq:toggle_mute(self.mute_cursor)
      end
      return
    end
  end

  if self.page == 1 then
    self:key_play(n)
  elseif self.page == 2 then
    self:key_tracks(n)
  elseif self.page == 3 then
    self:key_drums(n)
  elseif self.page == 4 then
    self:key_queue(n)
  elseif self.page == 5 then
    self:key_library(n)
  end
end

function UI:key_play(n)
  if n == 2 then
    if self.seq.playing then
      self.seq:stop()
    else
      self.seq:play()
    end
  elseif n == 3 then
    self.seq:restart()
  end
end

function UI:key_tracks(n)
  if n == 2 then
    self.track_field = (self.track_field == 1) and 2 or 1
  elseif n == 3 then
    self.seq:toggle_mute(self.track_cursor)
  end
end

function UI:key_drums(n)
  if n == 2 then
    engine.randomize()
  elseif n == 3 then
    engine.random_keep()
  end
end

function UI:key_queue(n)
  if n == 2 then
    self.queue:remove(self.queue_cursor)
    self.queue_cursor = util.clamp(self.queue_cursor, 1, math.max(1, self.queue:count()))
  elseif n == 3 then
    if self.k1_held then
      if self.queue:count() > 0 then
        local playlist_dir = _path.code .. "retrospects-playbox/playlists"
        os.execute("mkdir -p " .. playlist_dir)
        local filepath = playlist_dir .. "/saved.txt"
        if self.queue:save_playlist(filepath) then
          print("Queue saved to " .. filepath)
          self._save_flash = 30
        end
      end
    else
      self.queue.position = self.queue_cursor
      if self.state.on_load_current then
        self.state.on_load_current()
      end
    end
  end
end

function UI:key_library(n)
  if n == 2 then
    local entry = self.lib_files[self.lib_cursor]
    if entry and self.state.on_play_file then
      self.state.on_play_file(entry)
    end
  elseif n == 3 then
    local entry = self.lib_files[self.lib_cursor]
    if entry then
      if self.k1_held then
        self:toggle_favorite(entry.display)
      else
        self.queue:add(entry.display, entry.file)
      end
    end
  end
end

-- ===== HELPERS =====

function format_time(seconds)
  if not seconds or seconds < 0 then return "0:00" end
  local m = math.floor(seconds / 60)
  local s = math.floor(seconds % 60)
  return string.format("%d:%02d", m, s)
end

return UI
