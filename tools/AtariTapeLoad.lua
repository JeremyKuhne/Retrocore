-- Copyright (c) 2025 Jeremy W Kuhne
-- SPDX-License-Identifier: MIT
-- See LICENSE file in the project root for full license information
--
-- MAME autoboot script for the Atari tape oracle (AtariTapeTests). With BASIC in the left slot and a tape in the
-- recorder (-sio cassette -cass), it types CLOAD at 3 seconds, presses PLAY and, at 6 seconds (after the OS's beep), RETURN; types
-- RUN at the emulated second given; and at the end writes the 64K the CPU sees to a file, then exits.
--
-- RETRO_RUN: the emulated second to type RUN at.
-- RETRO_END: the emulated second to stop at.
-- RETRO_OUT: the file to write: $0000-$FFFF.

local output = os.getenv("RETRO_OUT") or "memory.bin"
local run = tonumber(os.getenv("RETRO_RUN") or "60")
local finish = tonumber(os.getenv("RETRO_END") or "70")
local stage = 0

subscription = emu.add_machine_frame_notifier(function()
  local seconds = manager.machine.time.seconds
  if stage == 0 and seconds >= 3 then
    stage = 1
    manager.machine.natkeyboard:post("CLOAD\r")
    for _, cassette in pairs(manager.machine.cassettes) do cassette:play() end
  elseif stage == 1 and seconds >= 6 then
    stage = 2
    manager.machine.natkeyboard:post("\r")
  elseif stage == 2 and seconds >= run then
    stage = 3
    manager.machine.natkeyboard:post("RUN\r")
  end

  if seconds < finish then return end
  local space = manager.machine.devices[":maincpu"].spaces["program"]
  local bytes = {}
  for address = 0x0000, 0xFFFF do bytes[#bytes + 1] = string.char(space:read_u8(address)) end
  local file = io.open(output, "wb")
  file:write(table.concat(bytes))
  file:close()
  manager.machine:exit()
end)
