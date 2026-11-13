// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Basic;

namespace Retrocore.Debug;

/// <summary>
///  Converts BASIC programs between their text form, tokenized files and Model I tapes.
/// </summary>
/// <remarks>
///  <para>
///   <c>--basic list program [--dialect applesoft|integer|level2|business] [--out file.bas]</c> lists a tokenized file or a
///   <c>.cas</c> tape. A listing written to a file without a dialect extension starts with a pragma naming it.
///  </para>
///  <para>
///   <c>--basic tokenize file.bas output [--dialect name] [--load-address $0801] [--cas name]</c> writes a
///   tokenized file, or a tape when the output ends in <c>.cas</c> or <c>--cas</c> gives the tape's one-letter name.
///  </para>
///  <para>
///   <c>--basic check file.bas [--dialect name]</c> reports the text's problems without writing anything.
///  </para>
///  <para>
///   <c>--basic renumber file.bas [--start 10] [--step 10] [--out file.bas] [--dialect name]</c> renumbers the lines
///   and every reference to them, in place unless <c>--out</c> names another file.
///  </para>
/// </remarks>
internal static class BasicCommand
{
    private const string Usage = """
        Usage: --basic list program [--dialect applesoft|integer|level2|business] [--out file.bas]
               --basic tokenize file.bas output [--dialect name] [--load-address $0801] [--cas name]
               --basic check file.bas [--dialect name]
               --basic renumber file.bas [--start 10] [--step 10] [--out file.bas] [--dialect name]
        """;

    /// <summary>
    ///  Runs the command.
    /// </summary>
    /// <param name="args">The arguments after <c>--basic</c>.</param>
    /// <returns>The process exit code: 0 on success, 1 when the input has errors, 2 for bad arguments.</returns>
    internal static int Run(string[] args)
    {
        int positional = args.Length > 0 && args[0] == "tokenize" ? 3 : 2;
        if (args.Length < positional || (args.Length - positional) % 2 != 0)
        {
            Console.Error.WriteLine(Usage);
            return 2;
        }

        Dictionary<string, string> options = new(StringComparer.OrdinalIgnoreCase);
        for (int index = positional; index < args.Length; index += 2) { options[args[index]] = args[index + 1]; }
        BasicDialect? dialect = null;
        if (options.TryGetValue("--dialect", out string? name) && (dialect = BasicDialect.FromName(name)) is null)
        {
            Console.Error.WriteLine($"'{name}' is not a BASIC dialect; use applesoft, integer, apple1, level2 or business.");
            return 2;
        }

        try
        {
            return args[0] switch
            {
                "list" => List(args[1], dialect, options.GetValueOrDefault("--out")),
                "tokenize" => Tokenize(args[1], args[2], dialect, options),
                "check" => Parse(args[1], dialect) is null ? 1 : 0,
                "renumber" => Renumber(args[1], dialect, options),
                _ => Fail(Usage, 2)
            };
        }
        catch (Exception exception) when (exception is InvalidDataException or IOException or ArgumentException or FormatException)
        {
            return Fail(exception.Message, 1);
        }
    }

    private static int List(string input, BasicDialect? dialect, string? output)
    {
        byte[] bytes = File.ReadAllBytes(input);
        BasicProgram program;
        if (input.EndsWith(".cas", StringComparison.OrdinalIgnoreCase))
        {
            program = BasicTape.Read(bytes, out _);
        }
        else if (dialect is null)
        {
            return Fail("A tokenized file does not say its dialect; give --dialect applesoft, integer, apple1, level2 or business.", 2);
        }
        else
        {
            program = BasicProgram.FromImage(dialect, bytes);
        }

        if (output is null)
        {
            Console.Write(program.ToText());
            return 0;
        }

        File.WriteAllText(output, program.ToText(pragma: BasicText.DialectOfPath(output) is null));
        return 0;
    }

    private static int Tokenize(string input, string output, BasicDialect? dialect, Dictionary<string, string> options)
    {
        if (Parse(input, dialect) is not { } program) { return 1; }
        string? tape = options.GetValueOrDefault("--cas");
        if (tape is null && output.EndsWith(".cas", StringComparison.OrdinalIgnoreCase))
        {
            tape = Path.GetFileName(output)[..1].ToUpperInvariant();
        }

        byte[] bytes = tape is { Length: 1 }
            ? BasicTape.Write(program, tape[0])
            : tape is null
                ? program.ToImage(options.TryGetValue("--load-address", out string? address) ? AssembleCommand.Address(address) : null)
                : throw new ArgumentException("--cas takes the tape's one-character name.");

        File.WriteAllBytes(output, bytes);
        return 0;
    }

    private static int Renumber(string input, BasicDialect? dialect, Dictionary<string, string> options)
    {
        int start = Number(options, "--start");
        int step = Number(options, "--step");
        string source = File.ReadAllText(input);
        (string? text, IReadOnlyList<BasicDiagnostic> diagnostics) = BasicRenumber.Renumber(source, start, step, dialect, input);
        foreach (BasicDiagnostic diagnostic in diagnostics)
        {
            Console.Error.WriteLine($"{input}({diagnostic.Line + 1}): {diagnostic.Message}");
        }

        if (text is null) { return 1; }
        File.WriteAllText(options.GetValueOrDefault("--out") ?? input, text);
        return 0;
    }

    // A whole-number option, 10 when it is not given.
    private static int Number(Dictionary<string, string> options, string name) =>
        options.TryGetValue(name, out string? text) ? int.Parse(text, System.Globalization.CultureInfo.InvariantCulture) : 10;

    // Parses a text program, reporting its problems as file(line): severity: message.
    private static BasicProgram? Parse(string input, BasicDialect? dialect)
    {
        BasicParseResult result = BasicProgram.Parse(File.ReadAllText(input), dialect, input);
        foreach (BasicDiagnostic diagnostic in result.Diagnostics)
        {
            string severity = diagnostic.Severity == BasicSeverity.Error ? "error" : "warning";
            Console.Error.WriteLine($"{input}({diagnostic.Line + 1}): {severity}: {diagnostic.Message}");
        }

        return result.Program;
    }

    private static int Fail(string message, int code)
    {
        Console.Error.WriteLine(message);
        return code;
    }
}
