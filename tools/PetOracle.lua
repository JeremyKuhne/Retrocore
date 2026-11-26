-- Copyright (c) 2025 Jeremy W Kuhne
-- SPDX-License-Identifier: MIT
-- See LICENSE file in the project root for full license information
--
-- MAME autoboot script for the PET and VIC-20 oracles (PetOracleTests, Vic20OracleTests). It needs MAME's debugger
-- (-debug, with -debugger none) and traces every instruction, with the registers before it, until the emulated
-- second given. Run MAME with its drive slot empty, -ieee8 "" on the PET and -iec8 "" on the VIC-20, so that no
-- drive's processor is traced; on the PET, CPU 0's trace would otherwise be the 4040 drive's 6502.
--
-- RETRO_CPU: the CPU's tag, f3 (the PET's) unless given; the VIC-20's is ue10.
-- RETRO_END: the emulated second to stop at.
-- RETRO_OUT: the trace file; each line is "a x y p sp|PC: disassembly".

local output = (os.getenv("RETRO_OUT") or "trace.log"):gsub("\\", "/")
local cpu = os.getenv("RETRO_CPU") or "f3"
-- MAME's time is whole seconds and attoseconds, so times are compared as attotimes: time.seconds drops a
-- fraction such as 2.5, and time:as_double() rounds a frame at 2.999999999999999880 up to 3, a frame early.
local finish = emu.attotime.from_double(tonumber(os.getenv("RETRO_END") or "1"))
local debugger = manager.machine.debugger
debugger:command('trace ' .. output .. ',' .. cpu .. ',noloop,{tracelog "%02x %02x %02x %02x %02x|",a,x,y,p,sp}')
debugger.execution_state = "run"

subscription = emu.add_machine_frame_notifier(function()
  if manager.machine.time >= finish then
    debugger:command("trace off," .. cpu)
    manager.machine:exit()
  end
end)
