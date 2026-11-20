-- Copyright (c) 2025 Jeremy W Kuhne
-- SPDX-License-Identifier: MIT
-- See LICENSE file in the project root for full license information
--
-- MAME autoboot script for the PET tape oracle (PetTapeTests). With a tape in cassette 1 (-cass1), it waits for
-- READY., types LOAD, presses PLAY, and at the emulated second given writes the screen's 1,000 bytes and the 64K
-- the CPU sees to a file, then exits.
--
-- RETRO_END: the emulated second to stop at.
-- RETRO_OUT: the file to write: video RAM ($8000-$83E7), then $0000-$FFFF.

local output = os.getenv("RETRO_OUT") or "memory.bin"
local finish = tonumber(os.getenv("RETRO_END") or "120")
local typed = false

subscription = emu.add_machine_frame_notifier(function()
  local seconds = manager.machine.time.seconds
  if not typed and seconds >= 3 then
    typed = true
    manager.machine.natkeyboard:post("LOAD\r")
    for _, cassette in pairs(manager.machine.cassettes) do cassette:play() end
  end

  if seconds < finish then return end
  local space = manager.machine.devices[":f3"].spaces["program"]
  local bytes = {}
  for address = 0x8000, 0x83E7 do bytes[#bytes + 1] = string.char(space:read_u8(address)) end
  for address = 0x0000, 0xFFFF do bytes[#bytes + 1] = string.char(space:read_u8(address)) end
  local file = io.open(output, "wb")
  file:write(table.concat(bytes))
  file:close()
  manager.machine:exit()
end)
