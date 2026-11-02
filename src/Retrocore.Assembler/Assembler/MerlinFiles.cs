// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Assembler;

/// <summary>
///  Produces a trimmed, owned in-memory Merlin object without writing source-directed filenames.
/// </summary>
internal static class MerlinFiles
{
    /// <summary>
    ///  Drops unused Merlin equates that could not compile, since Merlin 32 accepts any unused EQU text.
    /// </summary>
    /// <remarks>
    ///  <para>
    ///   Referenced equates always compile. An unused one is kept, so its value is published, when its text is a
    ///   valid expression whose names are all defined; otherwise, such as hexadecimal text meant for string
    ///   trailers, it is dropped.
    ///  </para>
    /// </remarks>
    /// <param name="source">Caller-owned expanded syntax.</param>
    /// <returns>A compilation-only view with statement indices unchanged.</returns>
    internal static AssemblyProject Prepare(AssemblyProject source)
    {
        Dictionary<string, int> equates = new(StringComparer.Ordinal);
        for (int index = 0; index < source.Statements.Count; index++)
        {
            AssemblyStatement node = source.Statements[index];
            if (node.Dialect == AssemblyDialect.Merlin && node.Kind == AssemblyStatementKind.Constant && node.Label is { } name)
            {
                if (!equates.TryAdd(name, index))
                {
                    throw new AssemblyError(index, $"Duplicate Merlin equate '{name}'.");
                }
            }
        }

        if (equates.Count == 0) { return source; }
        HashSet<string> required = new(StringComparer.Ordinal);
        Queue<string> pending = new();
        void References(ReadOnlyMemory<char> text)
        {
            AssemblyNameReferences cursor = new(text);
            while (cursor.MoveNext())
            {
                string token = cursor.Current.ToString();
                if (equates.ContainsKey(token) && required.Add(token)) { pending.Enqueue(token); }
            }
        }

        foreach (AssemblyStatement node in source.Statements)
        {
            if (node.Dialect != AssemblyDialect.Merlin || node.Kind != AssemblyStatementKind.Constant)
            {
                References(node.Operand.Memory);
            }
        }

        while (pending.Count != 0) { References(source.Statements[equates[pending.Dequeue()]].Operand.Memory); }

        // Unused equates compile only when valid and closed over names that stay defined, found as a fixpoint.
        HashSet<string> labels = new(StringComparer.Ordinal);
        foreach (AssemblyStatement node in source.Statements)
        {
            if (node.Label is { } label && !equates.ContainsKey(label)) { labels.Add(label); }
        }

        HashSet<string> kept = new(required, StringComparer.Ordinal);
        bool added = true;
        while (added)
        {
            added = false;
            foreach (KeyValuePair<string, int> pair in equates)
            {
                bool compiles = !kept.Contains(pair.Key) && Compiles(source.Statements[pair.Value].Operand.Text, labels, kept);
                if (!compiles) { continue; }
                kept.Add(pair.Key);
                added = true;
            }
        }

        AssemblyProject project = new(source.Statements.Count)
        {
            InitialSection = source.InitialSection,
            MemoryRegions = source.MemoryRegions,
            LinkerSymbols = source.LinkerSymbols,
            LabelSizes = source.LabelSizes,
            SymbolAliases = source.SymbolAliases,
            MerlinOutput = source.MerlinOutput
        };

        foreach (AssemblySource document in source.Sources) { project.Sources.Add(document); }
        if (source.DeclaredSections is { } sections)
        {
            foreach (AssemblySectionDefinition definition in sections) { project.SectionDefinitions.Add(definition); }
        }

        foreach (AssemblyStatement node in source.Statements)
        {
            bool equate = node.Dialect == AssemblyDialect.Merlin && node.Kind == AssemblyStatementKind.Constant;
            bool unused = equate && node.Label is { } name && !kept.Contains(name);

            project.Statements.Add(unused ? new(AssemblyStatementKind.Label, "", label: null)
            {
                Location = node.Location, Dialect = node.Dialect
            } : node);
        }

        return project;
    }

    private static bool Compiles(string text, HashSet<string> labels, HashSet<string> equates)
    {
        try
        {
            ExpressionEvaluator syntax = new(text.AsMemory(), new AssemblySymbols(), address: 0, line: 0);
            _ = syntax.TryEvaluate(out _);
        }
        catch (AssemblyError)
        {
            return false;
        }
        catch (OverflowException)
        {
            return false;
        }

        AssemblyNameReferences cursor = new(text.AsMemory());
        while (cursor.MoveNext())
        {
            if (cursor.Current.Span[0] == '.') { continue; }
            string name = cursor.Current.ToString();
            if (!labels.Contains(name) && !equates.Contains(name)) { return false; }
        }

        return true;
    }

    /// <summary>
    ///  Copies emitted ranges into the requested output.
    /// </summary>
    /// <param name="image">Resolved compiler storage.</param>
    /// <param name="name">The source or caller output name.</param>
    internal static void Emit(AssemblyImage image, string name)
    {
        int length = 0;
        foreach (LayoutStatement statement in image.Statements.AsSpan(0, image.StatementCount))
        {
            if (statement.NoOutput || statement.Size == 0) { continue; }
            if (statement.Section != 0)
            {
                throw new AssemblyError(statement.Line, "Merlin output requires a single emitting section.");
            }

            length = Math.Max(length, statement.Offset + statement.Size);
        }

        image.Files = new(StringComparer.Ordinal) { [name] = image.Sections[0].Bytes[..length].ToArray() };
    }
}
