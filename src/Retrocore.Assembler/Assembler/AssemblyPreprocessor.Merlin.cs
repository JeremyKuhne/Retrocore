// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Assembler;

internal sealed partial class AssemblyPreprocessor
{
    private MerlinState? _merlin;

    /// <summary>
    ///  Separates Merlin macro arguments in a translated invocation. Merlin uses ';', which the native line
    ///  splitter reads as a comment.
    /// </summary>
    internal const char MerlinArgumentSeparator = '\u001F';

    private const string MerlinLoopCounter = "__MerlinLup";

    // Macro parameter names and the ]n text they replace, indexed by argument number.
    private static readonly string[] s_merlinParameters =
        ["", "__MerlinArg1", "__MerlinArg2", "__MerlinArg3", "__MerlinArg4", "__MerlinArg5", "__MerlinArg6", "__MerlinArg7", "__MerlinArg8"];

    private static readonly string[] s_merlinVariables = ["]0", "]1", "]2", "]3", "]4", "]5", "]6", "]7", "]8"];

    private string TranslateMerlin(Line line, Dictionary<string, string>? arguments, MacroFrame? frame, bool master)
    {
        MerlinState state = _merlin ??= new();
        ReadOnlyMemory<char> text = line.Text;
        if (arguments is not null
            && frame is not null
            && arguments.ContainsKey(s_merlinParameters[1])
            && text.Span.IndexOf(']') >= 0)
        {
            // ]1 through ]8 are the arguments and ]0 their count, substituted as text before the line is read.
            string substituted = AssemblySyntax.AsString(text);
            for (int index = 1; index < s_merlinParameters.Length; index++)
            {
                if (arguments.TryGetValue(s_merlinParameters[index], out string? value))
                {
                    substituted = substituted.Replace(s_merlinVariables[index], value);
                }
            }

            text = substituted.Replace(s_merlinVariables[0], frame.ParameterCount.ToString()).AsMemory();
        }

        MerlinFrontend.Split(text.Span, out string label, out string rawOperation, out string operand);
        string operation = rawOperation.ToUpperInvariant();
        bool active = _conditions.Count == 0 || _conditions[^1].Active;
        if (!active && operation is not ("DO" or "IF" or "ELSE" or "FIN")) { return ""; }
        if (label.Length == 0 && operation.Length == 0) { return ""; }
        string Name(string value) => state.Names.Resolve(value, frame?.Locals);
        string Expression(string value) => MerlinExpression.Translate(value, state.Names, frame?.Locals);
        string Label()
        {
            if (label.Length == 0) { return ""; }
            if (label.IndexOf('@') >= 0 && arguments?.TryGetValue(MerlinLoopCounter, out string? iteration) == true)
            {
                // As in Merlin 32, @ in a LUP label becomes A, B, C ... for each iteration.
                int count = int.Parse(iteration);
                if (count >= 26) { throw new AssemblyError(0, "A LUP label with @ allows at most 26 iterations."); }
                label = label.Replace('@', (char)('A' + count));
            }

            state.Names.Define(label);
            if (label[0] == ':' && frame?.Locals.ContainsKey(label) != true)
            {
                return $"{state.Names.DefineLocal(label)}: ";
            }

            if (label[0] == ']')
            {
                Emit(line, $".set {Name(label)}, *");
                return "";
            }

            if (label[0] is not (':' or ']') && frame?.Locals.ContainsKey(label) != true)
            {
                state.Names.Anchor = label;
            }

            return $"{Name(label)}: ";
        }

        if (operation == "MAC")
        {
            const string Parameters = "__MerlinArg1,__MerlinArg2,__MerlinArg3,__MerlinArg4,__MerlinArg5,__MerlinArg6,__MerlinArg7,__MerlinArg8";
            return label.Length == 0
                ? throw new AssemblyError(0, "MAC requires a macro name in column zero.")
                : $".macro {Name(label)} {Parameters}";
        }

        if (operation is "EOM" or "<<<") { return ".endmacro"; }
        // The native block directives take no label, so a label on these lines becomes its own statement.
        void EmitLabel()
        {
            string text = active ? Label() : "";
            if (text.Length != 0) { Emit(line, text); }
        }

        if (operation == "LUP")
        {
            EmitLabel();
            return $".repeat {Expression(operand)}, {MerlinLoopCounter}";
        }

        if (operation == "--^") { return ".endrepeat"; }
        if (operation == "DO")
        {
            EmitLabel();
            return active ? $".if {Expression(operand)}" : ".if 0";
        }

        if (operation == "IF")
        {
            if (operand.StartsWith("MX", StringComparison.OrdinalIgnoreCase))
            {
                throw new AssemblyError(0, "65816 IF MX is unsupported.");
            }

            string characters = new([.. operand.Where(character => !char.IsWhiteSpace(character))]);
            bool equal = active && characters.Length >= 3 && characters[0] == characters[2];
            EmitLabel();
            return equal ? ".if 1" : ".if 0";
        }

        if (operation == "ELSE") { return ".else"; }
        if (operation == "FIN") { return ".endif"; }
        if (operation is "PUT" or "USE")
        {
            // As in Merlin 32, only the master file's PUT and USE lines include files; nested ones are ignored.
            // PUT inserts its file each time, while USE loads a macro file once.
            string path = MerlinIncludePath(operand.Trim('"', '\''), line);
            bool include = master && (operation == "PUT" || state.Used.Add(path));
            return include ? $"{Label()}.include \"{path}\"" : Label();
        }

        if (operation is "SAV" or "DSK")
        {
            if (operand.Length == 0) { throw new AssemblyError(0, "A Merlin output directive requires a filename."); }
            if (state.Output is { } output && output != operand)
            {
                throw new AssemblyError(0, "Multiple Merlin output files are not supported.");
            }

            state.Output = operand;
            return Label();
        }

        if (operation is "TYP" or "LST" or "LSTDO" or "TR" or "TTL" or "PAG" or "PAU" or "EXP" or "END")
        {
            return Label();
        }

        if (operation == "XC")
        {
            if (state.Extended || operand.Length != 0)
            {
                throw new AssemblyError(0, "65816 mode and a second XC are unsupported.");
            }

            state.Extended = true;
            return $"{Label()}.cpu Wdc65C02";
        }

        if (operation == "MX") { throw new AssemblyError(0, "65816 MX modes are unsupported."); }
        if (operation == "ENT")
        {
            if (label.Length != 0)
            {
                Emit(line, Label());
                return $".export {Name(label)}";
            }

            return $".export {MerlinList(operand, frame, MerlinItem.Name)}";
        }

        if (operation == "EXT") { throw new AssemblyError(0, "External Merlin linking is unsupported."); }
        if (operation is "EQU" or "=")
        {
            if (label.Length == 0) { throw new AssemblyError(0, "A Merlin assignment requires a name."); }
            state.Names.Define(label);
            string name = Name(label);
            if (label[0] != ']' && frame?.Locals.ContainsKey(label) != true) { state.Names.Anchor = label; }
            if (operation == "EQU" && label[0] != ']')
            {
                // EQU is textual in Merlin 32, except that * means the location of the definition, not of each use.
                string pinned = MerlinPinLocation(operand, label);
                if (!ReferenceEquals(pinned, operand)) { Emit(line, $"{MerlinLocationLabel(label)}:"); }
                state.Equates[label] = operand = pinned;
            }

            string value = MerlinExpression.Translate(operand, state.Names, frame?.Locals, expandEquates: false);
            return operation == "=" || label[0] == ']' ? $".set {name}, {value}" : $"{name} = {value}";
        }

        if (operation.Length == 0) { return Label(); }
        string macro = rawOperation;
        if (operation is "PMC" or ">>>")
        {
            int space = operand.IndexOfAny([' ', '\t', ';', ',']);
            macro = space < 0 ? operand : operand[..space];
            operand = space < 0 ? "" : operand[(space + 1)..].TrimStart();
        }

        string safeMacro = Name(macro);
        if (_macros.ContainsKey(safeMacro))
        {
            return $"{Label()}{safeMacro} {operand.Replace(';', MerlinArgumentSeparator)}";
        }

        string prefix = Label();
        switch (operation)
        {
            case "ASC":
            case "DCI":
            case "INV":
            case "FLS":
            case "REV":
            case "STR":
                return $"{prefix}{MerlinFrontend.StringData(operation, operand, MerlinHexEquate)}";
            case "HEX":
                return $"{prefix}.byte {string.Join(",", MerlinFrontend.Hex(operand))}";

            // Merlin keeps the low bits of data values silently; <, > and ^ select a byte of the whole item.
            case "DFB":
            case "DB":
                return $"{prefix}.byte {MerlinList(operand, frame, MerlinItem.Byte)}";
            case "DA":
            case "DW":
                return $"{prefix}.word {MerlinData(operand, "65535", frame)}";
            case "DDB":
                return $"{prefix}.dbyt {MerlinData(operand, "65535", frame)}";
            case "ADR":
                return $"{prefix}.faraddr {MerlinData(operand, "16777215", frame)}";
            case "ADRL":
                return $"{prefix}.dword {MerlinList(operand, frame, MerlinItem.Expression)}";
            case "DS":
                return operand == "\\"
                    ? $"{prefix}.align 256"
                    : $"{prefix}.res {MerlinList(operand, frame, MerlinItem.Expression)}";

            case "ORG": return $"{prefix}.logicalorg {Expression(operand)}";
            case "DUM": return $"{prefix}.dum {Expression(operand)}";
            case "DEND": return $"{prefix}.dend";
            case "CHK": return $"{prefix}.checksum";
            case "ERR": return $"{prefix}.assert .not ({Expression(operand)})";
        }

        // Merlin 32 assembles XCE in every mode; 6502 code uses it to probe for a 65816.
        if (operation == "XCE")
        {
            return operand.Length == 0 ? $"{prefix}.byte $FB" : throw new AssemblyError(0, "XCE takes no operand.");
        }

        operand = MerlinHexEquate(operand);
        if (operation == "BRK" && operand.Length != 0)
        {
            // BRK may carry a signature byte, written with or without #.
            return $"{prefix}.byte 0, {MerlinByte(operand.TrimStart('#'), frame)}";
        }

        // A fourth opcode character other than L forces absolute addressing; L selects 65816 long addressing.
        if (operation.Length == 4 && char.IsLetter(operation[0]))
        {
            operation = operation[3] == 'L'
                ? throw new AssemblyError(0, "65816 long addressing is unsupported.")
                : $"{operation.AsSpan(0, 3)}.W";
        }
        else if (operation.Length > 3)
        {
            throw new AssemblyError(0, $"Unsupported Merlin operation '{operation}'.");
        }

        if (operand.Length == 0 || operand.Equals("A", StringComparison.OrdinalIgnoreCase))
        {
            return $"{prefix}{operation} {operand}";
        }

        if (operand[0] == '#')
        {
            string value = operand[1..];
            char extraction = value.Length != 0 ? value[0] : '\0';
            if (extraction is '<' or '>' or '/' or '^') { value = value[1..]; }
            string expression = Expression(value);

            // An immediate keeps its low byte silently, as in Merlin 32.
            return extraction switch
            {
                '>' => $"{prefix}{operation} #>({expression})",
                '/' or '^' => $"{prefix}{operation} #.bankbyte({expression})",
                _ => $"{prefix}{operation} #<({expression})"
            };
        }

        List<string> parts = Ca65Frontend.Split(operand);
        if (operand[0] == '(')
        {
            int close = operand.LastIndexOf(')');
            if (close < 0) { throw new AssemblyError(0, "Unterminated Merlin indirect operand."); }
            List<string> inner = Ca65Frontend.Split(operand[1..close]);
            string index = inner.Count > 1 ? $",{inner[1]}" : "";
            return $"{prefix}{operation} ({Expression(inner[0])}{index}){operand.AsSpan(close + 1)}";
        }

        // A leading parenthesis would read as indirect addressing, so a grouped address gets 0+ in front.
        string address = Expression(parts[0]);
        string zero = address.Length != 0 && address[0] == '(' ? "0+" : "";
        return parts.Count > 1
            ? $"{prefix}{operation} {zero}{address},{parts[1]}"
            : $"{prefix}{operation} {zero}{address}";
    }

    /// <summary>
    ///  Translates each comma-separated item of an operand.
    /// </summary>
    /// <remarks>
    ///  <para>
    ///   A loop rather than a LINQ lambda, since a lambda in <see cref="TranslateMerlin"/> would move its locals to a
    ///   heap closure allocated for every line.
    ///  </para>
    /// </remarks>
    /// <param name="operand">The operand text.</param>
    /// <param name="frame">The macro invocation, if any.</param>
    /// <param name="kind">How each item is translated.</param>
    /// <returns>The translated items, joined by commas.</returns>
    private string MerlinList(string operand, MacroFrame? frame, MerlinItem kind)
    {
        MerlinState state = _merlin ??= new();
        List<string> items = kind == MerlinItem.Name ? [.. operand.Split(',')] : Ca65Frontend.Split(operand);
        for (int index = 0; index < items.Count; index++)
        {
            string item = items[index];
            items[index] = kind switch
            {
                MerlinItem.Name => state.Names.Resolve(item.Trim(), frame?.Locals),
                MerlinItem.Byte => MerlinByte(item, frame),
                _ => MerlinExpression.Translate(item, state.Names, frame?.Locals)
            };
        }

        return string.Join(",", items);
    }

    private string MerlinByte(string item, MacroFrame? frame)
    {
        MerlinState state = _merlin ??= new();
        string text = item.Trim();
        char selector = text.Length != 0 ? text[0] : '\0';
        string source = selector is '<' or '>' or '^' ? text[1..] : text;
        string expression = MerlinExpression.Translate(source, state.Names, frame?.Locals);
        return selector switch
        {
            '>' => $">({expression})",
            '^' => $".bankbyte({expression})",
            _ => $"<({expression})"
        };
    }

    private string MerlinData(string operand, string mask, MacroFrame? frame)
    {
        MerlinState state = _merlin ??= new();
        List<string> values = [];
        foreach (string item in Ca65Frontend.Split(operand))
        {
            // As in Merlin 32, < keeps the value, > shifts it right 8 bits and ^ 16, before the field keeps its low bits.
            char selector = item.Length != 0 ? item[0] : '\0';
            string source = selector is '<' or '>' or '^' ? item[1..] : item;
            string expression = MerlinExpression.Translate(source, state.Names, frame?.Locals);
            values.Add(selector switch
            {
                '>' => $"(({expression}) >> 8) & {mask}",
                '^' => $"(({expression}) >> 16) & {mask}",
                _ => $"({expression}) & {mask}"
            });
        }

        return string.Join(",", values);
    }

    /// <summary>
    ///  Resolves a PUT or USE name the way Merlin 32 does: as written, or with .s appended when only that exists.
    /// </summary>
    /// <param name="request">The file name relative to the master file.</param>
    /// <param name="line">The including line.</param>
    /// <returns>The include request.</returns>
    private string MerlinIncludePath(string request, Line line)
    {
        if (request.EndsWith(".s", StringComparison.OrdinalIgnoreCase) || _options.SourceResolver is not { } resolver)
        {
            return request;
        }

        try
        {
            string from = line.Location.Path;
            bool exact = resolver.TryResolve(from, request, out _);
            string suffixed = $"{request}.s";
            return exact || !resolver.TryResolve(from, suffixed, out _) ? request : suffixed;
        }
        catch (IOException)
        {
            return request;
        }
        catch (UnauthorizedAccessException)
        {
            return request;
        }
    }

    private string MerlinLocationLabel(string label) => $"__merlin_at_{(_merlin ??= new()).Names.Resolve(label)}";

    /// <summary>
    ///  Replaces * meaning the location counter with a label at the definition, leaving multiplication alone.
    /// </summary>
    /// <param name="operand">The EQU text.</param>
    /// <param name="label">The equate's name.</param>
    /// <returns>The pinned text, or the same instance when it does not read the location counter.</returns>
    private string MerlinPinLocation(string operand, string label)
    {
        if (operand.IndexOf('*') < 0) { return operand; }
        List<string> parts = [];
        int copied = 0;
        bool operandExpected = true;
        for (int index = 0; index < operand.Length; index++)
        {
            char character = operand[index];
            if (character is '"' or '\'' && index + 2 < operand.Length && operand[index + 2] == character)
            {
                // A character constant such as "*" is a value, not an operator.
                index += 2;
                operandExpected = false;
                continue;
            }

            if (character == '*' && operandExpected)
            {
                parts.Add(operand[copied..index]);
                parts.Add(MerlinLocationLabel(label));
                copied = index + 1;
                operandExpected = false;
                continue;
            }

            if (!char.IsWhiteSpace(character))
            {
                operandExpected = character is '+' or '-' or '*' or '/' or '&' or '.' or '!' or '=' or '<' or '>' or '(' or '#';
            }
        }

        if (parts.Count == 0) { return operand; }
        parts.Add(operand[copied..]);
        return string.Concat(parts);
    }

    /// <summary>
    ///  Records a file's EQU text before its lines run, because Merlin substitutes an EQU even ahead of it.
    /// </summary>
    /// <param name="source">The Merlin source.</param>
    private void CollectMerlinEquates(AssemblySource source)
    {
        MerlinState state = _merlin ??= new();
        state.Names.MaximumDepth = _options.MaximumMacroDepth;
        foreach (ReadOnlyMemory<char> raw in new AssemblyLines(source.Text.AsMemory()))
        {
            // Most lines have no EQU, and splitting one into strings would allocate three.
            if (raw.Span.IndexOf("EQU".AsSpan(), StringComparison.OrdinalIgnoreCase) < 0) { continue; }
            MerlinFrontend.Split(raw.Span, out string label, out string operation, out string operand);
            if (label.Length != 0 && label[0] != ']' && operation.Equals("EQU", StringComparison.OrdinalIgnoreCase))
            {
                state.Equates.TryAdd(label, MerlinPinLocation(operand, label));
            }
        }
    }

    private void FinishMerlin()
    {
        if (_merlin is not { } merlin) { return; }
        _project.SymbolAliases = new(merlin.Names.Aliases, StringComparer.Ordinal);
        _project.MerlinOutput = merlin.Output ?? _options.OutputFile;
    }

    private string MerlinHexEquate(string text)
    {
        MerlinState state = _merlin ??= new();
        int depth = 0;
        while (state.Equates.TryGetValue(text, out string? replacement))
        {
            if (++depth >= _options.MaximumMacroDepth) { throw new AssemblyError(0, "Recursive Merlin EQU text."); }
            text = replacement;
        }

        return text;
    }
}
