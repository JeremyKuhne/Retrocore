// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using System.Text;
using Retrocore.Machines.Altair;
using Retrocore.Machines.Chips;

namespace Retrocore.Tests;

/// <summary>
///  An Altair BASIC image loaded at $0000 in a 32 KB Altair, with what the terminal is sent kept as text.
/// </summary>
internal sealed class AltairBasicSession
{
    private readonly StringBuilder _output = new();

    /// <summary>
    ///  Loads an image.
    /// </summary>
    /// <param name="name">The image's file name in the external test data.</param>
    /// <param name="console">The board the terminal is on.</param>
    /// <param name="switches">The front panel's switches, whose high 8 BASIC reads to pick its terminal.</param>
    internal AltairBasicSession(string name, AltairConsole console, ushort switches)
        : this(console, switches)
    {
        byte[] image = AltairBasicTests.Image(name);
        for (int index = 0; index < image.Length; index++) { Machine.Bus.Write((ushort)index, image[index]); }
    }

    private AltairBasicSession(AltairConsole console, ushort switches)
    {
        Machine = new(new AltairConfiguration
        {
            RamKilobytes = 32,
            Console = console,
            Switches = switches,
            UpperCase = true
        });

        ISerialLine line = console == AltairConsole.Sio
            ? Machine.Bus.Sio ?? throw new InvalidOperationException("The 88-SIO is missing.")
            : Machine.Bus.SerialA;

        Action<byte>? terminal = line.Transmitted;
        line.Transmitted = value =>
        {
            int code = value & 0x7F;
            if (code is 0x0A or (>= 0x20 and < 0x7F)) { _output.Append((char)code); }
            terminal?.Invoke(value);
        };
    }

    /// <summary>
    ///  Loads a MITS tape as an operator did: keys MITS's bootstrap for the 88-ACR in at $0000 with the front panel's
    ///  EXAMINE and DEPOSIT, puts the tape in, and runs until it has played. The bootstrap reads the tape's checksum
    ///  loader backwards into memory below the load address, skipping the leader, whose bytes are the load address's
    ///  low byte, then jumps to it; the checksum loader reads the rest and starts BASIC.
    /// </summary>
    /// <param name="tape">The tape's bytes.</param>
    /// <param name="loadAddress">
    ///  Where the checksum loader ends: $0FAE and $1FAE for 4K and 8K 3.2, $0FC2 and $1FC2 for 4K and 8K 4.0, and
    ///  $3FC2 for Extended BASIC.
    /// </param>
    /// <param name="console">The board the terminal is on.</param>
    /// <param name="switches">The front panel's switches: the checksum loader reads its device from them too.</param>
    /// <returns>The session, with BASIC asking its first question.</returns>
    internal static AltairBasicSession FromTape(byte[] tape, ushort loadAddress, AltairConsole console, ushort switches)
    {
        AltairBasicSession session = new(console, switches);
        AltairFrontPanel panel = session.Machine.FrontPanel;
        byte[] bootstrap =
        [
            0x21, (byte)loadAddress, (byte)(loadAddress >> 8),  // LXI H,load address
            0x31, 0x12, 0x00,                                   // LXI SP,$0012, where RET finds $0003
            0xDB, 0x06,                                         // IN $06
            0x0F,                                               // RRC: bit 0 low when a byte waits
            0xD8,                                               // RC
            0xDB, 0x07,                                         // IN $07
            0xBD,                                               // CMP L: a leader byte?
            0xC8,                                               // RZ
            0x2D,                                               // DCR L
            0x77,                                               // MOV M,A
            0xC0,                                               // RNZ
            0xE9,                                               // PCHL
            0x03, 0x00                                          // $0003, the loop
        ];

        panel.Switches = 0;
        panel.Examine();
        for (int index = 0; index < bootstrap.Length; index++)
        {
            panel.Switches = bootstrap[index];
            if (index == 0)
            {
                panel.Deposit();
            }
            else
            {
                panel.DepositNext();
            }
        }

        panel.Switches = switches;
        AltairCassette cassette = session.Machine.Bus.Cassette
            ?? throw new InvalidOperationException("The 88-ACR is missing.");

        cassette.Play(tape, "tape");
        int character = AltairTiming.CyclesPerCharacter(AltairBus.CassetteBaudRate);
        session.Machine.Run((ulong)(((long)tape.Length * character) + AltairTiming.ClockHertz));
        return session;
    }

    /// <summary>
    ///  Gets the machine.
    /// </summary>
    internal AltairMachine Machine { get; }

    /// <summary>
    ///  Gets what the terminal was sent since the last <see cref="Clear"/>, without carriage returns or nulls.
    /// </summary>
    internal string Output => _output.ToString();

    /// <summary>
    ///  Starts BASIC and answers the questions it starts with.
    /// </summary>
    /// <param name="answers">The answers, each typed as a line.</param>
    internal void Start(params string[] answers)
    {
        if (Machine.Processor.CycleCount == 0) { Machine.Run(AltairTiming.ClockHertz / 2); }
        foreach (string answer in answers) { Type(answer); }
    }

    /// <summary>
    ///  Forgets the output so far.
    /// </summary>
    internal void Clear() => _output.Clear();

    /// <summary>
    ///  Types a line and lets BASIC finish with it. BASIC reads keys while it prints, as its check for ^C, so a line
    ///  goes in only after the last one is done.
    /// </summary>
    /// <param name="text">The line, without its return.</param>
    /// <param name="seconds">The emulated seconds to run after it.</param>
    internal void Type(string text, double seconds = 0.5)
    {
        foreach (char key in text) { Machine.Terminal.Type((byte)key); }
        Machine.Terminal.Type(13);
        Machine.Run((ulong)(seconds * AltairTiming.ClockHertz));
    }
}
