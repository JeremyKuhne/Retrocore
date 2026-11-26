// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Debug.Project;

/// <summary>
///  One of a project's <c>steps</c>: a host-side tool the build runs before it assembles, with the files it reads and
///  the files it writes.
/// </summary>
/// <remarks>
///  <para>
///   The tool is a C# file-based app (a <c>.cs</c> file, run as <c>dotnet run &lt;file&gt; -- &lt;args&gt;</c>) or a
///   project (a <c>.csproj</c>, run as <c>dotnet run --project &lt;file&gt; -- &lt;args&gt;</c>), started in the
///   project's folder. Paths are relative to the project's folder, and <c>${obj}</c> in an input, an output or an
///   argument is the project's intermediate folder, <c>obj/</c>; the tool's own path takes no variables. An argument that is exactly <c>${in}</c> or <c>${out}</c> stands for
///   every input or every output, one argument each; with no <c>args</c> the tool is given the inputs, then the
///   outputs.
///  </para>
/// </remarks>
/// <param name="Tool">The tool's full path.</param>
/// <param name="Arguments">
///  The arguments as the project file gives them, or null for the inputs then the outputs.
/// </param>
/// <param name="Inputs">The full paths of the files the tool reads.</param>
/// <param name="Outputs">The full paths of the files the tool writes.</param>
internal sealed record ProjectStep(string Tool, IReadOnlyList<string>? Arguments, IReadOnlyList<string> Inputs, IReadOnlyList<string> Outputs)
{
    /// <summary>
    ///  The fields a step can give.
    /// </summary>
    internal static readonly string[] Fields = ["tool", "args", "in", "out"];

    /// <summary>
    ///  The variable that names the project's intermediate folder.
    /// </summary>
    internal const string Intermediate = "${obj}";

    /// <summary>
    ///  The argument that stands for every input.
    /// </summary>
    internal const string AllInputs = "${in}";

    /// <summary>
    ///  The argument that stands for every output.
    /// </summary>
    internal const string AllOutputs = "${out}";

    /// <summary>
    ///  Gets whether the tool is a project rather than a file-based app.
    /// </summary>
    internal bool IsProject => Tool.EndsWith(".csproj", StringComparison.OrdinalIgnoreCase);

    /// <summary>
    ///  Gets the arguments the tool is run with, after the <c>--</c>: <c>${in}</c> and <c>${out}</c> expanded, and
    ///  <c>${obj}</c> replaced in each.
    /// </summary>
    /// <param name="intermediate">The project's intermediate folder.</param>
    /// <returns>The arguments.</returns>
    internal List<string> ToolArguments(string intermediate)
    {
        if (Arguments is null) { return [.. Inputs, .. Outputs]; }
        List<string> arguments = [];
        foreach (string argument in Arguments)
        {
            if (argument == AllInputs) { arguments.AddRange(Inputs); }
            else if (argument == AllOutputs) { arguments.AddRange(Outputs); }
            else { arguments.Add(argument.Replace(Intermediate, intermediate, StringComparison.Ordinal)); }
        }

        return arguments;
    }
}
