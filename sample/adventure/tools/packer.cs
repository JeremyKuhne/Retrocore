#!/usr/bin/env dotnet
// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

// Packs a ScottFree .dat game into the adventure engine's binary format, and plays a packed game from a transcript
// with the C# reference engine, which the 6502 engine's tests compare against.
//
//   dotnet run packer.cs -- pack game.dat game.bin
//   dotnet run packer.cs -- play game.bin commands.txt [--echo] [--columns 40] [--expect expected.out]
//
// pack prints the size of each part of the packed game. play writes what the engine sends to the screen, with each
// command after its prompt when --echo is given; with --expect it compares that with a file instead, and fails when
// they differ.

#:include DatReader.cs
#:include ScottFreeGame.cs
#:include GameAction.cs
#:include GameCondition.cs
#:include GameRoom.cs
#:include GameItem.cs
#:include TextCompressor.cs
#:include PackedHeader.cs
#:include GamePacker.cs
#:include WrappedOutput.cs
#:include ReferenceEngine.cs

using System.Globalization;

const int DefaultColumns = 40;

try
{
    return args switch
    {
        ["pack", string input, string output] => Pack(input, output),
        ["play", string packed, string commands, .. string[] options] => Play(packed, commands, options),
        _ => Usage()
    };
}
catch (Exception exception) when (exception is InvalidDataException or IOException or UnauthorizedAccessException)
{
    Console.Error.WriteLine(exception.Message);
    return 1;
}

static int Usage()
{
    Console.Error.WriteLine("Usage: dotnet run packer.cs -- pack game.dat game.bin");
    Console.Error.WriteLine("       dotnet run packer.cs -- play game.bin commands.txt [--echo] [--columns 40] [--expect expected.out]");
    return 2;
}

static int Pack(string input, string output)
{
    ScottFreeGame game = ScottFreeGame.Parse(File.ReadAllText(input));
    (byte[] bytes, List<(string Part, int Size)> sizes, List<string> warnings) = GamePacker.Pack(game);
    foreach (string warning in warnings) { Console.Error.WriteLine($"Warning: {warning}"); }
    if (Path.GetDirectoryName(Path.GetFullPath(output)) is { } folder) { Directory.CreateDirectory(folder); }
    File.WriteAllBytes(output, bytes);
    foreach ((string part, int size) in sizes)
    {
        Console.WriteLine(string.Create(CultureInfo.InvariantCulture, $"{part,-18} {size,6}"));
    }

    return 0;
}

static int Play(string packed, string commands, string[] options)
{
    bool echo = false;
    int columns = DefaultColumns;
    string? expected = null;
    for (int index = 0; index < options.Length; index++)
    {
        switch (options[index])
        {
            case "--echo":
                echo = true;
                break;
            case "--columns" when index + 1 < options.Length:
                if (!int.TryParse(options[++index], CultureInfo.InvariantCulture, out columns) || columns < 2)
                {
                    return Usage();
                }

                break;
            case "--expect" when index + 1 < options.Length:
                expected = options[++index];
                break;
            default:
                return Usage();
        }
    }

    string[] lines = File.ReadAllLines(commands);
    string transcript = new ReferenceEngine(File.ReadAllBytes(packed), columns).Play(lines, echo);
    if (expected is null)
    {
        Console.Out.Write(transcript);
        return 0;
    }

    string wanted = File.ReadAllText(expected).ReplaceLineEndings("\n");
    if (wanted == transcript) { return 0; }
    int at = 0;
    while (at < Math.Min(wanted.Length, transcript.Length) && wanted[at] == transcript[at]) { at++; }
    int line = wanted.AsSpan(0, at).Count('\n') + 1;
    Console.Error.WriteLine($"The transcript differs from {expected} at line {line}:");
    Console.Error.WriteLine(transcript);
    return 1;
}
