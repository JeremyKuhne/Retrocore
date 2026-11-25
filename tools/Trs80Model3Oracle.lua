-- Copyright (c) 2025 Jeremy W Kuhne
-- SPDX-License-Identifier: MIT
-- See LICENSE file in the project root for full license information
--
-- MAME autoboot script for the Model III, 4 and II oracle (Trs80Model3OracleTests). It types a schedule of
-- keystrokes and, at the end, writes the CPU's 64K address space and then a memory share, such as video RAM, to a
-- file.
--
-- RETRO_SCRIPT: entries "seconds=text" separated by '|', where text may contain \r for ENTER, or is
--               "@port,field,state" to press (1) or release (0) a key the natural keyboard cannot type, such as
--               "@:LINE7,F1,1".
-- RETRO_END:    the emulated second to dump at.
-- RETRO_OUT:    the dump file.
-- RETRO_SHARE:  the memory share written after the address space, such as ":videoram".
-- RETRO_CPU:    the CPU's tag, ":maincpu" unless set.

local space = manager.machine.devices[os.getenv("RETRO_CPU") or ":maincpu"].spaces["program"]
local schedule = {}
for entry in string.gmatch(os.getenv("RETRO_SCRIPT") or "", "[^|]+") do
  local at, text = string.match(entry, "^([%d%.]+)=(.*)$")
  schedule[#schedule + 1] = { at = tonumber(at), text = (text:gsub("\\r", "\r")) }
end
local finish = tonumber(os.getenv("RETRO_END") or "10")
local output = os.getenv("RETRO_OUT") or "memory.bin"
local share = os.getenv("RETRO_SHARE")
local next_entry = 1
local done = false
subscription = emu.add_machine_frame_notifier(function()
  -- time.seconds counts whole seconds; as_double keeps the fraction of a time such as 2.5.
  local now = manager.machine.time:as_double()
  while next_entry <= #schedule and now >= schedule[next_entry].at do
    local text = schedule[next_entry].text
    local port, field, state = string.match(text, "^@([^,]+),([^,]+),([01])$")
    if port then
      manager.machine.ioport.ports[port].fields[field]:set_value(tonumber(state))
    else
      manager.machine.natkeyboard:post(text)
    end
    next_entry = next_entry + 1
  end
  if not done and now >= finish then
    done = true
    local bytes = {}
    for address = 0, 0xFFFF do bytes[#bytes + 1] = string.char(space:read_u8(address)) end
    if share then
      local s = manager.machine.memory.shares[share]
      for offset = 0, s.size - 1 do bytes[#bytes + 1] = string.char(s:read_u8(offset)) end
    end
    local file = io.open(output, "wb")
    file:write(table.concat(bytes))
    file:close()
    manager.machine:exit()
  end
end)
