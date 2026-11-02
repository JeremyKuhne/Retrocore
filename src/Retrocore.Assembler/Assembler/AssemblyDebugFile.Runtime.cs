// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Assembler;

/// <summary>
///  Writes assembly output as a cc65 debug information file, the <c>.dbg</c> format ld65 writes with
///  <c>--dbgfile</c>.
/// </summary>
/// <remarks>
///  <para>
///   Every dialect produces the same file, so debuggers and other tools that read ld65 debug information can step
///   through native, ca65 and Merlin sources alike. Each run of emitted bytes is a span on the line that produced
///   it, which for an included file is that file's own line.
///  </para>
///  <para>
///   As in ld65's output, bytes from a macro belong to two kinds of line record: the invocation line, which has no
///   type, and each macro body line, which has <c>type=2</c> and a <c>count</c> of its expansion depth. A debugger
///   can step by invocation and still break on a line inside the macro.
///  </para>
///  <para>
///   A section whose logical address changes, such as with <c>.org</c> or Merlin <c>ORG</c>, becomes one
///   segment record per address run, so a segment's start plus a span's offset is always the CPU address.
///  </para>
/// </remarks>
public static partial class AssemblyDebugFile
{
    private const int MacroLineType = 2;

    /// <summary>
    ///  Writes debug information for a successful assembly.
    /// </summary>
    /// <param name="result">The assembly output.</param>
    /// <param name="writer">The destination.</param>
    /// <exception cref="ArgumentException">The assembly failed.</exception>
    public static void Write(AssemblyResult result, TextWriter writer)
    {
        ArgumentNullException.ThrowIfNull(result);
        ArgumentNullException.ThrowIfNull(writer);
        if (!result.Success)
        {
            throw new ArgumentException("Only a successful assembly has debug information.", nameof(result));
        }

        Builder builder = new(result);
        builder.Write(writer);
    }
}
