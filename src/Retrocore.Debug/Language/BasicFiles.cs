// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using System.Text.Json.Nodes;
using Retrocore.Basic;

namespace Retrocore.Debug.Language;

/// <summary>
///  The language server's BASIC requests that need no machine: renumbering text, and listing and storing tokenized
///  files and Model I tapes, so they open as text.
/// </summary>
internal static class BasicFiles
{
    private const int DefaultStep = 10;

    /// <summary>
    ///  Renumbers text: <c>retrocore/basic/renumber</c>, with <c>text</c>, <c>start</c>, <c>step</c>,
    ///  <c>languageId</c> and <c>path</c>.
    /// </summary>
    /// <param name="args">The request.</param>
    /// <returns>The renumbered <c>text</c>, null when it cannot be, and its <c>diagnostics</c>.</returns>
    internal static JsonObject Renumber(JsonObject args)
    {
        (string? text, IReadOnlyList<BasicDiagnostic> diagnostics) = BasicRenumber.Renumber(
            args.String("text") ?? "",
            args.Int("start") ?? DefaultStep,
            args.Int("step") ?? DefaultStep,
            BasicDocuments.DialectOf(args.String("languageId") ?? ""),
            args.String("path"));

        return new JsonObject { ["text"] = text, ["diagnostics"] = Diagnostics(diagnostics) };
    }

    /// <summary>
    ///  Lists a tokenized file or a tape: <c>retrocore/basic/list</c>, with <c>path</c> and an optional
    ///  <c>dialect</c>.
    /// </summary>
    /// <param name="args">The request.</param>
    /// <returns>The listing's <c>text</c> and <c>dialect</c>.</returns>
    /// <exception cref="ArgumentException">The dialect is not given and the file name does not say it.</exception>
    internal static JsonObject List(JsonObject args)
    {
        string path = Path(args);
        BasicDialect dialect = DialectOf(path, args.String("dialect"));
        byte[] bytes = File.ReadAllBytes(path);
        BasicProgram program = IsTape(path) ? BasicTape.Read(bytes, out _) : BasicProgram.FromImage(dialect, bytes);
        return new JsonObject { ["text"] = program.ToText(), ["dialect"] = dialect.Name };
    }

    /// <summary>
    ///  Tokenizes text into a file in the form it had: <c>retrocore/basic/store</c>, with <c>path</c>, <c>text</c> and
    ///  <c>dialect</c>. A tape keeps its name, and a Level II Disk BASIC file its leading $FF.
    /// </summary>
    /// <param name="args">The request.</param>
    /// <returns>Whether it was written (<c>success</c>), and the text's <c>diagnostics</c>.</returns>
    internal static JsonObject Store(JsonObject args)
    {
        string path = Path(args);
        BasicDialect dialect = DialectOf(path, args.String("dialect"));
        BasicParseResult parsed = BasicProgram.Parse(args.String("text") ?? "", dialect);
        if (parsed.Program is not { } program)
        {
            return new JsonObject { ["success"] = false, ["diagnostics"] = Diagnostics(parsed.Diagnostics) };
        }

        byte[] old = File.Exists(path) ? File.ReadAllBytes(path) : [];
        byte[] bytes;
        if (IsTape(path))
        {
            char name = 'A';
            if (old.Length != 0) { BasicTape.Read(old, out name); }
            bytes = BasicTape.Write(program, name);
        }
        else
        {
            bytes = old.Length > 0 && old[0] == 0xFF && dialect == BasicDialect.Level2 ? [0xFF, .. program.ToImage()] : program.ToImage();
        }

        File.WriteAllBytes(path, bytes);
        return new JsonObject { ["success"] = true, ["diagnostics"] = Diagnostics(parsed.Diagnostics) };
    }

    /// <summary>
    ///  Gets the dialect of a tokenized file: the one given, Level II for a tape, AppleSoft or Integer BASIC for a
    ///  CiderPress2 name with its $FC or $FA file type (such as <c>HELLO#fc0801</c>).
    /// </summary>
    /// <param name="path">The file.</param>
    /// <param name="name">The dialect given, or null.</param>
    /// <returns>The dialect.</returns>
    /// <exception cref="ArgumentException">The dialect is not given and the file name does not say it.</exception>
    internal static BasicDialect DialectOf(string path, string? name)
    {
        if (BasicDialect.FromName(name) is { } named) { return named; }
        if (IsTape(path)) { return BasicDialect.Level2; }
        string file = System.IO.Path.GetFileName(path);
        if (file.Contains("#fa", StringComparison.OrdinalIgnoreCase)) { return BasicDialect.Integer; }
        return file.Contains("#fc", StringComparison.OrdinalIgnoreCase)
            ? BasicDialect.AppleSoft
            : throw new ArgumentException($"Say which BASIC {file} is: applesoft, integer or level2.");
    }

    private static bool IsTape(string path) => path.EndsWith(".cas", StringComparison.OrdinalIgnoreCase);

    private static string Path(JsonObject args) => args.String("path") ?? throw new ArgumentException("path is required.");

    private static JsonArray Diagnostics(IReadOnlyList<BasicDiagnostic> diagnostics) =>
        diagnostics.Select(diagnostic => new JsonObject
            {
                ["line"] = diagnostic.Line,
                ["severity"] = diagnostic.Severity == BasicSeverity.Error ? "error" : "warning",
                ["message"] = diagnostic.Message,
                ["start"] = diagnostic.Start,
                ["end"] = diagnostic.End
            }).ToJsonArray();
}
