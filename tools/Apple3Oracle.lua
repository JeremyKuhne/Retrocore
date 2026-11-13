-- Copyright (c) 2025 Jeremy W Kuhne
-- SPDX-License-Identifier: MIT
-- See LICENSE file in the project root for full license information
--
-- MAME autoboot script for the Apple III oracle (Apple3OracleTests). It needs MAME's debugger (-debug, with
-- -debugger none) and traces every instruction, with the registers before it, until the emulated second given.
--
-- RETRO_END: the emulated second to stop at.
-- RETRO_OUT: the trace file; each line is "a x y p sp|PC: disassembly".
--
-- The trace reads no memory: on MAME's Apple III a debugger read of zero page can latch an X-byte.

local output = (os.getenv("RETRO_OUT") or "trace.log"):gsub("\\", "/")
local finish = tonumber(os.getenv("RETRO_END") or "1")
local debugger = manager.machine.debugger
debugger:command('trace ' .. output .. ',maincpu,noloop,{tracelog "%02x %02x %02x %02x %02x|",a,x,y,p,sp}')
debugger.execution_state = "run"

subscription = emu.add_machine_frame_notifier(function()
  if manager.machine.time.seconds >= finish then
    debugger:command("trace off,maincpu")
    manager.machine:exit()
  end
end)
