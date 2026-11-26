-- Copyright (c) 2025 Jeremy W Kuhne
-- SPDX-License-Identifier: MIT
-- See LICENSE file in the project root for full license information
--
-- MAME autoboot script for the Apple III frame oracle (Apple3OracleTests). At the emulated second given, it writes
-- the screen as raw RGBA, 4 bytes a pixel, row by row, and exits.
--
-- RETRO_END: the emulated second to capture at.
-- RETRO_OUT: the file to write.

local output = os.getenv("RETRO_OUT") or "frame.rgba"
-- MAME's time is whole seconds and attoseconds, so times are compared as attotimes: time.seconds drops a
-- fraction such as 2.5, and time:as_double() rounds a frame at 2.999999999999999880 up to 3, a frame early.
local finish = emu.attotime.from_double(tonumber(os.getenv("RETRO_END") or "4"))

subscription = emu.add_machine_frame_notifier(function()
  if manager.machine.time < finish then return end
  local screen = manager.machine.screens[":screen"]
  local pixels, width, height = screen:pixels()
  local rgba = {}
  for i = 1, width * height do
    -- MAME gives 32-bit ARGB, little-endian: blue, green, red, alpha.
    local b, g, r = string.byte(pixels, (i - 1) * 4 + 1, (i - 1) * 4 + 3)
    rgba[#rgba + 1] = string.char(r, g, b, 255)
  end

  local file = io.open(output, "wb")
  file:write(table.concat(rgba))
  file:close()
  print(string.format("frame %dx%d", width, height))
  manager.machine:exit()
end)
