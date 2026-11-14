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
    {
        Machine = new(new AltairConfiguration
        {
            RamKilobytes = 32,
            Console = console,
            Switches = switches,
            UpperCase = true
        });

        byte[] image = AltairBasicTests.Image(name);
        for (int index = 0; index < image.Length; index++) { Machine.Bus.Write((ushort)index, image[index]); }
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
        Machine.Run(AltairTiming.ClockHertz / 2);
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
