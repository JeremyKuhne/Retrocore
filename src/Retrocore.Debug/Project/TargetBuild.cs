// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Assembler;

namespace Retrocore.Debug.Project;

/// <summary>
///  A target as <see cref="ProjectBuild"/> built it: the assembly, what it loads where, and its output files.
/// </summary>
/// <param name="Target">The target.</param>
/// <param name="Result">The assembly, with its source map.</param>
/// <param name="Sources">The files assembled, in order.</param>
/// <param name="Segments">The address and bytes of each section that emitted code or data, in output order.</param>
/// <param name="Entry">The program's entry: the project's <c>entry</c> label, or the first segment's address.</param>
internal sealed record TargetBuild(
    ProjectTarget Target,
    AssemblyResult Result,
    IReadOnlyList<TargetSourceFile> Sources,
    IReadOnlyList<(int Address, ReadOnlyMemory<byte> Bytes)> Segments,
    int Entry)
{
    /// <summary>
    ///  Gets the binary's path, <c>&lt;output&gt;/&lt;target&gt;/&lt;name&gt;.bin</c>.
    /// </summary>
    internal required string Binary { get; init; }

    /// <summary>
    ///  Gets the cc65 debug information's path, beside the binary.
    /// </summary>
    internal required string DebugFile { get; init; }

    /// <summary>
    ///  Gets the map's path, beside the binary.
    /// </summary>
    internal required string MapFile { get; init; }

    /// <summary>
    ///  Gets the build record's path, <c>obj/&lt;target&gt;/build.json</c>.
    /// </summary>
    internal required string Record { get; init; }

    /// <summary>
    ///  Gets the project's steps as the build left them, each run or up to date.
    /// </summary>
    internal IReadOnlyList<StepResult> Steps { get; init; } = [];
}
