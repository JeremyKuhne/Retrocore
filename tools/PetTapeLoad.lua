-- Copyright (c) 2025 Jeremy W Kuhne
-- SPDX-License-Identifier: MIT
-- See LICENSE file in the project root for full license information
--
-- MAME autoboot script for the tape oracles (PetTapeTests, Vic20TapeTests). With a tape in the cassette (-cass1 on
-- the PET, -cass on the VIC-20), it types LOAD and presses PLAY at the third emulated second, and at the emulated
-- second given writes the 1,000 bytes at $8000 (the PET's screen) and the 64K the CPU sees to a file, then exits.
--
-- RETRO_END: the emulated second to stop at.
-- RETRO_OUT: the file to write: $8000-$83E7, then $0000-$FFFF.
-- RETRO_CPU: the CPU's tag: f3 (the PET's, the default) or ue10 (the VIC-20's).

local output = os.getenv("RETRO_OUT") or "memory.bin"
local cpu = ":" .. (os.getenv("RETRO_CPU") or "f3")
-- MAME's time is whole seconds and attoseconds, so times are compared as attotimes: time.seconds drops a
-- fraction such as 2.5, and time:as_double() rounds a frame at 2.999999999999999880 up to 3, a frame early.
local load_at = emu.attotime.from_double(3)
local finish = emu.attotime.from_double(tonumber(os.getenv("RETRO_END") or "120"))
local typed = false

subscription = emu.add_machine_frame_notifier(function()
  local now = manager.machine.time
  if not typed and now >= load_at then
    typed = true
    manager.machine.natkeyboard:post("LOAD\r")
    for _, cassette in pairs(manager.machine.cassettes) do cassette:play() end
  end

  if now < finish then return end
  local space = manager.machine.devices[cpu].spaces["program"]
  local bytes = {}
  for address = 0x8000, 0x83E7 do bytes[#bytes + 1] = string.char(space:read_u8(address)) end
  for address = 0x0000, 0xFFFF do bytes[#bytes + 1] = string.char(space:read_u8(address)) end
  local file = io.open(output, "wb")
  file:write(table.concat(bytes))
  file:close()
  manager.machine:exit()
end)
