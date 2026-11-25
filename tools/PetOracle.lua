-- Copyright (c) 2025 Jeremy W Kuhne
-- SPDX-License-Identifier: MIT
-- See LICENSE file in the project root for full license information
--
-- MAME autoboot script for the PET oracle (PetOracleTests). It needs MAME's debugger (-debug, with
-- -debugger none) and traces every instruction, with the registers before it, until the emulated second given.
-- Run MAME with -ieee8 "": tracelog writes to CPU 0's trace, which is otherwise the 4040 drive's 6502.
--
-- RETRO_END: the emulated second to stop at.
-- RETRO_OUT: the trace file; each line is "a x y p sp|PC: disassembly".

local output = (os.getenv("RETRO_OUT") or "trace.log"):gsub("\\", "/")
local finish = tonumber(os.getenv("RETRO_END") or "1")
local debugger = manager.machine.debugger
debugger:command('trace ' .. output .. ',f3,noloop,{tracelog "%02x %02x %02x %02x %02x|",a,x,y,p,sp}')
debugger.execution_state = "run"

subscription = emu.add_machine_frame_notifier(function()
  -- time.seconds counts whole seconds; as_double keeps the fraction of a time such as 2.5.
  if manager.machine.time:as_double() >= finish then
    debugger:command("trace off,f3")
    manager.machine:exit()
  end
end)
