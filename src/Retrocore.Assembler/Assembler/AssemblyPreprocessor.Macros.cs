// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Assembler;

internal sealed partial class AssemblyPreprocessor
{
    private void DefineMacro(
        string operand,
        IReadOnlyList<Line> body,
        AssemblyLocation location,
        Dictionary<string, string>? substitutions,
        MacroFrame? frame)
    {
        ReadOnlySpan<char> text = operand;
        text = text.Trim();
        int nameLength = AssemblySyntax.IdentifierSegmentLength(text);
        if (nameLength == 0 || (nameLength < text.Length && !char.IsWhiteSpace(text[nameLength]) && text[nameLength] != ','))
        {
            Error(".macro requires a name and optional parameter names.", location);
            return;
        }

        string name = text[..nameLength].ToString();
        string parameters = text[nameLength..].Trim().ToString();
        if (parameters.Length != 0 && parameters[0] == ',') { parameters = parameters[1..].Trim(); }
        List<string> names = Arguments(parameters);
        HashSet<string> unique = new(StringComparer.Ordinal);
        foreach (string parameter in names)
        {
            if (!AssemblySyntax.IsPlainIdentifier(parameter) || !unique.Add(parameter))
            {
                Error("Invalid or duplicate macro parameter.", location);
                return;
            }
        }

        if (_macros.ContainsKey(name))
        {
            Error($"Duplicate macro '{name}'.", location);
            return;
        }

        List<Line> frozen = new(body.Count);
        foreach (Line line in body)
        {
            frozen.Add(new(Substitute(line.Text, substitutions, frame), line.Location, line.Dialect));
        }

        _macros.Add(name, new([.. names], frozen));
    }

    private void ExpandMacro(Macro macro, string operand, Line invocation, int includeDepth, int macroDepth, bool merlin = false)
    {
        if (macroDepth >= _options.MaximumMacroDepth)
        {
            Error("Maximum macro recursion depth exceeded.", invocation.Location);
            return;
        }

        if (!ValidateArguments(operand, invocation.Location)) { return; }

        // Merlin separates arguments with ';', so an argument such as ($06),Y keeps its comma.
        List<string> arguments = merlin ? MerlinArguments(operand) : Arguments(operand);
        if (arguments.Count > macro.Parameters.Length)
        {
            Error("Too many macro arguments.", invocation.Location);
            return;
        }

        Dictionary<string, string> names = new(StringComparer.Ordinal);
        for (int index = 0; index < macro.Parameters.Length; index++)
        {
            names.Add(macro.Parameters[index], index < arguments.Count ? arguments[index] : "");
        }

        // Each invocation gets its own call-site identity, so a debugger can tell expansions from one line apart,
        // such as successive iterations of a .repeat.
        AssemblyLocation call = invocation.Location.Occurrence();
        List<Line> expanded = new(macro.Body.Count);
        foreach (Line line in macro.Body)
        {
            AssemblyLocation physical = line.Location;
            AssemblyLocation location = new(physical.Path, physical.Line, physical.Column, call, macro: true);
            expanded.Add(new(line.Text, location, line.Dialect));
        }

        int floor = _conditions.Count;
        MacroFrame frame = new(++_invocation, arguments.Count);
        if (macro.MerlinLocals is { } locals)
        {
            string prefix = $"__merlin_macro_{frame.Invocation}_";
            for (int index = 0; index < locals.Length; index++)
            {
                frame.Locals.Add(locals[index], $"{prefix}{index}");
            }
        }

        bool exit = Process(expanded, names, includeDepth, macroDepth + 1, floor, frame);
        CloseConditions(floor, report: !exit);
    }

    private void DeclareLocals(Line line, MacroFrame? frame, Dictionary<string, string>? names)
    {
        if (frame is null)
        {
            Error(".local requires a macro invocation.", line.Location);
            return;
        }

        Split(line.Text.Span, out _, out _, out ReadOnlySpan<char> operand);
        List<string> arguments = Arguments(operand.ToString());
        if (arguments.Count == 0) { Error(".local requires at least one name.", line.Location); }
        foreach (string name in arguments)
        {
            // As in ca65, a local belongs to the whole invocation, so a repeat body may declare it again.
            if (frame.Locals.ContainsKey(name)) { continue; }
            if (!AssemblySyntax.IsPlainIdentifier(name) || names?.ContainsKey(name) == true)
            {
                Error("Invalid or parameter-conflicting local name.", line.Location);
                continue;
            }

            string local = $"__retro_macro_{frame.Invocation}_{name}";
            if (_defined.Contains(local))
            {
                Error($"Generated macro local '{local}' collides with an existing symbol.", line.Location);
                continue;
            }

            frame.Locals.Add(name, local);
        }
    }
}
