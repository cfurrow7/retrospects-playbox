-- track_assign.lua: Retrospects live rig routing
-- Smart assignment: name detection + note analysis scoring
-- M32 (bass/ch2), OB-6 (mono lead/ch4), PRO-800 (chords/ch11), Drums (internal)
-- Two modes: GREEDY (everything plays) and SMART (best 3 + drums, rest muted)

local TrackAssign = {}

-- The Retrospects live rig
TrackAssign.BASS_CH = 2    -- Mother 32
TrackAssign.LEAD_CH = 4    -- OB-6 (strict mono, latest note wins)
TrackAssign.CHORD_CH = 11  -- PRO-800 (full poly, no cap)

-- GM drum note to voice mapping (8 voices)
TrackAssign.gm_drum_map = {
  [35] = 0, [36] = 0,
  [38] = 1, [40] = 1, [37] = 1,
  [42] = 2, [44] = 2,
  [46] = 3,
  [39] = 4, [54] = 4,
  [41] = 5, [43] = 5, [45] = 5,
  [47] = 6, [48] = 6, [50] = 6,
  [49] = 7, [51] = 3, [52] = 7,
  [53] = 3, [55] = 7, [56] = 7, [57] = 7,
  [59] = 3,
}

for n = 58, 81 do
  if not TrackAssign.gm_drum_map[n] then
    TrackAssign.gm_drum_map[n] = 7
  end
end

-- ===== NAME DETECTION =====
-- Patterns that strongly suggest a role (checked in priority order)

local name_scores = {
  bass = {
    strong = { "bass", "fretless", "fingered", "slap" },
    weak   = { "cello", "tuba", "contrabass" },
  },
  lead = {
    strong = { "lead", "melody", "solo", "vocal", "voice", "flute", "trumpet",
               "sax", "whistle", "oboe", "clarinet", "harmonica" },
    weak   = { "synth lead", "guitar solo" },
  },
  chord = {
    strong = { "chord", "pad", "organ", "piano", "key", "string", "acoustic",
               "rhythm", "guitar", "harp", "vibes", "vibraphone", "marimba" },
    weak   = { "backing", "accomp", "comp", "rhythm guitar" },
  },
  drum = {
    strong = { "drum", "perc", "kit", "beat", "cymbal", "snare", "kick", "hat" },
    weak   = {},
  },
}

-- Score a track name against a role (0 = no match, 10 = strong, 5 = weak)
local function name_score(name, role)
  if not name then return 0 end
  local lower = string.lower(name)
  local patterns = name_scores[role]
  if not patterns then return 0 end
  for _, pat in ipairs(patterns.strong) do
    if string.find(lower, pat, 1, true) then return 10 end
  end
  for _, pat in ipairs(patterns.weak) do
    if string.find(lower, pat, 1, true) then return 5 end
  end
  return 0
end

-- ===== NOTE ANALYSIS =====

-- Score how well a track fits each role based on note data
local function note_score_bass(info)
  local median = math.floor((info.min_note + info.max_note) / 2)
  local score = 0
  -- Low notes are bassy
  if median <= 48 then score = score + 10      -- below C3
  elseif median <= 55 then score = score + 7   -- below G3
  elseif median <= 60 then score = score + 3   -- below C4
  end
  -- Bass is usually monophonic or near-mono
  if info.max_poly <= 2 then score = score + 3 end
  -- Narrow range is more bass-like
  local range = info.max_note - info.min_note
  if range <= 24 then score = score + 2 end
  return score
end

local function note_score_lead(info)
  local median = math.floor((info.min_note + info.max_note) / 2)
  local score = 0
  -- High notes = lead
  if median >= 72 then score = score + 8       -- above C5
  elseif median >= 64 then score = score + 6   -- above E4
  elseif median >= 60 then score = score + 3   -- above C4
  end
  -- Lead is monophonic or near-mono
  if info.max_poly <= 2 then score = score + 5
  elseif info.max_poly <= 3 then score = score + 2
  end
  -- Moderate note count (not too sparse, not chords)
  if info.note_count >= 20 then score = score + 2 end
  return score
end

local function note_score_chord(info)
  local median = math.floor((info.min_note + info.max_note) / 2)
  local score = 0
  -- Mid-range notes
  if median >= 48 and median <= 72 then score = score + 5 end
  -- High polyphony = chords
  if info.max_poly >= 3 then score = score + 6
  elseif info.max_poly >= 2 then score = score + 3
  end
  -- Wide range suggests chord voicings
  local range = info.max_note - info.min_note
  if range >= 24 then score = score + 3 end
  -- Lots of notes
  if info.note_count >= 50 then score = score + 2 end
  return score
end

-- ===== COMBINED SCORING =====

-- Score each track for each role, return { bass=N, lead=N, chord=N }
local function score_track(info)
  local scores = {
    bass  = name_score(info.name, "bass")  + note_score_bass(info),
    lead  = name_score(info.name, "lead")  + note_score_lead(info),
    chord = name_score(info.name, "chord") + note_score_chord(info),
  }
  return scores
end

-- ===== BUILD TRACKS =====

function TrackAssign.build_tracks(ch_data, mode)
  mode = mode or "greedy"
  local tracks = {}

  -- First pass: create track objects with scores
  for ch, info in pairs(ch_data) do
    local is_drum = (ch == 10)
    local role_scores = nil

    if not is_drum then
      role_scores = score_track(info)
    end

    table.insert(tracks, {
      source_ch = ch,
      name = info.name or ("Ch " .. ch),
      role = is_drum and "drum" or nil,  -- assigned in second pass
      output = is_drum and "internal" or "midi",
      out_channels = is_drum and {0} or {},
      octave = 0,
      velocity_scale = 1.0,
      mute = false,
      note_count = info.note_count,
      min_note = info.min_note,
      max_note = info.max_note,
      max_poly = info.max_poly or 1,
      _scores = role_scores,
    })
  end

  -- Sort non-drum tracks by total score (most "useful" first)
  table.sort(tracks, function(a, b)
    if a.role == "drum" and b.role ~= "drum" then return false end
    if a.role ~= "drum" and b.role == "drum" then return true end
    if a._scores and b._scores then
      local a_max = math.max(a._scores.bass, a._scores.lead, a._scores.chord)
      local b_max = math.max(b._scores.bass, b._scores.lead, b._scores.chord)
      return a_max > b_max
    end
    return a.note_count > b.note_count
  end)

  -- Second pass: assign roles using greedy best-fit
  local assigned = { bass = nil, lead = nil }
  local chord_tracks = {}

  -- Find best bass candidate
  local best_bass_score = -1
  local best_bass_idx = nil
  for i, t in ipairs(tracks) do
    if t.role ~= "drum" and t._scores then
      if t._scores.bass > best_bass_score then
        best_bass_score = t._scores.bass
        best_bass_idx = i
      end
    end
  end

  -- Find best lead candidate (excluding bass winner)
  local best_lead_score = -1
  local best_lead_idx = nil
  for i, t in ipairs(tracks) do
    if t.role ~= "drum" and t._scores and i ~= best_bass_idx then
      if t._scores.lead > best_lead_score then
        best_lead_score = t._scores.lead
        best_lead_idx = i
      end
    end
  end

  -- Assign roles
  for i, t in ipairs(tracks) do
    if t.role == "drum" then
      -- already set
    elseif i == best_bass_idx then
      t.role = "bass"
      t.out_channels = {TrackAssign.BASS_CH}
    elseif i == best_lead_idx then
      t.role = "lead"
      t.out_channels = {TrackAssign.LEAD_CH}
    else
      t.role = "chord"
      table.insert(chord_tracks, t)
      t.out_channels = {TrackAssign.CHORD_CH}
    end
  end

  -- SMART mode: mute everything except best bass, best lead, best chord
  if mode == "smart" then
    -- Find the best chord track (highest chord score)
    local best_chord_score = -1
    local best_chord = nil
    for _, t in ipairs(chord_tracks) do
      if t._scores and t._scores.chord > best_chord_score then
        best_chord_score = t._scores.chord
        best_chord = t
      end
    end
    -- Mute all other chord tracks
    for _, t in ipairs(chord_tracks) do
      if t ~= best_chord then
        t.mute = true
      end
    end
  end

  -- Clean up scoring data
  for _, t in ipairs(tracks) do
    t._scores = nil
  end

  return tracks
end

-- Reassign channels based on current roles
function TrackAssign.reassign_channels(tracks)
  if not tracks then return end
  for _, t in ipairs(tracks) do
    if t.output == "off" then
      t.out_channels = {0}
    elseif t.role == "drum" then
      t.out_channels = {0}
    elseif t.role == "bass" then
      t.out_channels = {TrackAssign.BASS_CH}
    elseif t.role == "lead" then
      t.out_channels = {TrackAssign.LEAD_CH}
    elseif t.role == "chord" then
      t.out_channels = {TrackAssign.CHORD_CH}
    else
      t.out_channels = {TrackAssign.CHORD_CH}
    end
  end
end

-- Map a GM drum note to a drum voice (0-7)
function TrackAssign.map_drum_note(note)
  return TrackAssign.gm_drum_map[note]
end

-- Role display labels
function TrackAssign.role_label(role)
  local labels = {
    bass  = "M32",
    lead  = "OB6",
    chord = "P800",
    drum  = "DRM",
  }
  return labels[role] or "???"
end

-- Synth name for display (longer form)
function TrackAssign.synth_name(role)
  local names = {
    bass  = "M32 ch2",
    lead  = "OB6 ch4",
    chord = "P800 ch11",
    drum  = "DRM",
  }
  return names[role] or "???"
end

-- Available roles for cycling on tracks page
function TrackAssign.cycle_roles()
  return { "bass", "lead", "chord", "drum", "off" }
end

return TrackAssign
