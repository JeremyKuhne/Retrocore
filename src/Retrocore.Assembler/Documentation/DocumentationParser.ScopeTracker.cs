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
        private int _macros;

        /// <summary>
        ///  Gets the names of the open named scopes, outermost first.
        /// </summary>
        internal List<string> Scopes { get; } = [];

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
            AdvanceCode(code, line, assembled?.UsingAssembled(line) ?? true);

            // A macro invoked on the line may itself have given a .using, and a .define may have expanded to one,
            // which apply from the next line.
            if (assembled is not null && _macros == 0)
            {
                bool written = FirstWord(code).Equals(".using", StringComparison.OrdinalIgnoreCase);
                IEnumerable<string[]> expanded = written || assembled.LineUsings is null ? [] : assembled.LineUsings(line);
                foreach (string[] names in assembled.InvokedUsings(line).Concat(expanded))
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
            if (word == ".macro")
            {
                _macros++;
                return;
            }

            if (word == ".endmacro")
            {
                if (_macros != 0) { _macros--; }
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
            else if (word == ".using" && _macros == 0 && assembled)
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
