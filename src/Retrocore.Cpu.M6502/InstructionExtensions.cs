// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using System.ComponentModel;

namespace Retrocore.Cpu.M6502;

/// <summary>
///  Extension members for <see cref="Instruction"/>.
/// </summary>
public static class InstructionExtensions
{
    private static readonly Dictionary<Instruction, string> s_instructionSummary = new()
    {
        { Instruction.ADC, "ADd memory to accumulator with Carry" },
        { Instruction.AND, "\"AND\" memory with accumulator" },
        { Instruction.ASL, "Arithmetic Shift one bit Left, memory or accumulator" },
        { Instruction.BBR, "Branch on Bit Reset" },
        { Instruction.BBS, "Branch of Bit Set" },
        { Instruction.BCC, "Branch on Carry Clear(Pc= 0)" },
        { Instruction.BCS, "Branch on Carry Set(Pc= 1)" },
        { Instruction.BEQ, "Branch if EQual(Pz= 1)" },
        { Instruction.BIT, "BIt Test" },
        { Instruction.BMI, "Branch if result MInus(Pn= 1)" },
        { Instruction.BNE, "Branch if Not Equal(Pz= 0)" },
        { Instruction.BPL, "Branch if result PLus(Pn= 0)" },
        { Instruction.BRA, "BRanch Always" },
        { Instruction.BRK, "BReaK instruction" },
        { Instruction.BVC, "Branch on oVerflow Clear(Pv= 0)" },
        { Instruction.BVS, "Branch on oVerflow Set(Pv= 1)" },
        { Instruction.CLC, "CLear Cary flag" },
        { Instruction.CLD, "CLear Decimal mode" },
        { Instruction.CLI, "CLear Interrupt disable bit" },
        { Instruction.CLV, "CLear oVerflow flag" },
        { Instruction.CMP, "CoMPare memory and accumulator" },
        { Instruction.CPX, "ComPare memory and X register" },
        { Instruction.CPY, "ComPare memory and Y register" },
        { Instruction.DEC, "DECrement memory or accumulate by one" },
        { Instruction.DEX, "DEcrement X by one" },
        { Instruction.DEY, "DEcrement Y by one" },
        { Instruction.EOR, "\"Exclusive OR\" memory with accumulate" },
        { Instruction.INC, "INCrement memory or accumulate by one" },
        { Instruction.INX, "INcrement X register by one" },
        { Instruction.INY, "INcrement Y register by one" },
        { Instruction.JMP, "JuMP to new location" },
        { Instruction.JSR, "Jump to new location Saving Return(Jump to SubRoutine)" },
        { Instruction.LDA, "LoaD Accumulator with memory" },
        { Instruction.LDX, "LoaD the X register with memory" },
        { Instruction.LDY, "LoaD the Y register with memory" },
        { Instruction.LSR, "Logical Shift one bit Right memory or accumulator" },
        { Instruction.NOP, "No OPeration" },
        { Instruction.ORA, "\"OR\" memory with Accumulator" },
        { Instruction.PHA, "PusH Accumulator on stack" },
        { Instruction.PHP, "PusH Processor status on stack" },
        { Instruction.PHX, "PusH X register on stack" },
        { Instruction.PHY, "PusH Y register on stack" },
        { Instruction.PLA, "PuLl Accumulator from stack" },
        { Instruction.PLP, "PuLl Processor status from stack" },
        { Instruction.PLX, "PuLl X register from stack" },
        { Instruction.PLY, "PuLl Y register from stack" },
        { Instruction.RMB, "Reset Memory Bit" },
        { Instruction.ROL, "ROtate one bit Left memory or accumulator" },
        { Instruction.ROR, "ROtate one bit Right memory or accumulator" },
        { Instruction.RTI, "ReTurn from Interrupt" },
        { Instruction.RTS, "ReTurn from Subroutine" },
        { Instruction.SBC, "SuBtract memory from accumulator with borrow(Carry bit)" },
        { Instruction.SEC, "SEt Carry" },
        { Instruction.SED, "SEt Decimal mode" },
        { Instruction.SEI, "SEt Interrupt disable status" },
        { Instruction.SMB, "Set Memory Bit" },
        { Instruction.STA, "STore Accumulator in memory" },
        { Instruction.STP, "SToP mode" },
        { Instruction.STX, "STore the X register in memory" },
        { Instruction.STY, "STore the Y register in memory" },
        { Instruction.STZ, "STore Zero in memory" },
        { Instruction.TAX, "Transfer the Accumulator to the X register" },
        { Instruction.TAY, "Transfer the Accumulator to the Y register" },
        { Instruction.TRB, "Test and Reset memory Bit" },
        { Instruction.TSB, "Test and Set memory Bit" },
        { Instruction.TSX, "Transfer the Stack pointer to the X register" },
        { Instruction.TXA, "Transfer the X register to the Accumulator" },
        { Instruction.TXS, "Transfer the X register to the Stack pointer register" },
        { Instruction.TYA, "Transfer Y register to the Accumulator" },
        { Instruction.WAI, "WAit for Interrupt" },
        { Instruction.JAM, "JAM processor until reset" },
        { Instruction.SLO, "Shift Left then OR" },
        { Instruction.RLA, "Rotate Left then AND" },
        { Instruction.SRE, "Shift Right then Exclusive OR" },
        { Instruction.RRA, "Rotate Right then Add" },
        { Instruction.SAX, "Store Accumulator AND X" },
        { Instruction.LAX, "Load Accumulator and X" },
        { Instruction.DCP, "Decrement then Compare" },
        { Instruction.ISC, "Increment then Subtract" },
        { Instruction.ANC, "AND and copy Negative to Carry" },
        { Instruction.ALR, "AND then shift Right" },
        { Instruction.ARR, "AND then Rotate Right" },
        { Instruction.XAA, "Unstable accumulator AND X AND immediate" },
        { Instruction.AXS, "Subtract immediate from Accumulator AND X" },
        { Instruction.AHX, "Unstable masked store of Accumulator AND X" },
        { Instruction.SHX, "Unstable masked Store of X" },
        { Instruction.SHY, "Unstable masked Store of Y" },
        { Instruction.TAS, "Set stack pointer and perform masked store" },
        { Instruction.LAS, "Load Accumulator, X, and Stack pointer" }
    };

    /// <param name="instruction">The instruction.</param>
    extension(Instruction instruction)
    {
        /// <summary>
        ///  Gets the short description of the instruction.
        /// </summary>
        /// <exception cref="InvalidEnumArgumentException">The instruction wasn't a valid value.</exception>
        public string Summary
        {
            get
            {
                if (!s_instructionSummary.TryGetValue(instruction, out string? summary))
                {
                    ThrowHelper.ThrowInvalidEnum(instruction);
                }

                return summary;
            }
        }
    }
}
