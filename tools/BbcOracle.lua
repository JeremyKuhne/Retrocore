-- Copyright (c) 2025 Jeremy W Kuhne
-- SPDX-License-Identifier: MIT
-- See LICENSE file in the project root for full license information
--
-- MAME autoboot script for the BBC Micro oracle (BbcOracleTests). It needs MAME's debugger (-debug, with
-- -debugger none) and traces every instruction of the main 6502, with the registers before it, until the emulated
-- second given.
--
-- RETRO_END: the emulated second to stop at.
-- RETRO_OUT: the trace file; each line is "a x y p sp|PC: disassembly".
-- RETRO_KEYS: optional text to type, with \r for RETURN, starting at the emulated second RETRO_KEYS_AT.

local output = (os.getenv("RETRO_OUT") or "trace.log"):gsub("\\", "/")
local finish = tonumber(os.getenv("RETRO_END") or "1")
local keys = os.getenv("RETRO_KEYS")
local keysAt = tonumber(os.getenv("RETRO_KEYS_AT") or "0")
local typed = false
local debugger = manager.machine.debugger
debugger:command('trace ' .. output .. ',maincpu,noloop,{tracelog "%02x %02x %02x %02x %02x|",a,x,y,p,sp}')
debugger.execution_state = "run"

subscription = emu.add_machine_frame_notifier(function()
  local now = manager.machine.time.seconds
  if keys and not typed and now >= keysAt then
    manager.machine.natkeyboard:post(keys:gsub("\\r", "\r"))
    typed = true
  end

  if now >= finish then
    debugger:command("trace off,maincpu")
    manager.machine:exit()
  end
end)
