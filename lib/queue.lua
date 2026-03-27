-- queue.lua: Song queue and playlist management

local Queue = {}
Queue.__index = Queue

function Queue.new()
  local self = setmetatable({}, Queue)
  self.songs = {}     -- { { name="Song", file="path.mid" }, ... }
  self.position = 1   -- current song index
  return self
end

function Queue:add(name, filepath, pc, ob6_pc)
  table.insert(self.songs, { name = name, file = filepath, pc = pc, ob6_pc = ob6_pc })
end

function Queue:remove(index)
  if index >= 1 and index <= #self.songs then
    table.remove(self.songs, index)
    -- Adjust position if needed
    if self.position > #self.songs then
      self.position = math.max(1, #self.songs)
    end
  end
end

function Queue:clear()
  self.songs = {}
  self.position = 1
end

function Queue:current()
  if #self.songs == 0 then return nil end
  if self.position > #self.songs then return nil end
  return self.songs[self.position]
end

function Queue:advance()
  if self.position < #self.songs then
    self.position = self.position + 1
    return self:current()
  end
  return nil  -- end of queue
end

function Queue:has_next()
  return self.position < #self.songs
end

function Queue:count()
  return #self.songs
end

function Queue:move_up(index)
  if index > 1 and index <= #self.songs then
    self.songs[index], self.songs[index - 1] = self.songs[index - 1], self.songs[index]
    if self.position == index then
      self.position = index - 1
    elseif self.position == index - 1 then
      self.position = index
    end
  end
end

function Queue:move_down(index)
  if index >= 1 and index < #self.songs then
    self.songs[index], self.songs[index + 1] = self.songs[index + 1], self.songs[index]
    if self.position == index then
      self.position = index + 1
    elseif self.position == index + 1 then
      self.position = index
    end
  end
end

-- Load playlist from text file (one filename per line)
function Queue:load_playlist(filepath, midi_dir)
  local f = io.open(filepath, "r")
  if not f then return false, "Cannot open playlist" end

  self:clear()
  for line in f:lines() do
    line = line:match("^%s*(.-)%s*$")  -- trim
    if line ~= "" and not line:match("^#") then  -- skip empty and comments
      -- Parse optional program changes: "filename.mid|pro800_pc|ob6_pc"
      local filename, pc1_str, pc2_str = line:match("^(.-)%s*|%s*(%d+)%s*|%s*(%d+)%s*$")
      if not filename then
        filename, pc1_str = line:match("^(.-)%s*|%s*(%d+)%s*$")
      end
      if not filename then filename = line end
      local pc = pc1_str and tonumber(pc1_str) or nil
      local ob6_pc = pc2_str and tonumber(pc2_str) or nil
      if pc then pc = math.max(0, math.min(127, pc)) end
      if ob6_pc then ob6_pc = math.max(0, math.min(127, ob6_pc)) end

      local name = filename:match("(.+)%.mid[i]?$") or filename
      local full_path = midi_dir .. "/" .. filename
      -- Add .mid if not present
      if not filename:match("%.mid[i]?$") then
        full_path = full_path .. ".mid"
      end
      self:add(name, full_path, pc, ob6_pc)
    end
  end
  f:close()
  return true
end

-- Save current queue as a playlist file
function Queue:save_playlist(filepath)
  local f = io.open(filepath, "w")
  if not f then return false end
  for _, song in ipairs(self.songs) do
    -- Write the filename relative to midi dir, with optional PCs
    local name = song.file:match(".*/(.+)$") or song.file
    if song.pc or song.ob6_pc then
      local p1 = song.pc or 0
      local p2 = song.ob6_pc
      if p2 then
        f:write(name .. "|" .. p1 .. "|" .. p2 .. "\n")
      else
        f:write(name .. "|" .. p1 .. "\n")
      end
    else
      f:write(name .. "\n")
    end
  end
  f:close()
  return true
end

return Queue
