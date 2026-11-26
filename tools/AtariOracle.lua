-- Copyright (c) 2025 Jeremy W Kuhne
-- SPDX-License-Identifier: MIT
-- See LICENSE file in the project root for full license information
--
-- MAME autoboot script for the Atari 400/800 oracle (AtariOracleTests). It needs MAME's debugger (-debug, with
-- -debugger none) and traces every instruction of a CPU, with the registers before it, until the emulated second
-- given.
--
-- RETRO_CPU: the CPU to trace: maincpu (the default), or an 810's 6507, :sio:a810:fdcpu.
-- RETRO_END: the emulated second to stop at.
-- RETRO_OUT: the trace file; each line is "a x y p sp|PC: disassembly".
-- RETRO_KEYS: optional text to type, with \r for RETURN, starting at the emulated second RETRO_KEYS_AT.

local output = (os.getenv("RETRO_OUT") or "trace.log"):gsub("\\", "/")
-- MAME's time is whole seconds and attoseconds, so times are compared as attotimes: time.seconds drops a
-- fraction such as 2.5, and time:as_double() rounds a frame at 2.999999999999999880 up to 3, a frame early.
local finish = emu.attotime.from_double(tonumber(os.getenv("RETRO_END") or "1"))
local keys = os.getenv("RETRO_KEYS")
local keysAt = emu.attotime.from_double(tonumber(os.getenv("RETRO_KEYS_AT") or "0"))
local cpu = os.getenv("RETRO_CPU") or "maincpu"
local typed = false
local debugger = manager.machine.debugger
-- The trace's action logs the registers of the debugger's visible CPU, to its trace.
if cpu ~= "maincpu" then debugger.visible_cpu = manager.machine.devices[cpu] end
debugger:command('trace ' .. output .. ',' .. cpu .. ',noloop,{tracelog "%02x %02x %02x %02x %02x|",a,x,y,p,sp}')
debugger.execution_state = "run"

subscription = emu.add_machine_frame_notifier(function()
  local now = manager.machine.time
  if keys and not typed and now >= keysAt then
    manager.machine.natkeyboard:post((keys:gsub("\\r", "\r")))
    typed = true
  end

  if now >= finish then
    debugger:command("trace off," .. cpu)
    manager.machine:exit()
  end
end)
