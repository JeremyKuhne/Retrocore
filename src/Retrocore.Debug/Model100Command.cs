// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Basic;
using System.Text;
using System.Text.Json.Nodes;

namespace Retrocore.Debug;

/// <summary>
///  Lists, copies out, adds and removes the files in a Model 100's or Tandy 102's RAM image.
/// </summary>
/// <remarks>
///  <para>
///   The image is the fitted RAM from its first address to $FFFF, as the <c>trs80-model100</c> launch's
///   <c>ramImage</c> keeps it. <c>--model100 files image [--json]</c> lists the files the menu shows.
///   <c>--model100 extract image NAME output [--list]</c> writes one as the Model 100 holds it, or with
///   <c>--list</c> a <c>.BA</c> file as its listing. <c>--model100 add image file [NAME]</c> adds a host file (see
///   <see cref="FromHost"/>), replacing one of the same name, and <c>--model100 delete image NAME</c> removes one.
///  </para>
/// </remarks>
internal static class Model100Command
{
    private const string Usage =
        "Usage: --model100 files image [--json] | --model100 extract image NAME output [--list]"
            + " | --model100 add image file [NAME] | --model100 delete image NAME";

    /// <summary>
    ///  Runs the command.
    /// </summary>
    /// <param name="args">The arguments after <c>--model100</c>.</param>
    /// <returns>The process exit code.</returns>
    internal static int Run(string[] args)
    {
        try
        {
            return args switch
            {
                ["files", string image, .. string[] rest] => List(image, rest.Contains("--json")),
                ["extract", string image, string name, string output, .. string[] rest] => Extract(image, name, output, rest.Contains("--list")),
                ["add", string image, string file] => Add(image, file, name: null),
                ["add", string image, string file, string name] => Add(image, file, name),
                ["delete", string image, string name] => Change(image, files => files.Delete(name), $"Removed {name.ToUpperInvariant()}."),
                _ => Fail(Usage, code: 2)
            };
        }
        catch (ArgumentException exception)
        {
            return Fail(exception.ParamName is { } parameter ? exception.Message.Replace($" (Parameter '{parameter}')", "", StringComparison.Ordinal) : exception.Message);
        }
        catch (Exception exception) when (exception is InvalidDataException or IOException or InvalidOperationException)
        {
            return Fail(exception.Message);
        }
    }

    /// <summary>
    ///  Reads a host file as a Model 100 file: its name and its bytes as RAM holds them.
    /// </summary>
    /// <remarks>
    ///  <para>
    ///   A <c>.ba</c>, <c>.do</c> or <c>.co</c> file is the Model 100's own; a <c>.bas</c> file is BASIC text,
    ///   tokenized as Model 100 BASIC into a <c>.BA</c> file; a <c>.txt</c> file is text for a <c>.DO</c> file, its
    ///   lines ended with CR LF. The name is the file's own, without its extension, unless one is given.
    ///  </para>
    /// </remarks>
    /// <param name="path">The host file.</param>
    /// <param name="name">The name in RAM, with its extension; by default the host file's.</param>
    /// <returns>The name in RAM and the bytes.</returns>
    /// <exception cref="ArgumentException">The file is not one of these kinds, or its name does not fit.</exception>
    /// <exception cref="InvalidDataException">A BASIC program does not parse.</exception>
    internal static (string Name, byte[] Bytes) FromHost(string path, string? name = null)
    {
        string extension = Path.GetExtension(path).ToLowerInvariant();
        string stem = Path.GetFileNameWithoutExtension(path);
        if (extension == ".bas" && Path.GetExtension(stem).Length > 0)
        {
            // game.model100.bas names GAME.BA.
            stem = Path.GetFileNameWithoutExtension(stem);
        }

        (string kind, byte[] bytes) = extension switch
        {
            ".ba" or ".do" or ".co" => (extension[1..], File.ReadAllBytes(path)),
            ".bas" => ("ba", Tokenize(path)),
            ".txt" => ("do", Encoding.Latin1.GetBytes(File.ReadAllText(path).ReplaceLineEndings("\r\n"))),
            _ => throw new ArgumentException($"{path} is not a Model 100 file: give a .ba, .do, .co, .bas or .txt file.")
        };

        string full = name ?? $"{stem}.{kind}";
        Model100Files.ParseName(full);
        return (full.ToUpperInvariant(), bytes);
    }

    /// <summary>
    ///  Wraps a RAM image as the memory it fills, the top of the 64K space; below it reads $FF and takes no writes.
    /// </summary>
    /// <param name="ram">The image.</param>
    /// <returns>The memory.</returns>
    /// <exception cref="InvalidDataException">The image is not 8, 16, 24 or 32 KB.</exception>
    internal static IBasicMemory Memory(byte[] ram)
    {
        if (ram.Length is not (0x2000 or 0x4000 or 0x6000 or 0x8000))
        {
            throw new InvalidDataException($"A Model 100's RAM image is 8, 16, 24 or 32 KB; this one has {ram.Length} bytes.");
        }

        int start = 0x10000 - ram.Length;
        return new Model100RamImage(ram, start);
    }

    private static byte[] Tokenize(string path)
    {
        BasicParseResult parsed = BasicProgram.Parse(File.ReadAllText(path), BasicDialect.Model100, path);
        if (parsed.Program is not { } program)
        {
            throw new InvalidDataException(
                $"{path} does not parse: {string.Join("; ", parsed.Diagnostics.Select(diagnostic => diagnostic.Message))}");
        }

        return program.ToImage();
    }

    private static int List(string image, bool json)
    {
        Model100Files files = new(Memory(File.ReadAllBytes(image)));
        JsonArray entries = [];
        foreach (Model100File file in files.List())
        {
            int length = files.Read(file.Name).Length;
            if (json)
            {
                entries.Add((JsonNode)new JsonObject
                {
                    ["name"] = file.Name,
                    ["type"] = file.Type.ToString(),
                    ["address"] = file.Address,
                    ["length"] = length
                });

                continue;
            }

            Console.WriteLine($"{file.Name,-10} ${file.Address:X4} {length,6} bytes");
        }

        if (json) { Console.WriteLine(entries.ToJsonString()); }
        return 0;
    }

    private static int Extract(string image, string name, string output, bool list)
    {
        byte[] bytes = new Model100Files(Memory(File.ReadAllBytes(image))).Read(name);
        if (list)
        {
            if (Model100Files.ParseName(name).Type != Model100FileType.Basic)
            {
                return Fail("--list lists a .BA file.");
            }

            File.WriteAllText(output, BasicProgram.FromImage(BasicDialect.Model100, bytes).ToText(pragma: true));
            Console.WriteLine($"Wrote {name.ToUpperInvariant()}'s listing to {output}.");
            return 0;
        }

        File.WriteAllBytes(output, bytes);
        Console.WriteLine($"Wrote {name.ToUpperInvariant()}, {bytes.Length} bytes, to {output}.");
        return 0;
    }

    private static int Add(string image, string file, string? name)
    {
        (string full, byte[] bytes) = FromHost(file, name);
        return Change(image, files => files.Write(full, bytes), $"Added {full}, {bytes.Length} bytes.");
    }

    // Changes the image's files, writing it back only when the change succeeds.
    private static int Change(string image, Action<Model100Files> change, string done)
    {
        byte[] ram = File.ReadAllBytes(image);
        change(new Model100Files(Memory(ram)));
        string temporary = $"{image}.{Environment.ProcessId}.tmp";
        try
        {
            File.WriteAllBytes(temporary, ram);
            File.Move(temporary, image, overwrite: true);
        }
        finally
        {
            File.Delete(temporary);
        }

        Console.WriteLine(done);
        return 0;
    }

    private static int Fail(string message, int code = 1)
    {
        Console.Error.WriteLine(message);
        return code;
    }
}
