-- Copyright (c) 2025 Jeremy W Kuhne
-- SPDX-License-Identifier: MIT
-- See LICENSE file in the project root for full license information
--
-- MAME autoboot script for the Model I oracle (Trs80OracleTests). It types a schedule of keystrokes and,
-- at the end, writes the 64K address space as MAME's CPU sees it to a file.
--
-- RETRO_SCRIPT: entries "seconds=text" separated by '|', where text may contain \r for ENTER.
-- RETRO_END:    the emulated second to dump at.
-- RETRO_OUT:    the dump file.
-- RETRO_FIRED:  optional; a file to log, a line per entry, "seconds=fired": the entry's time and the emulated
--               second it fired.

local space = manager.machine.devices[":maincpu"].spaces["program"]
local schedule = {}
for entry in string.gmatch(os.getenv("RETRO_SCRIPT") or "", "[^|]+") do
  local at, text = string.match(entry, "^([%d%.]+)=(.*)$")
  if not tonumber(at) then error("RETRO_SCRIPT entry is not seconds=text: " .. entry) end
  local seconds = tonumber(at)
  schedule[#schedule + 1] = { at = seconds, time = emu.attotime.from_double(seconds), text = (text:gsub("\\r", "\r")) }
end

-- MAME's time is whole seconds and attoseconds, so times are compared as attotimes: time.seconds drops a
-- fraction such as 2.5, and time:as_double() rounds a frame at 2.999999999999999880 up to 3, a frame early.
local finish = emu.attotime.from_double(tonumber(os.getenv("RETRO_END") or "10"))
local output = os.getenv("RETRO_OUT") or "memory.bin"
local fired_log = os.getenv("RETRO_FIRED")
local fired = {}
local next_entry = 1
local done = false

subscription = emu.add_machine_frame_notifier(function()
  local now = manager.machine.time
  while next_entry <= #schedule and now >= schedule[next_entry].time do
    manager.machine.natkeyboard:post(schedule[next_entry].text)
    fired[#fired + 1] = string.format("%.6f=%.6f", schedule[next_entry].at, now:as_double())
    next_entry = next_entry + 1
  end

  if not done and now >= finish then
    done = true
    local bytes = {}
    for address = 0, 0xFFFF do bytes[#bytes + 1] = string.char(space:read_u8(address)) end
    local file = io.open(output, "wb")
    file:write(table.concat(bytes))
    file:close()
    if fired_log then
      local log = io.open(fired_log, "w")
      log:write(table.concat(fired, "\n"), "\n")
      log:close()
    end
    manager.machine:exit()
  end
end)
