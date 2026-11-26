// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Machines.Apple1;

namespace Retrocore.Tests;

/// <summary>
///  The Woz Monitor hex writer: the text it writes, and that text typed at the emulated Monitor storing the bytes and
///  running them.
/// </summary>
[TestClass]
public sealed class WozMonitorHexTests
{
    // LDA #'H' | $80, JSR ECHO, LDA #'I' | $80, JSR ECHO, JMP GETLINE
    private static readonly byte[] s_hello = [0xA9, 0xC8, 0x20, 0xEF, 0xFF, 0xA9, 0xC9, 0x20, 0xEF, 0xFF, 0x4C, 0x1F, 0xFF];

    /// <summary>
    ///  Each line gives its address and up to eight bytes, and the last line runs the program.
    /// </summary>
    [TestMethod]
    public void WritesAddressedLinesThenTheRunLine()
    {
        string run = Lines("0300: A9 C8 20 EF FF A9 C9 20", "0308: EF FF 4C 1F FF", "0300R");
        WozMonitorHex.ToText(s_hello, 0x0300, entry: 0x0300).Should().Be(run);
        string noRun = Lines("0300: A9 C8 20 EF FF", "0305: A9 C9 20 EF FF", "030A: 4C 1F FF");
        WozMonitorHex.ToText(s_hello, 0x0300, entry: null, bytesPerLine: 5).Should().Be(noRun);
        WozMonitorHex.ToText([], 0x0300, entry: 0x0280).Should().Be(Lines("0280R"));
        WozMonitorHex.ToText([0x60], 0xFFFF, entry: null).Should().Be(Lines("FFFF: 60"));
    }

    /// <summary>
    ///  A line stays within the 127 keys the Monitor takes before Return, and the bytes stay within the address
    ///  space.
    /// </summary>
    [TestMethod]
    public void KeepsLinesWithinTheMonitorsBuffer()
    {
        byte[] bytes = new byte[100];
        string text = WozMonitorHex.ToText(bytes, 0x1000, entry: null, WozMonitorHex.MaxBytesPerLine);
        string[] lines = text.Split(WozMonitorHex.NewLine, StringSplitOptions.RemoveEmptyEntries);
        lines.Should().HaveCount(3);
        lines[0].Length.Should().Be(125, "within the 127 keys the Monitor takes");
        lines[1].Should().StartWith("1028:");
        lines[2].Should().StartWith("1050:");

        Action tooMany = () => WozMonitorHex.ToText(bytes, 0x1000, entry: null, WozMonitorHex.MaxBytesPerLine + 1);
        tooMany.Should().Throw<ArgumentOutOfRangeException>();
        Action none = () => WozMonitorHex.ToText(bytes, 0x1000, entry: null, 0);
        none.Should().Throw<ArgumentOutOfRangeException>();
        Action pastTheTop = () => WozMonitorHex.ToText([1, 2], 0xFFFF, entry: null);
        pastTheTop.Should().Throw<ArgumentOutOfRangeException>();
    }

    /// <summary>
    ///  Typed at the Monitor's prompt, the text stores a program and its data and runs the program.
    /// </summary>
    /// <param name="kilobytes">The RAM from <c>$0000</c>.</param>
    /// <param name="address">Where the program goes.</param>
    /// <param name="bytesPerLine">The bytes on each line.</param>
    [TestMethod]
    [DataRow(4, 0x0300, WozMonitorHex.DefaultBytesPerLine)]
    [DataRow(4, 0x0300, WozMonitorHex.MaxBytesPerLine)]
    [DataRow(32, 0x7000, WozMonitorHex.DefaultBytesPerLine)]
    public void TypedAtTheMonitorStoresAndRunsTheBytes(int kilobytes, int address, int bytesPerLine)
    {
        Apple1Machine machine = new(new() { RamKilobytes = kilobytes }, Apple1MachineTests.Roms);
        machine.Run(Apple1Timing.CyclesPerFrame * 4);

        // The program, then data after it that crosses a page.
        byte[] bytes = [.. s_hello, .. Enumerable.Range(0, 300).Select(value => (byte)((value * 37) + 11))];
        string text = WozMonitorHex.ToText(bytes, (ushort)address, entry: (ushort)address, bytesPerLine);

        Apple1MachineTests.TypeLine(machine, text.TrimEnd('\r', '\n'), seconds: 60);

        // A line past the Monitor's buffer would be dropped with a backslash, and its bytes with it.
        Enumerable.Range(address, bytes.Length).Select(at => machine.Bus.Peek((ushort)at)).Should().Equal(bytes);
        Screen(machine).Should().Contain($"{address:X4}: A9HI", "R shows the entry's first byte, then the program prints");
    }

    /// <summary>
    ///  The Monitor drops a line one byte longer than <see cref="WozMonitorHex.MaxBytesPerLine"/>, 128 keys, with a
    ///  backslash, so the limit is the Monitor's.
    /// </summary>
    [TestMethod]
    public void TheMonitorDropsALineOneByteLonger()
    {
        Apple1Machine machine = Boot();
        byte[] zeros = new byte[WozMonitorHex.MaxBytesPerLine];
        string longest = WozMonitorHex.ToText(zeros, 0x0300, entry: null, WozMonitorHex.MaxBytesPerLine).TrimEnd();
        string tooLong = longest + " 11";
        tooLong.Length.Should().Be(128);

        Apple1MachineTests.TypeLine(machine, tooLong, seconds: 10);
        machine.Bus.Peek(0x0300 + WozMonitorHex.MaxBytesPerLine).Should().Be(0x00, "the line never ran");
        Screen(machine).Skip(1).Should().Contain(line => line.EndsWith('\\'), "the Monitor drops the line with a backslash");

        Apple1MachineTests.TypeLine(machine, longest.Replace(" 00", " 22", StringComparison.Ordinal), seconds: 10);
        machine.Bus.Peek(0x0300 + WozMonitorHex.MaxBytesPerLine - 1).Should().Be(0x22, "the longest line stores");
    }

    /// <summary>
    ///  Sent as they are, the carriage return runs each line and the line feed after it is skipped.
    /// </summary>
    [TestMethod]
    public void TheMonitorTakesCarriageReturnAndLineFeed()
    {
        Apple1Machine machine = Boot();
        string text = WozMonitorHex.ToText(s_hello, 0x0300, entry: 0x0300, bytesPerLine: 4);
        text.Should().Contain("\r\n");
        foreach (char character in text) { machine.Keyboard.Type((byte)character); }
        machine.Keyboard.Pending.Should().Be(text.Length, "the carriage returns and line feeds are typed too");

        // An empty line after it, to wait until the Monitor has taken everything.
        Apple1MachineTests.TypeLine(machine, "", seconds: 20);
        Enumerable.Range(0x0300, s_hello.Length).Select(at => machine.Bus.Peek((ushort)at)).Should().Equal(s_hello);
        Screen(machine).Should().Contain("0300: A9HI");
        Screen(machine).Skip(1).Should().NotContain(line => line.Contains('\\'), "no line was dropped after the prompt");
    }

    private static Apple1Machine Boot()
    {
        Apple1Machine machine = new(new(), Apple1MachineTests.Roms);
        machine.Run(Apple1Timing.CyclesPerFrame * 4);
        return machine;
    }

    private static string[] Screen(Apple1Machine machine) =>
        [.. Enumerable.Range(0, Apple1Terminal.Rows).Select(row => machine.Terminal.Line(row).TrimEnd())];

    private static string Lines(params string[] lines) => string.Concat(lines.Select(line => line + WozMonitorHex.NewLine));
}
