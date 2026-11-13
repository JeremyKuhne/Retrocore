// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Cpu.M6809;

public sealed partial class M6809Processor<TBus>
{
    private void DecodePage0(byte opcode)
    {
        _state.Page = 0;
        _state.Opcode = opcode;
        if (opcode is 0x10 or 0x11)
        {
            _state.Page = opcode;
            _state.Operation = M6809Operation.DecodePage;
            return;
        }

        DecodeOpcode(opcode);
    }

    // Every page-0 opcode is defined on the MC6809, the undocumented ones included.
    private void DecodeOpcode(byte opcode)
    {
        switch (opcode >> 4)
        {
            case 0x0:
                DecodeUnaryMemory(opcode, M6809AddressPhase.DirectFetch);
                return;
            case 0x1:
                DecodeMiscGroup1(opcode);
                return;
            case 0x2:
                _state.Operation = M6809Operation.BranchShort;
                return;
            case 0x3:
                DecodeMiscGroup3(opcode);
                return;
            case 0x4:
            case 0x5:
                // Every low nibble is an accumulator operation; $x1, $x2, $x5, $xB and $xE are undocumented.
                _state.Operation = M6809Operation.Inherent;
                _state.Remaining = 1;
                return;
            case 0x6:
                DecodeUnaryMemory(opcode, M6809AddressPhase.IndexedPostbyte);
                return;
            case 0x7:
                DecodeUnaryMemory(opcode, M6809AddressPhase.ExtendedHigh);
                return;
            default:
                DecodeArithmeticGroup(opcode);
                return;
        }
    }

    private void DecodePrefixed(byte page, byte opcode)
    {
        _state.Opcode = opcode;

        // Only the first prefix counts; each further one costs a cycle, and no interrupt is taken between them.
        if (opcode is 0x10 or 0x11)
        {
            _state.Operation = M6809Operation.DecodePage;
            return;
        }

        if (page == 0x10)
        {
            switch (opcode)
            {
                case >= 0x20 and <= 0x2F:
                    _state.Operation = M6809Operation.BranchLong;
                    return;
                case 0x3E:
                case 0x3F:
                    // $3E is the undocumented XSWI2: SWI2 without setting E in the stacked CC.
                    _state.Effective = 0xFFF4;
                    _state.Operation = M6809Operation.SoftwareInterrupt;
                    return;
                case 0x83 or 0x8C or 0xC3:
                    _state.Operation = M6809Operation.Immediate16Alu;
                    return;
                case 0x87 or 0xC7:
                    _state.Operation = M6809Operation.StoreImmediate8;
                    return;
                case 0x8E or 0xCE:
                    _state.Operation = M6809Operation.Immediate16Load;
                    return;
                case 0x8F or 0xCF:
                    _state.Operation = M6809Operation.StoreImmediate16;
                    return;
                case 0x93 or 0x9C or 0xD3:
                    BeginAddressed(M6809AddressPhase.DirectFetch, M6809Operation.MemoryAlu16);
                    return;
                case 0xA3 or 0xAC or 0xE3:
                    BeginAddressed(M6809AddressPhase.IndexedPostbyte, M6809Operation.MemoryAlu16);
                    return;
                case 0xB3 or 0xBC or 0xF3:
                    BeginAddressed(M6809AddressPhase.ExtendedHigh, M6809Operation.MemoryAlu16);
                    return;
                case 0x9E or 0xDE:
                    BeginAddressed(M6809AddressPhase.DirectFetch, M6809Operation.MemoryRead16);
                    return;
                case 0xAE or 0xEE:
                    BeginAddressed(M6809AddressPhase.IndexedPostbyte, M6809Operation.MemoryRead16);
                    return;
                case 0xBE or 0xFE:
                    BeginAddressed(M6809AddressPhase.ExtendedHigh, M6809Operation.MemoryRead16);
                    return;
                case 0x9F or 0xDF:
                    BeginAddressed(M6809AddressPhase.DirectFetch, M6809Operation.MemoryWrite16);
                    return;
                case 0xAF or 0xEF:
                    BeginAddressed(M6809AddressPhase.IndexedPostbyte, M6809Operation.MemoryWrite16);
                    return;
                case 0xBF or 0xFF:
                    BeginAddressed(M6809AddressPhase.ExtendedHigh, M6809Operation.MemoryWrite16);
                    return;
                default:
                    DecodeWithoutPrefix(opcode);
                    return;
            }
        }

        // Page $11
        switch (opcode)
        {
            case 0x3E:
                // The undocumented XFIRQ: the whole state stacked, CC without E, through the FIRQ vector.
                _state.Effective = 0xFFF6;
                _state.Operation = M6809Operation.SoftwareInterrupt;
                return;
            case 0x3F:
                _state.Effective = 0xFFF2;
                _state.Operation = M6809Operation.SoftwareInterrupt;
                return;
            case 0x83 or 0x8C or 0xC3:
                _state.Operation = M6809Operation.Immediate16Alu;
                return;
            case 0x87 or 0xC7:
                _state.Operation = M6809Operation.StoreImmediate8;
                return;
            case 0x8F or 0xCF:
                _state.Operation = M6809Operation.StoreImmediate16;
                return;
            case 0x93 or 0x9C or 0xD3:
                BeginAddressed(M6809AddressPhase.DirectFetch, M6809Operation.MemoryAlu16);
                return;
            case 0xA3 or 0xAC or 0xE3:
                BeginAddressed(M6809AddressPhase.IndexedPostbyte, M6809Operation.MemoryAlu16);
                return;
            case 0xB3 or 0xBC or 0xF3:
                BeginAddressed(M6809AddressPhase.ExtendedHigh, M6809Operation.MemoryAlu16);
                return;
            default:
                DecodeWithoutPrefix(opcode);
                return;
        }
    }

    // An opcode a prefix leaves undefined runs as on page 0, one cycle longer for the prefix.
    private void DecodeWithoutPrefix(byte opcode)
    {
        _state.Page = 0;
        DecodeOpcode(opcode);
    }

    private void DecodeUnaryMemory(byte opcode, M6809AddressPhase addressPhase)
    {
        switch (opcode & 0x0F)
        {
            case 0xD:
                BeginAddressed(addressPhase, M6809Operation.MemoryTest8);
                return;
            case 0xE:
                BeginAddressed(addressPhase, M6809Operation.Jump);
                return;
            default:
                // $x1, $x2, $x5 and $xB are the undocumented NEG, XNC, LSR and XDEC.
                BeginAddressed(addressPhase, M6809Operation.MemoryModify8);
                return;
        }
    }

    private void DecodeMiscGroup1(byte opcode)
    {
        switch (opcode)
        {
            case 0x12 or 0x19 or 0x1B or 0x1D:
                _state.Operation = M6809Operation.Inherent;
                _state.Remaining = 1;
                return;
            case 0x13:
                _state.Operation = M6809Operation.Inherent;
                _state.Remaining = 3;
                return;
            case 0x14 or 0x15:
                _state.Operation = M6809Operation.HaltAndCatchFire;
                return;
            case 0x16:
                _state.Operation = M6809Operation.BranchLong;
                return;
            case 0x17:
                _state.Operation = M6809Operation.BranchSubroutineLong;
                return;
            case 0x18:
                _state.Operation = M6809Operation.ShiftConditionCodes;
                return;
            case 0x1A or 0x1C:
                _state.Operation = M6809Operation.Immediate8;
                return;
            default:
                // $1E and $1F; the prefixes $10 and $11 never reach here.
                _state.Operation = M6809Operation.TransferExchange;
                return;
        }
    }

    private void DecodeMiscGroup3(byte opcode)
    {
        switch (opcode)
        {
            case 0x30 or 0x31 or 0x32 or 0x33:
                BeginAddressed(M6809AddressPhase.IndexedPostbyte, M6809Operation.LoadEffectiveAddress);
                return;
            case 0x34 or 0x36:
                _state.Operation = M6809Operation.StackPush;
                return;
            case 0x35 or 0x37:
                _state.Operation = M6809Operation.StackPull;
                return;
            case 0x38:
                // The undocumented XANDCC: ANDCC with one more cycle.
                _state.Operation = M6809Operation.Immediate8;
                return;
            case 0x39:
                _state.Operation = M6809Operation.ReturnSubroutine;
                return;
            case 0x3A:
                _state.Operation = M6809Operation.Inherent;
                _state.Remaining = 2;
                return;
            case 0x3B:
                _state.Operation = M6809Operation.ReturnInterrupt;
                return;
            case 0x3C:
                _state.Operation = M6809Operation.Cwai;
                return;
            case 0x3D:
                _state.Operation = M6809Operation.Inherent;
                _state.Remaining = 10;
                return;
            case 0x3E:
                // The undocumented XRES: SWI through the reset vector, without setting E, I or F.
                _state.Effective = 0xFFFE;
                _state.Operation = M6809Operation.SoftwareInterrupt;
                return;
            default:
                _state.Effective = 0xFFFA;
                _state.Operation = M6809Operation.SoftwareInterrupt;
                return;
        }
    }

    private void DecodeArithmeticGroup(byte opcode)
    {
        int high = opcode >> 4;
        int low = opcode & 0x0F;
        bool groupB = high >= 0xC;
        bool immediate = high is 0x8 or 0xC;

        if (immediate)
        {
            switch (low)
            {
                case 0x3:
                    _state.Operation = M6809Operation.Immediate16Alu;
                    return;
                case 0x7:
                    _state.Operation = M6809Operation.StoreImmediate8;
                    return;
                case 0xC:
                    _state.Operation = groupB ? M6809Operation.Immediate16Load : M6809Operation.Immediate16Alu;
                    return;
                case 0xD:
                    // $8D is BSR; $CD is the undocumented halt and catch fire.
                    _state.Operation = groupB
                        ? M6809Operation.HaltAndCatchFire
                        : M6809Operation.BranchSubroutineShort;

                    return;
                case 0xE:
                    _state.Operation = M6809Operation.Immediate16Load;
                    return;
                case 0xF:
                    _state.Operation = M6809Operation.StoreImmediate16;
                    return;
                default:
                    _state.Operation = M6809Operation.Immediate8;
                    return;
            }
        }

        M6809AddressPhase phase = high is 0x9 or 0xD
            ? M6809AddressPhase.DirectFetch
            : high is 0xA or 0xE
                ? M6809AddressPhase.IndexedPostbyte
                : M6809AddressPhase.ExtendedHigh;

        M6809Operation operation = low switch
        {
            0x3 => M6809Operation.MemoryAlu16,
            0x7 => M6809Operation.MemoryWrite8,
            0xC => groupB ? M6809Operation.MemoryRead16 : M6809Operation.MemoryAlu16,
            0xD => groupB ? M6809Operation.MemoryWrite16 : M6809Operation.JumpSubroutine,
            0xE => M6809Operation.MemoryRead16,
            0xF => M6809Operation.MemoryWrite16,
            _ => M6809Operation.MemoryRead8
        };

        BeginAddressed(phase, operation);
    }

    private void BeginAddressed(M6809AddressPhase addressPhase, M6809Operation operation)
    {
        _state.AddressPhase = addressPhase;
        _state.Operation = operation;
    }
}
