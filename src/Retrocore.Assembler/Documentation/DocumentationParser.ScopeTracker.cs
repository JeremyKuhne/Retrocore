// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Documentation;

public static partial class DocumentationParser
{
    /// <summary>
    ///  Follows a source's <c>.proc</c> and <c>.scope</c> nesting and the <c>.using</c> directives in effect, line
    ///  by line, as the assembler qualifies and looks up names.
    /// </summary>
    private sealed class ScopeTracker
    {
        // Whether each open scope has a name, so an anonymous one's end leaves the named ones open.
        private readonly List<bool> _named = [];
        private readonly List<(int Depth, DocumentationUsing Using)> _usings = [];
        private DocumentationScopes? _current;

        // The macro bodies open around the line, innermost last, with the names that differ in each expansion (the
        // macro's parameters and its .local names), how many named scopes were open where its definition began, and
        // the line of its .macro directive.
        private readonly List<(string Name, HashSet<string> Parameters, HashSet<string> Locals, int Depth, int Line)> _macros = [];

        /// <summary>
        ///  Gets the names of the open named scopes, outermost first.
        /// </summary>
        internal List<string> Scopes { get; } = [];

        /// <summary>
        ///  Gets the macro whose body the next line is in, innermost; null outside a macro's body.
        /// </summary>
        internal string? Macro => _macros.Count == 0 ? null : _macros[^1].Name;

        /// <summary>
        ///  Gets the zero-based line of the directive that opens the macro whose body the next line is in, innermost;
        ///  -1 outside a macro's body.
        /// </summary>
        internal int MacroLine => _macros.Count == 0 ? -1 : _macros[^1].Line;

        /// <summary>
        ///  Gets how a definition's name, as the next line writes it, varies from one expansion of the macro around
        ///  it to the next.
        /// </summary>
        /// <param name="name">The definition's name.</param>
        /// <returns>
        ///  Whether a part of it is one of the macro's parameters, and whether it is local to each expansion: a
        ///  <c>.local</c> name or a cheap local (<c>@name</c>).
        /// </returns>
        internal (bool Parameter, bool Local) Varies(string name)
        {
            if (_macros.Count == 0) { return (false, false); }

            // A macro defined in another's body takes the outer one's parameters and .local names in each of its
            // expansions too. The scopes around each macro's definition aren't its expansion's: only the parts of the
            // name written in its body can be its parameters or .local names.
            string[] qualified = name.Split(["::"], StringSplitOptions.None);
            // A macro's or a .define's name isn't qualified by the scopes around it, so it's written whole.
            IEnumerable<string> Written(int depth) => qualified.Skip(Math.Min(depth, qualified.Length - 1));
            string last = qualified[qualified.Length - 1];
            bool local = (last.Length != 0 && last[0] == '@')
                || _macros.Any(macro => Written(macro.Depth).Any(macro.Locals.Contains));

            bool parameter = _macros.Any(macro => Written(macro.Depth).Any(macro.Parameters.Contains));
            return (!local && parameter, local);
        }

        /// <summary>
        ///  Gets the scope and the <c>.using</c> directives in effect before the next line.
        /// </summary>
        internal DocumentationScopes Current => _current ??= Scopes.Count == 0 && _usings.Count == 0
            ? DocumentationScopes.Root
            : new(string.Join("::", Scopes), [.. Enumerable.Reverse(_usings).Select(item => item.Using)]);

        /// <summary>
        ///  Follows one line's code, reading it in place.
        /// </summary>
        /// <param name="code">The trimmed code, without its comment.</param>
        /// <param name="line">The line's zero-based number.</param>
        /// <param name="assembled">What the assembler took from the file, or null when not known.</param>
        internal void Advance(ReadOnlySpan<char> code, int line, DocumentationAssembled? assembled)
        {
            // With the names the assembler took from each line, those stand for the line's text, which a .define may
            // have changed or given; without them, the text is read.
            bool namesKnown = assembled?.LineUsings is not null;
            AdvanceCode(code, line, !namesKnown && (assembled?.UsingAssembled(line) ?? true));

            // A macro invoked on the line may itself have given a .using, which applies from the next line: the names
            // written on the line first, then those of the macros it invoked.
            if (assembled is not null && _macros.Count == 0)
            {
                IReadOnlyList<string[]> written = assembled.LineUsings is { } lineUsings ? lineUsings(line) : [];
                IReadOnlyList<string[]> invoked = assembled.InvokedUsings(line);
                for (int index = 0; index < written.Count; index++) { AddUsing(written[index], line); }
                for (int index = 0; index < invoked.Count; index++) { AddUsing(invoked[index], line); }
            }
        }

        private void AddUsing(string[] names, int line)
        {
            _usings.Add((_named.Count, new(string.Join("::", Scopes), names, line)));
            _current = null;
        }

        // Only a line that opens or closes a macro, a scope or a .using is copied out of the text.
        private void AdvanceCode(ReadOnlySpan<char> code, int line, bool assembled)
        {
            ReadOnlySpan<char> word = FirstWord(code);

            // A .using in a macro's body applies where the macro is invoked, not where it is defined.
            // ca65's short forms open and close a macro too.
            if (IsLowered(word, ".macro") || IsLowered(word, ".mac"))
            {
                IReadOnlyList<string> words = Words(code[word.Length..].ToString());
                HashSet<string> parameters = [with(StringComparer.Ordinal), .. words.Skip(1)];
                _macros.Add((words.Count == 0 ? "" : words[0], parameters, [with(StringComparer.Ordinal)], Scopes.Count, line));
                return;
            }

            if (IsLowered(word, ".endmacro") || IsLowered(word, ".endmac"))
            {
                if (_macros.Count != 0) { _macros.RemoveAt(_macros.Count - 1); }
                return;
            }

            if (IsLowered(word, ".local") && _macros.Count != 0)
            {
                foreach (string local in Words(code[word.Length..].ToString())) { _macros[^1].Locals.Add(local); }
                return;
            }

            int length = IdentifierLength(code);
            if (length != 0 && code.Length > length && code[length] == ':')
            {
                // A label may precede .proc on the same line.
                code = code[(length + 1)..].TrimStart(':').Trim();
                word = FirstWord(code);
            }

            if (IsLowered(word, ".proc") || IsLowered(word, ".scope"))
            {
                string name = FirstWord(code[word.Length..].Trim()).ToString();
                _named.Add(name.Length != 0);
                if (name.Length != 0) { Scopes.Add(name); }
                _current = null;
            }
            else if ((IsLowered(word, ".endproc") || IsLowered(word, ".endscope")) && _named.Count != 0)
            {
                if (_named[^1]) { Scopes.RemoveAt(Scopes.Count - 1); }
                _named.RemoveAt(_named.Count - 1);

                // A scope's .using directives end with it, and so do those of a continued scope's piece.
                _usings.RemoveAll(item => item.Depth > _named.Count);
                _current = null;
            }
            else if (IsLowered(word, ".using") && _macros.Count == 0 && assembled)
            {
                string[] names = [.. code[word.Length..].ToString().Split(',').Select(name => name.Trim()).Where(name => name.Length != 0)];
                if (names.Length != 0)
                {
                    _usings.Add((_named.Count, new(string.Join("::", Scopes), names, line)));
                    _current = null;
                }
            }
        }
    }
}
