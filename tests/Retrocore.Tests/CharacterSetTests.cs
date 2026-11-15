// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Machines;
using Retrocore.Machines.Apple1;
using Retrocore.Machines.Apple3;
using Retrocore.Machines.Coco;
using System.Runtime.InteropServices;

namespace Retrocore.Tests;

/// <summary>
///  The character sets Retrocore Memory draws its text column with, on the Apple-1, the Apple III and the CoCo 3:
///  each draws a byte as the machine's screen does.
/// </summary>
[TestClass]
public class CharacterSetTests
{
    /// <summary>
    ///  The Apple-1 draws a byte as its terminal shows it written to port B: the 2513's character, bit 7 and the
    ///  lowercase bit ignored, and control characters blank.
    /// </summary>
    [TestMethod]
    public void Apple1DrawsTheTerminalsCharacters()
    {
        Apple1Machine machine = new(new(), Apple1MachineTests.Roms);
        ICharacterSet characters = machine.Terminal;
        ReadOnlySpan<byte> generator = Apple1MachineTests.Roms.CharacterGenerator.Span;
        (characters.CharacterWidth, characters.CharacterHeight).Should().Be((7, 8));

        // A is the 2513's character 1.
        bool lit = false;
        for (int line = 0; line < 8; line++)
        {
            for (int pixel = 0; pixel < 7; pixel++)
            {
                bool expected = pixel is >= 1 and <= 5 && (generator[(1 << 3) | line] & (0x10 >> (pixel - 1))) != 0;
                characters.IsLit(0xC1, line, pixel, flashed: false).Should().Be(expected, $"line {line}, pixel {pixel}");
                characters.IsLit(0x41, line, pixel, flashed: false).Should().Be(expected, "bit 7 is ignored");
                characters.IsLit(0xE1, line, pixel, flashed: false).Should().Be(expected, "lowercase shows as uppercase");
                characters.IsLit(0x8D, line, pixel, flashed: false).Should().BeFalse("Return draws nothing");
                lit |= expected;
            }
        }

        lit.Should().BeTrue();
        characters.Character(0xC1).Should().Be('A');
        characters.Character(0xE1).Should().Be('A');
        characters.Character(0xA0).Should().Be(' ');
        characters.Character(0x8D).Should().Be('\0');
    }

    /// <summary>
    ///  The Apple III draws from the character set in RAM: $80-$FF normal, $00-$7F inverse, and a glyph row with
    ///  bit 7 set flashing, normal in the flashed phase.
    /// </summary>
    [TestMethod]
    public void Apple3DrawsFromItsCharacterRam()
    {
        byte[] rom = new byte[0x1000];
        rom[0xFFD] = 0xF0;
        Apple3Machine machine = new(new Apple3Roms(rom, new byte[256]));
        ICharacterSet characters = machine.Video;
        machine.Video.CharacterRam[0x41 * 8] = 0b0000_0001;     // A, row 0: the leftmost dot
        machine.Video.CharacterRam[0x42 * 8] = 0b1000_0001;     // B, row 0: the leftmost dot, flashing
        (characters.CharacterWidth, characters.CharacterHeight).Should().Be((7, 8));

        characters.IsLit(0xC1, 0, 0, flashed: false).Should().BeTrue();
        characters.IsLit(0xC1, 0, 1, flashed: false).Should().BeFalse();
        characters.IsLit(0x41, 0, 0, flashed: false).Should().BeFalse("$00-$7F are inverse");
        characters.IsLit(0x41, 0, 1, flashed: true).Should().BeTrue("inverse does not flash");
        characters.IsLit(0x42, 0, 0, flashed: false).Should().BeFalse("a flashing character shows inverse");
        characters.IsLit(0x42, 0, 0, flashed: true).Should().BeTrue("and then normal");
        characters.IsLit(0xC2, 0, 0, flashed: false).Should().BeTrue("$80-$FF do not flash");
        characters.Character(0xC1).Should().Be('A');
        characters.Character(0x41).Should().Be('A');
        characters.Character(0x8D).Should().Be('\0');
    }

    /// <summary>
    ///  The CoCo 3 draws as its current mode does: the compatible mode's VDG characters at power on, then after
    ///  WIDTH 40 the GIME's text, as its screen shows the O of OK.
    /// </summary>
    [TestMethod]
    public void Coco3FollowsItsTextMode()
    {
        CocoMachine machine = new(
            new() { Model = CocoModel.Coco3, RgbMonitor = true },
            CocoTestRoms.Load(CocoModel.Coco3));

        machine.Run(3 * (ulong)CocoTiming.ClockHertz);
        ICharacterSet characters = machine.Bus.Coco3Video;
        (characters.CharacterWidth, characters.CharacterHeight).Should().Be((8, 12));
        characters.Character(0x4F).Should().Be('O');
        characters.Character(0x0F).Should().Be('O', "inverse, without the GIME's lowercase on");
        characters.Character(0x8F).Should().Be('\0', "semigraphics");
        characters.IsLit(0x80 | 0x08, 0, 0, flashed: false).Should().BeTrue("the top left element");
        characters.IsLit(0x80 | 0x08, 0, 4, flashed: false).Should().BeFalse();
        characters.IsLit(0x80 | 0x08, 8, 0, flashed: false).Should().BeFalse();

        // With the GIME's lowercase on, codes 0 to 31 without the inverse bit are what its font draws there.
        SetVideoMode(machine, 0x10);
        string lowercase = new([.. Enumerable.Range(0, 32).Select(code => characters.Character((byte)code))]);
        lowercase.Should().Be("^abcdefghijklmnopqrstuvwxyz{|}~_");
        characters.Character(0x41).Should().Be('A', "the inverse bit keeps uppercase");
        SetVideoMode(machine, 0x00);

        CocoMachineTests.Type(machine, "width 40\r");
        (characters.CharacterWidth, characters.CharacterHeight).Should().Be((8, 8));
        characters.Character(0x4F).Should().Be('O');
        characters.Character(0x0D).Should().Be('\0');

        // The first row's first cell holds O of OK, each dot two wide: lit dots in one color, the rest in another.
        Coco3Video video = machine.Bus.Coco3Video;
        byte[] pixels = new byte[video.Width * video.Height * 4];
        video.Render(pixels, scanned: true);
        uint[] frame = MemoryMarshal.Cast<byte, uint>(pixels).ToArray();
        int top = 12 + ((225 - video.ActiveLines) / 2);
        HashSet<uint> on = [], off = [];
        for (int line = 0; line < 8; line++)
        {
            for (int dot = 0; dot < 8; dot++)
            {
                uint color = frame[((top + line) * video.Width) + 32 + (dot * 2)];
                (characters.IsLit(0x4F, line, dot, flashed: false) ? on : off).Add(color);
            }
        }

        on.Should().ContainSingle();
        off.Should().ContainSingle();
        on.Should().NotIntersectWith(off);
    }

    /// <summary>
    ///  The MC6847T1 draws codes 0 to 31 as its lowercase while GM0 is set, as copying, finding and typing read them.
    /// </summary>
    [TestMethod]
    public void TheT1sLowercaseIsWhatItDraws()
    {
        CocoMachine machine = CocoMachineTests.Create(CocoModel.Coco2, 13, 11, 64);
        machine.Run(2 * (ulong)CocoTiming.ClockHertz);
        ICharacterSet characters = machine.Bus.Video;
        SetVideoMode(machine, 0x10);
        string lowercase = new([.. Enumerable.Range(0, 32).Select(code => characters.Character((byte)code))]);
        lowercase.Should().Be("^abcdefghijklmnopqrstuvwxyz{|}~_");
    }

    // Writes PIA 1's port B, whose top bits are the VDG's mode, as the test of the T1's lowercase does.
    private static void SetVideoMode(CocoMachine machine, byte mode)
    {
        machine.Bus.Pia1.Write(3, (byte)(machine.Bus.Pia1.ControlB & ~0x04));
        machine.Bus.Pia1.Write(2, 0xF8);
        machine.Bus.Pia1.Write(3, (byte)(machine.Bus.Pia1.ControlB | 0x04));
        machine.Bus.Pia1.Write(2, mode);
    }
}
