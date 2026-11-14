-- Copyright (c) 2025 Jeremy W Kuhne
-- SPDX-License-Identifier: MIT
-- See LICENSE file in the project root for full license information
--
-- MAME autoboot script for the SoftCard oracles (Apple2SoftCardOracleTests, SoftCard3OracleTests). It needs MAME's
-- debugger (-debug, with -debugger none) and traces every instruction a SoftCard's Z80 runs, with the registers
-- before it, until the emulated second given.
--
-- RETRO_END: the emulated second to stop at.
-- RETRO_OUT: the trace file; each line is "af bc de hl ix iy sp|PC: disassembly".
-- RETRO_CPU: the Z80's tag, ":sl4:softcard:z80" if not set.

local output = (os.getenv("RETRO_OUT") or "trace.log"):gsub("\\", "/")
local finish = tonumber(os.getenv("RETRO_END") or "1")
local cpu = os.getenv("RETRO_CPU") or ":sl4:softcard:z80"
local debugger = manager.machine.debugger
debugger:command('trace ' .. output .. ',' .. cpu ..
  ',noloop,{tracelog "%04x %04x %04x %04x %04x %04x %04x|",af,bc,de,hl,ix,iy,sp}')
debugger.execution_state = "run"

subscription = emu.add_machine_frame_notifier(function()
  if manager.machine.time.seconds >= finish then
    debugger:command("trace off," .. cpu)
    manager.machine:exit()
  end
end)
