// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Assembler;

internal sealed partial class AssemblyPreprocessor
{
    private Dictionary<string, string>? _macro10Aliases;

    /// <summary>
    ///  Expands a MACRO-10 file and parses each native line it produces.
    /// </summary>
    /// <remarks>
    ///  <para>
    ///   MACRO-10 bodies span lines and nest mid-line, so the whole file is expanded at once rather than line by
    ///   line; each produced line keeps the source location and macro expansion it came from.
    ///  </para>
    /// </remarks>
    /// <param name="source">The source.</param>
    /// <param name="parent">The including location, if any.</param>
    private void ProcessMacro10(AssemblySource source, AssemblyLocation? parent)
    {
        Macro10Expander expander = new(_options.MaximumExpandedLines, _options.MaximumMacroDepth, _options.PredefinedSymbols);
        IReadOnlyList<(string Text, AssemblyLocation Location)> lines;
        if (PragmaValue(source.Text, "overlay") is { } request)
        {
            // An overlay edits a pinned base, so unchanged lines keep the base's file and line for debugging.
            AssemblySource? baseSource = null;
            AssemblyLocation pragma = new(source.Path, line: 0, expandedFrom: parent);
            try
            {
                IAssemblySourceResolver? resolver = _options.SourceResolver;
                resolver?.TryResolve(source.Path, request, out baseSource);
            }
            catch (Exception error) when (error is IOException or UnauthorizedAccessException or ArgumentException)
            {
                // As an include reports them: unreadable, denied, or a name no path can hold or that depends on
                // current-directory state.
                Error($"Cannot resolve overlay base '{request}': {error.Message}", pragma);
                return;
            }

            if (baseSource is null)
            {
                Error($"Cannot resolve overlay base '{request}'.", pragma);
                return;
            }

            try
            {
                (string composed, Func<int, AssemblyLocation> location) = Macro10Overlay.Compose(source, baseSource, parent);
                lines = expander.Expand(composed, location);
            }
            catch (AssemblyError error)
            {
                Error(error.Message, new(source.Path, error.Line, expandedFrom: parent));
                return;
            }
        }
        else
        {
            lines = expander.Expand(source.Text, source.Path, parent);
        }

        foreach ((string text, AssemblyLocation location) in lines)
        {
            _visited++;
            Emit(new Line(text, location, AssemblyDialect.Macro10), text);
        }

        foreach ((string message, AssemblyLocation location) in expander.Errors) { Error(message, location); }
        if (expander.Aliases.Count == 0) { return; }
        _macro10Aliases ??= [with(StringComparer.Ordinal)];
        foreach (KeyValuePair<string, string> alias in expander.Aliases) { _macro10Aliases[alias.Key] = alias.Value; }
    }

    /// <summary>
    ///  Defines the options' predefined symbols as constants ahead of every source.
    /// </summary>
    private void Predefine()
    {
        AssemblyLocation location = new("<predefined>", line: 0);
        foreach (KeyValuePair<string, long> symbol in _options.PredefinedSymbols)
        {
            // The most negative value's magnitude is past the largest literal, so it is written as a sum.
            string value = symbol.Value == long.MinValue
                ? "(-9223372036854775807 - 1)"
                : symbol.Value.ToString(System.Globalization.CultureInfo.InvariantCulture);

            string text = $"{symbol.Key} = {value}";
            Emit(new Line(text, location, AssemblyDialect.Native), text);
        }
    }

    /// <summary>
    ///  Publishes MACRO-10 names that needed generated aliases alongside any Merlin ones.
    /// </summary>
    private void FinishMacro10()
    {
        if (_macro10Aliases is null) { return; }
        _project.SymbolAliases ??= [with(StringComparer.Ordinal)];
        foreach (KeyValuePair<string, string> alias in _macro10Aliases)
        {
            _project.SymbolAliases[alias.Key] = alias.Value;
        }
    }
}
