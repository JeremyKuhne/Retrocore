// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Assembler;

namespace Retrocore.Debug;

/// <summary>
///  Assembles a native, ca65 or Merlin source with the retrocore assembler for debugging.
/// </summary>
internal static class SourceBuild
{
    /// <summary>
    ///  Assembles a source file.
    /// </summary>
    /// <param name="source">The source file.</param>
    /// <param name="dialect">The dialect, or null for native unless the file's first-line pragma names one.</param>
    /// <param name="cpu">The CPU, as <c>.cpu</c> names it.</param>
    /// <param name="origin">The load address when no linker configuration places the code.</param>
    /// <param name="linkerConfiguration">An optional ld65-style linker configuration file.</param>
    /// <returns>The assembly result.</returns>
    /// <exception cref="InvalidDataException">The source has errors, listed in the message.</exception>
    internal static AssemblyResult Assemble(
        string source,
        AssemblyDialect? dialect,
        string cpu,
        int origin,
        string? linkerConfiguration)
    {
        string path = Path.GetFullPath(source);
        AssemblyOptions options = new(cpu, origin, 0x10000 - origin)
        {
            Dialect = dialect ?? AssemblyDialect.Native,
            SourceResolver = new FileAssemblySourceResolver(),
            LinkerConfiguration = linkerConfiguration is null
                ? null
                : new(File.ReadAllText(linkerConfiguration), Path.GetFullPath(linkerConfiguration))
        };

        AssemblyResult result = new Assembler.Assembler().Assemble(new AssemblySource(File.ReadAllText(path), path), options);
        if (!result.Success)
        {
            IEnumerable<string> errors = result.Diagnostics.Select(diagnostic => diagnostic.Location is { } location
                ? $"{location.Path}({location.Line + 1}): {diagnostic.Message}"
                : diagnostic.Message);

            throw new InvalidDataException(string.Join(Environment.NewLine, errors));
        }

        return result;
    }

    /// <summary>
    ///  Tests whether a source's first <c>.cpu</c> directive names a CPU, such as the Z80 of a program for the
    ///  SoftCard.
    /// </summary>
    /// <param name="source">The source file.</param>
    /// <param name="cpu">The CPU's name.</param>
    /// <returns>Whether it does.</returns>
    internal static bool DeclaresCpu(string source, string cpu)
    {
        foreach (string line in File.ReadLines(source))
        {
            string text = line.Trim();
            if (!text.StartsWith(".cpu", StringComparison.OrdinalIgnoreCase)) { continue; }
            string name = text[4..].Split(';')[0].Trim().Trim('"');
            return string.Equals(name, cpu, StringComparison.OrdinalIgnoreCase);
        }

        return false;
    }

    /// <summary>
    ///  Gets the sections that hold bytes, each with the address it loads at.
    /// </summary>
    /// <param name="result">The assembly output.</param>
    /// <returns>The loadable sections, in output order.</returns>
    internal static IEnumerable<AssemblySection> Loadable(AssemblyResult result) =>
        result.Sections.Where(section => section.Bytes.Length != 0);

    /// <summary>
    ///  Gets each section's emitted bytes and load address, without the unused rest of a native image.
    /// </summary>
    /// <param name="result">The assembly output.</param>
    /// <returns>The address and bytes of each section that emitted code or data, in output order.</returns>
    internal static IEnumerable<(int Address, ReadOnlyMemory<byte> Bytes)> Emitted(AssemblyResult result)
    {
        int[] used = new int[result.Sections.Count];
        foreach (AssemblySourceMapEntry entry in result.SourceMap)
        {
            if (entry.Size != 0) { used[entry.Section] = Math.Max(used[entry.Section], entry.Offset + entry.Size); }
        }

        for (int index = 0; index < used.Length; index++)
        {
            if (used[index] != 0)
            {
                yield return (result.Sections[index].Origin, result.Sections[index].Bytes[..used[index]]);
            }
        }
    }

    /// <summary>
    ///  Gets the single output file's bytes.
    /// </summary>
    /// <param name="result">The assembly output.</param>
    /// <returns>The linker or Merlin output file, or the only section that holds bytes.</returns>
    /// <exception cref="InvalidDataException">The output has several files or sections.</exception>
    internal static ReadOnlyMemory<byte> OutputBytes(AssemblyResult result)
    {
        if (result.Files.Count == 1) { return result.Files.Values.Single(); }
        AssemblySection[] sections = [.. Loadable(result)];
        return sections.Length == 1
            ? sections[0].Bytes
            : throw new InvalidDataException("The output has several sections; a linker configuration must place them in one file.");
    }

    /// <summary>
    ///  Gets a source file's debug information in cc65 .dbg format.
    /// </summary>
    /// <param name="result">The assembly output.</param>
    /// <returns>The .dbg records.</returns>
    internal static string DebugInfo(AssemblyResult result)
    {
        using StringWriter writer = new();
        AssemblyDebugFile.Write(result, writer);
        return writer.ToString();
    }

    /// <summary>
    ///  Parses a dialect name.
    /// </summary>
    /// <param name="name">native, ca65, merlin or macro10, or null.</param>
    /// <returns>The dialect, or null when none is given.</returns>
    internal static AssemblyDialect? Dialect(string? name) => name?.ToLowerInvariant() switch
    {
        null => null,
        "native" => AssemblyDialect.Native,
        "ca65" => AssemblyDialect.Ca65,
        "merlin" => AssemblyDialect.Merlin,
        "macro10" => AssemblyDialect.Macro10,
        _ => throw new ArgumentException($"Unknown dialect '{name}'; expected native, ca65, merlin or macro10.")
    };
}
