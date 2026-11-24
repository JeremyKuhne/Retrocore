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
        // macro's parameters and its .local names) and how many scopes were open where its definition began.
        private readonly List<(string Name, HashSet<string> Parameters, HashSet<string> Locals, int Depth)> _macros = [];

        /// <summary>
        ///  Gets the names of the open named scopes, outermost first.
        /// </summary>
        internal List<string> Scopes { get; } = [];

        /// <summary>
        ///  Gets the macro whose body the next line is in, innermost; null outside a macro's body.
        /// </summary>
        internal string? Macro => _macros.Count == 0 ? null : _macros[^1].Name;

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
        ///  Follows one line's code.
        /// </summary>
        /// <param name="code">The trimmed code, without its comment.</param>
        /// <param name="line">The line's zero-based number.</param>
        /// <param name="assembled">What the assembler took from the file, or null when not known.</param>
        internal void Advance(string code, int line, DocumentationAssembled? assembled)
        {
            // With the names the assembler took from each line, those stand for the line's text, which a .define may
            // have changed or given; without them, the text is read.
            bool namesKnown = assembled?.LineUsings is not null;
            AdvanceCode(code, line, !namesKnown && (assembled?.UsingAssembled(line) ?? true));

            // A macro invoked on the line may itself have given a .using, which applies from the next line.
            if (assembled is not null && _macros.Count == 0)
            {
                IEnumerable<string[]> written = assembled.LineUsings is { } lineUsings ? lineUsings(line) : [];
                foreach (string[] names in written.Concat(assembled.InvokedUsings(line)))
                {
                    _usings.Add((_named.Count, new(string.Join("::", Scopes), names, line)));
                    _current = null;
                }
            }
        }

        private void AdvanceCode(string code, int line, bool assembled)
        {
            string word = FirstWord(code).ToLowerInvariant();

            // A .using in a macro's body applies where the macro is invoked, not where it is defined.
            // ca65's short forms open and close a macro too.
            if (word is ".macro" or ".mac")
            {
                IReadOnlyList<string> words = Words(code[word.Length..]);
                HashSet<string> parameters = [with(StringComparer.Ordinal), .. words.Skip(1)];
                _macros.Add((words.Count == 0 ? "" : words[0], parameters, [with(StringComparer.Ordinal)], Scopes.Count));
                return;
            }

            if (word is ".endmacro" or ".endmac")
            {
                if (_macros.Count != 0) { _macros.RemoveAt(_macros.Count - 1); }
                return;
            }

            if (word == ".local" && _macros.Count != 0)
            {
                foreach (string local in Words(code[word.Length..])) { _macros[^1].Locals.Add(local); }
                return;
            }

            int length = IdentifierLength(code);
            if (length != 0 && code.Length > length && code[length] == ':')
            {
                // A label may precede .proc on the same line.
                code = code[(length + 1)..].TrimStart(':').Trim();
                word = FirstWord(code).ToLowerInvariant();
            }

            if (word is ".proc" or ".scope")
            {
                string name = FirstWord(code[word.Length..].Trim());
                _named.Add(name.Length != 0);
                if (name.Length != 0) { Scopes.Add(name); }
                _current = null;
            }
            else if (word is ".endproc" or ".endscope" && _named.Count != 0)
            {
                if (_named[^1]) { Scopes.RemoveAt(Scopes.Count - 1); }
                _named.RemoveAt(_named.Count - 1);

                // A scope's .using directives end with it, and so do those of a continued scope's piece.
                _usings.RemoveAll(item => item.Depth > _named.Count);
                _current = null;
            }
            else if (word == ".using" && _macros.Count == 0 && assembled)
            {
                string[] names = [.. code[word.Length..].Split(',').Select(name => name.Trim()).Where(name => name.Length != 0)];
                if (names.Length != 0)
                {
                    _usings.Add((_named.Count, new(string.Join("::", Scopes), names, line)));
                    _current = null;
                }
            }
        }
    }
}
