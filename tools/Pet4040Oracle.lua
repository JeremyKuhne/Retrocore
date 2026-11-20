-- Copyright (c) 2025 Jeremy W Kuhne
-- SPDX-License-Identifier: MIT
-- See LICENSE file in the project root for full license information
--
-- MAME autoboot script for the 4040 drive oracle (Pet4040OracleTests). It needs MAME's debugger (-debug, with
-- -debugger none) and traces every instruction of the drive's DOS processor, with the registers before it, until the
-- emulated second given. With the PET's IEEE-488 slot left at its default 4040, that 6502 is CPU 0, the one
-- tracelog writes to.
--
-- RETRO_END: the emulated second to stop at.
-- RETRO_OUT: the trace file; each line is "a x y p sp|PC: disassembly".
-- RETRO_TYPE: text to type at the PET once RETRO_TYPE_AT seconds have passed; "\n" is RETURN. Optional.

local output = (os.getenv("RETRO_OUT") or "trace.log"):gsub("\\", "/")
local finish = tonumber(os.getenv("RETRO_END") or "1")
local text = os.getenv("RETRO_TYPE")
local typeAt = tonumber(os.getenv("RETRO_TYPE_AT") or "0")
local debugger = manager.machine.debugger
debugger:command('trace ' .. output .. ',0,noloop,{tracelog "%02x %02x %02x %02x %02x|",a,x,y,p,sp}')
debugger.execution_state = "run"

local typed = false
subscription = emu.add_machine_frame_notifier(function()
  local now = manager.machine.time.seconds
  if text and not typed and now >= typeAt then
    manager.machine.natkeyboard:post((text:gsub("\\n", "\n")))
    typed = true
  end

  if now >= finish then
    debugger:command("trace off,0")
    manager.machine:exit()
  end
end)
