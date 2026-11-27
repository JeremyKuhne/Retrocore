-- Copyright (c) 2025 Jeremy W Kuhne
-- SPDX-License-Identifier: MIT
-- See LICENSE file in the project root for full license information
--
-- MAME autoboot script for the drive oracles (Pet4040OracleTests, Vic20DiskOracleTests). It needs MAME's debugger
-- (-debug, with -debugger none) and traces every instruction of the drive's DOS processor, with the registers before
-- it, until the emulated second given. With the PET's IEEE-488 slot left at its default 4040, that 6502 is CPU 0,
-- the one tracelog writes to.
--
-- RETRO_CPU: the drive's CPU, 0 unless given (the PET's 4040), or a tag, such as :iec8:c1541:ucd5 for the VIC-20's
-- 1541.
-- RETRO_END: the emulated second to stop at.
-- RETRO_OUT: the trace file; each line is "a x y p sp|PC: disassembly".
-- RETRO_TYPE: text to type at the computer once RETRO_TYPE_AT seconds have passed; "\n" is RETURN. Optional.

local output = (os.getenv("RETRO_OUT") or "trace.log"):gsub("\\", "/")
-- MAME's time is whole seconds and attoseconds, so times are compared as attotimes: time.seconds drops a
-- fraction such as 2.5, and time:as_double() rounds a frame at 2.999999999999999880 up to 3, a frame early.
local finish = emu.attotime.from_double(tonumber(os.getenv("RETRO_END") or "1"))
local text = os.getenv("RETRO_TYPE")
local typeAt = emu.attotime.from_double(tonumber(os.getenv("RETRO_TYPE_AT") or "0"))
local cpu = os.getenv("RETRO_CPU") or "0"
local debugger = manager.machine.debugger
-- tracelog writes to the trace of the CPU the debugger shows, so that is the drive's.
if cpu ~= "0" then debugger.visible_cpu = manager.machine.devices[cpu] end
debugger:command('trace ' .. output .. ',' .. cpu .. ',noloop,{tracelog "%02x %02x %02x %02x %02x|",a,x,y,p,sp}')
debugger.execution_state = "run"

local typed = false
subscription = emu.add_machine_frame_notifier(function()
  local now = manager.machine.time
  if text and not typed and now >= typeAt then
    manager.machine.natkeyboard:post((text:gsub("\\n", "\n")))
    typed = true
  end

  if now >= finish then
    debugger:command("trace off," .. cpu)
    manager.machine:exit()
  end
end)
