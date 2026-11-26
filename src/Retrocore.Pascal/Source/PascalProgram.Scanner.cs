// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Pascal.Source;

public sealed partial class PascalProgram
{
    /// <summary>
    ///  Reads the declarations and the names used, by recursive descent over the program's tokens: its includes
    ///  expanded, its options left out, its documentation comments kept. It is forgiving: what it does not follow it
    ///  steps over, so that a source being edited still gets most of its names.
    /// </summary>
    private sealed class Scanner
    {
        private readonly PascalProgram _program;
        private readonly List<PascalToken> _tokens;
        private int _at;
        private PascalDocComment? _pending;
        private readonly List<PascalDeclaration> _statement = [];
        private readonly Dictionary<PascalToken, PascalDeclaration> _declared = [];

        /// <summary>
        ///  Creates a scanner.
        /// </summary>
        /// <param name="program">The program it fills in.</param>
        /// <param name="tokens">The program's tokens.</param>
        public Scanner(PascalProgram program, List<PascalToken> tokens)
        {
            _program = program;
            _tokens = tokens;
        }

        private static bool IsIntrinsic(PascalToken? token) =>
            token is { Kind: PascalTokenKind.Identifier } && PascalNames.Key(token.Text) == "INTRINSI";

        private PascalToken? Current => Skip() < _tokens.Count ? _tokens[_at] : null;

        /// <summary>
        ///  Reads the whole program.
        /// </summary>
        public void Run()
        {
            PascalScope scope = _program.Outer;
            if (Current is { } first && (first.Is("PROGRAM") || first.Is("UNIT") || first.Is("SEPARATE")))
            {
                bool unit = !first.Is("PROGRAM");
                if (first.Is("SEPARATE")) { Next(); }
                Next();
                if (Current is { Kind: PascalTokenKind.Identifier } name)
                {
                    PascalDeclarationKind kind = unit ? PascalDeclarationKind.Unit : PascalDeclarationKind.Program;
                    PascalDeclaration program = Declare(name, kind, scope);
                    _program.Outer.Owner = program;
                    Next();
                }

                // The heading's files; then a unit's INTRINSIC CODE and DATA, its own clause.
                SkipTo(";");
                Next();
                EndStatement();
                if (unit && IsIntrinsic(Current))
                {
                    SkipTo(";");
                    Next();
                }

                if (unit) { Unit(scope); }
            }

            Block(scope);
            while (Current is not null)
            {
                Use(scope);
                Next();
            }

            if (_pending is { } stray) { _program.StrayDocs.Add(stray); }
        }

        private void Unit(PascalScope scope)
        {
            if (Current is { } token && token.Is("INTERFACE"))
            {
                Next();
                Declarations(scope, interfacePart: true);
            }

            if (Current is { } implementation && implementation.Is("IMPLEMENTATION")) { Next(); }
        }

        private void Block(PascalScope scope)
        {
            Declarations(scope, interfacePart: false);
            if (Current is { } token && token.Is("BEGIN")) { Compound(scope); }
        }

        private void Declarations(PascalScope scope, bool interfacePart)
        {
            while (Current is { } token)
            {
                if (token.Is("PROCEDURE") || token.Is("FUNCTION") || token.Is("SEGMENT"))
                {
                    Routine(scope, interfacePart);
                    continue;
                }

                bool section = token.Is("LABEL")
                    || token.Is("CONST")
                    || token.Is("TYPE")
                    || token.Is("VAR")
                    || token.Is("USES");

                if (!section)
                {
                    // The statement part, or the unit's implementation, ends the declarations; anything else, such as
                    // a name still being typed, is stepped over, so the declarations after it are still read.
                    bool ends = token.Is("BEGIN") || token.Is("IMPLEMENTATION") || (token.Is("END") && IsSymbol(1, "."));
                    if (ends) { return; }
                    if (token.IsSymbol(".") && IsEndOfProgram()) { return; }
                    Use(scope);
                    Next();
                    continue;
                }

                Next();
                if (token.Is("CONST")) { Constants(scope, interfacePart); }
                else if (token.Is("TYPE")) { Types(scope, interfacePart); }
                else if (token.Is("VAR")) { Variables(scope, interfacePart, PascalDeclarationKind.Variable, ";"); }
                else
                {
                    // LABEL's labels, or the units USES names.
                    if (UseUntilBlock(scope, ";"))
                    {
                        Next();
                        EndStatement();
                    }
                }
            }
        }

        private void Constants(PascalScope scope, bool interfacePart)
        {
            while (Current is { Kind: PascalTokenKind.Identifier } name && IsSymbol(1, "="))
            {
                Declare(name, PascalDeclarationKind.Constant, scope).IsInterface = interfacePart;
                Next();
                Next();
                if (!UseUntilBlock(scope, ";"))
                {
                    _statement.Clear();
                    return;
                }

                Next();
                EndStatement();
            }
        }

        private void Types(PascalScope scope, bool interfacePart)
        {
            while (Current is { Kind: PascalTokenKind.Identifier } name && IsSymbol(1, "="))
            {
                PascalDeclaration type = Declare(name, PascalDeclarationKind.Type, scope);
                type.IsInterface = interfacePart;
                Next();
                Next();
                Type(scope, type, interfacePart);
                if (Current is { } end && end.IsSymbol(";")) { Next(); }
                EndStatement();
            }
        }

        // A list of names, a colon and a type: variables, a record's fields, or parameters.
        private void Variables(PascalScope scope, bool interfacePart, PascalDeclarationKind kind, string end)
        {
            while (Current is { Kind: PascalTokenKind.Identifier })
            {
                List<PascalDeclaration> names = [];
                while (Current is { Kind: PascalTokenKind.Identifier } name)
                {
                    PascalDeclaration declared = Declare(name, kind, scope);
                    declared.IsInterface = interfacePart;
                    names.Add(declared);
                    Next();
                    if (Current is { } comma && comma.IsSymbol(",")) { Next(); continue; }
                    break;
                }

                if (Current is not { } colon || !colon.IsSymbol(":"))
                {
                    // A list still being typed: its names keep no comment that comes after.
                    _statement.Clear();
                    return;
                }

                Next();
                Type(scope.IsRecord ? scope.Parent ?? scope : scope, owner: null, interfacePart);
                if (Current is { } semicolon && semicolon.IsSymbol(end)) { Next(); EndStatement(); }
                else { EndStatement(); return; }
            }
        }

        // A type, up to the ";" or ")" or END that ends it: its names used, its enumeration's values and its
        // records' fields declared.
        private void Type(PascalScope scope, PascalDeclaration? owner, bool interfacePart)
        {
            if (Current is { } open && open.IsSymbol("("))
            {
                // A comment after the type documents the type; one among its values documents none of them.
                List<PascalDeclaration> outer = [.. _statement];
                _statement.Clear();
                Next();
                while (Current is { Kind: PascalTokenKind.Identifier } value)
                {
                    PascalDeclaration declared = Declare(value, PascalDeclarationKind.EnumValue, scope);
                    declared.IsInterface = interfacePart;
                    _statement.Clear();
                    Next();
                    if (Current is { } comma && comma.IsSymbol(",")) { Next(); }
                }

                bool closed = Current is { } close && close.IsSymbol(")");
                _statement.AddRange(outer);
                if (closed) { Next(); }
                return;
            }

            int depth = 0;
            while (Current is { } token)
            {
                if (token.Is("RECORD"))
                {
                    Next();
                    PascalScope fields = new(scope, owner, isRecord: true);
                    _program.Scopes.Add(fields);

                    // A field's trailing comment documents the field, not the type being declared.
                    List<PascalDeclaration> outer = [.. _statement];
                    _statement.Clear();
                    Fields(fields, interfacePart);
                    _statement.Clear();
                    _statement.AddRange(outer);
                    if (Current is { } end && end.Is("END")) { Next(); }
                    continue;
                }

                if (token.IsSymbol("(") || token.IsSymbol("[")) { depth++; }
                else if (token.IsSymbol(")") || token.IsSymbol("]"))
                {
                    if (depth == 0) { return; }
                    depth--;
                }
                else if (StartsBlock(token) || (depth == 0 && (token.IsSymbol(";") || token.Is("END")))) { return; }
                else if (token.Kind == PascalTokenKind.Identifier) { Use(scope); }

                Next();
            }
        }

        // A record's fields, up to its END: fixed fields, then a variant part.
        private void Fields(PascalScope fields, bool interfacePart)
        {
            Variables(fields, interfacePart, PascalDeclarationKind.Field, ";");
            if (Current is not { } variant || !variant.Is("CASE")) { return; }
            Next();
            if (Current is { Kind: PascalTokenKind.Identifier } tag && IsSymbol(1, ":"))
            {
                Declare(tag, PascalDeclarationKind.Field, fields).IsInterface = interfacePart;
                Next();
                Next();
            }

            // The tag's type, to OF; a variant part still being typed may have none yet. The tag takes no comment of
            // the fields after it.
            if (!UseUntilBefore(fields.Parent ?? fields, "OF", "END", ";")) { return; }
            Next();
            _statement.Clear();
            // An inner variant part ends at the ")" that closes its variant; the outermost at the record's END.
            while (Current is { } token && !token.Is("END") && !token.IsSymbol(")"))
            {
                // The variant's labels, a colon, and its fields in parentheses.
                if (!UseUntilBefore(fields.Parent ?? fields, ":", "END", ";", ")")) { return; }
                Next();
                if (Current is not { } open || !open.IsSymbol("(")) { return; }
                Next();
                Fields(fields, interfacePart);
                if (Current is { } close && close.IsSymbol(")")) { Next(); }
                if (Current is { } semicolon && semicolon.IsSymbol(";")) { Next(); }
            }
        }

        private void Routine(PascalScope scope, bool interfacePart)
        {
            bool segment = false;
            if (Current is { } token && token.Is("SEGMENT")) { segment = true; Next(); }
            if (Current is not { } kind) { return; }
            bool function = kind.Is("FUNCTION");
            Next();
            if (Current is not { Kind: PascalTokenKind.Identifier } name) { return; }

            // A routine declared FORWARD, or in a unit's interface, is given its body by a second heading.
            string key = PascalNames.Key(name.Text);
            PascalDeclaration? earlier = scope.Declarations.LastOrDefault(
                declaration => declaration.Key == key && declaration.IsHeadingOnly && declaration.Body is not null);

            PascalDeclaration routine;
            PascalScope body;
            if (earlier is not null && !interfacePart)
            {
                routine = earlier;
                body = earlier.Body ?? new(scope, routine, isRecord: false);
                routine.IsHeadingOnly = false;
                _program.References.Add(new(name, scope, AfterDot: false));
                TakePending(routine);
            }
            else
            {
                PascalDeclarationKind kind2 = function
                    ? PascalDeclarationKind.Function
                    : PascalDeclarationKind.Procedure;

                routine = Declare(name, kind2, scope);
                routine.IsSegment = segment;
                routine.IsInterface = interfacePart;
                body = new(scope, routine, isRecord: false);
                routine.Body = body;
                _program.Scopes.Add(body);
            }

            // A parameter's trailing comment documents the parameter; the routine's comes after its heading.
            _statement.Clear();
            Next();
            if (Current is { } open && open.IsSymbol("("))
            {
                Next();
                // A parameter list ends at its ")", or, still being typed, where the routine's block starts.
                while (Current is { } parameter && !parameter.IsSymbol(")") && !EndsParameters(parameter))
                {
                    if (parameter.Is("VAR")) { Next(); continue; }
                    if (parameter.Kind == PascalTokenKind.Identifier)
                    {
                        Variables(body, interfacePart, PascalDeclarationKind.Parameter, ";");
                        continue;
                    }

                    Next();
                }

                if (Current is { } close && close.IsSymbol(")")) { Next(); }
            }

            // A comment after the heading on its line, with or without its ";", documents the routine.
            _statement.Clear();
            if (routine.Doc is null) { _statement.Add(routine); }
            if (Current is { } colon && colon.IsSymbol(":"))
            {
                Next();
                UseUntilBlock(scope, ";");
            }

            bool ended = Current is { } semicolon && semicolon.IsSymbol(";");
            if (ended)
            {
                // A documentation comment after the heading, on its line, documents the routine.
                Next();
                _statement.Clear();
                if (routine.Doc is null) { _statement.Add(routine); }
                EndStatement();
            }

            // A heading without its ";", still being typed, leaves its routine to no later comment.
            if (!ended) { _statement.Clear(); }
            if (interfacePart)
            {
                routine.IsHeadingOnly = true;
                return;
            }

            // A heading still being typed, with no ";" and a declaration after it, has no block yet: the declaration
            // is the enclosing one's. After a ";", a routine there is a nested one.
            if (!ended && Current is { } cut && StartsDeclaration(cut)) { return; }

            if (Current is { } directive && (directive.Is("FORWARD") || directive.Is("EXTERNAL")))
            {
                routine.IsHeadingOnly = true;
                Next();
                if (Current is { } end && end.IsSymbol(";"))
                {
                    // A documentation comment after the directive, on its line, documents the routine.
                    Next();
                    _statement.Clear();
                    if (routine.Doc is null) { _statement.Add(routine); }
                    EndStatement();
                }

                return;
            }

            Block(body);
            if (Current is { } after && after.IsSymbol(";")) { Next(); }
        }

        // A statement part, BEGIN to its END, noting the WITH statements whose bodies may name fields bare: a body
        // that is a BEGIN ends at its END, any other at the ";", END or UNTIL that ends the statement, or an ELSE
        // that isn't its own IF's.
        private void Compound(PascalScope scope)
        {
            int depth = 0;
            bool awaitingDo = false;
            List<PascalWithBody> withs = [];
            Stack<int> repeats = [];
            _statement.Clear();
            while (Current is { } token)
            {
                // A declaration can't be in a statement: an END is missing, and the declaration is the enclosing one's.
                if (StartsDeclaration(token)) { return; }
                if (token.Is("WITH")) { awaitingDo = true; }
                else if (token.Is("DO") && awaitingDo)
                {
                    awaitingDo = false;
                    bool block = IsKeyword(1, "BEGIN");
                    withs.Add(new(block ? depth + 1 : depth, block));
                }
                else if (token.Is("BEGIN") || token.Is("CASE")) { depth++; }
                else if (token.Is("IF"))
                {
                    foreach (PascalWithBody body in withs.Where(body => !body.Block && body.Depth == depth))
                    {
                        body.Ifs++;
                    }

                }
                else if (token.Is("ELSE"))
                {
                    // An ELSE ends the bodies with no IF of their own open; in the others it is their IF's.
                    withs.RemoveAll(body => !body.Block && body.Depth == depth && body.Ifs == 0);
                    foreach (PascalWithBody body in withs.Where(body => !body.Block && body.Depth == depth))
                    {
                        body.Ifs--;
                    }
                }
                else if (token.IsSymbol(";"))
                {
                    withs.RemoveAll(body => !body.Block && body.Depth == depth);
                }
                else if (token.Is("REPEAT"))
                {
                    depth++;
                    repeats.Push(depth);
                }
                else if (token.Is("UNTIL") && repeats.TryPeek(out int open) && open == depth)
                {
                    // REPEAT's statements are a level, as BEGIN's are, which its UNTIL closes; a stray UNTIL is not.
                    repeats.Pop();
                    withs.RemoveAll(body => body.Depth >= depth);
                    depth--;
                }
                else if (token.Is("END"))
                {
                    // An END closes a BEGIN or CASE, after any REPEAT inside it its UNTIL never closed.
                    while (repeats.TryPeek(out int unclosed) && unclosed == depth)
                    {
                        repeats.Pop();
                        withs.RemoveAll(body => body.Depth >= depth);
                        depth--;
                    }

                    withs.RemoveAll(body => body.Depth >= depth);
                    depth--;
                    Next();
                    if (depth == 0) { return; }
                    continue;
                }
                else if (token.Kind == PascalTokenKind.Identifier) { Use(scope, inWith: withs.Count > 0); }

                Next();
            }
        }

        // Uses the names up to a symbol or word, and says whether it was found before one of the others.
        private bool UseUntilBefore(PascalScope scope, string end, params string[] stops)
        {
            while (Current is { } token && !(token.IsSymbol(end) || token.Is(end)))
            {
                if (stops.Any(stop => token.IsSymbol(stop) || token.Is(stop))) { return false; }
                if (token.Kind == PascalTokenKind.Identifier) { Use(scope); }
                Next();
            }

            return Current is not null;
        }

        // Uses the names up to a symbol, and says whether it was found before a declaration or block started.
        private bool UseUntilBlock(PascalScope scope, string end)
        {
            while (Current is { } token && !token.IsSymbol(end))
            {
                if (StartsBlock(token)) { return false; }
                if (token.Kind == PascalTokenKind.Identifier) { Use(scope); }
                Next();
            }

            return Current is not null;
        }

        // Whether a token starts a declaration, a declaration section or a statement part, which no value or type has.
        private static bool StartsBlock(PascalToken token) =>
            StartsDeclaration(token) || token.Is("VAR") || token.Is("BEGIN") || token.Is("USES");

        private static bool EndsParameters(PascalToken token) =>
            token.Is("BEGIN") || token.Is("FORWARD") || token.Is("EXTERNAL") || StartsDeclaration(token);

        private void UseUntil(PascalScope scope, string end)
        {
            while (Current is { } token && !(token.IsSymbol(end) || token.Is(end)))
            {
                if (token.Kind == PascalTokenKind.Identifier) { Use(scope); }
                Next();
            }
        }

        private void Use(PascalScope scope, bool inWith = false)
        {
            if (Current is not { Kind: PascalTokenKind.Identifier } token) { return; }
            bool afterDot = _at > 0 && Previous() is { } previous && previous.IsSymbol(".");
            _program.References.Add(new(token, scope, afterDot, inWith));
        }

        private PascalDeclaration Declare(PascalToken name, PascalDeclarationKind kind, PascalScope scope)
        {
            PascalDeclaration declaration = new(name.Text, kind, name, scope);
            scope.Declarations.Add(declaration);
            _program.Declarations.Add(declaration);
            _declared.TryAdd(name, declaration);
            TakePending(declaration);
            _statement.Add(declaration);
            return declaration;
        }

        private void TakePending(PascalDeclaration declaration)
        {
            if (_pending is null) { return; }
            declaration.Doc = _pending;
            _pending = null;
        }

        // Ends a declaration: a documentation comment after it on the same line documents what it declared that has
        // none.
        private void EndStatement()
        {
            int line = _at > 0 ? _tokens[_at - 1].EndLine : -1;
            string? file = _at > 0 ? _tokens[_at - 1].File : null;
            if (_at < _tokens.Count
                && _tokens[_at] is { Kind: PascalTokenKind.DocComment } trailing
                && trailing.Line == line
                && trailing.File == file)
            {
                PascalDocComment doc = PascalDocComment.Parse(trailing);
                List<PascalDeclaration> undocumented = [.. _statement.Where(declaration => declaration.Doc is null)];
                if (undocumented.Count > 0)
                {
                    foreach (PascalDeclaration declaration in undocumented) { declaration.Doc = doc; }
                }
                else
                {
                    _program.StrayDocs.Add(doc);
                }

                _at++;
            }

            _statement.Clear();
        }

        // Moves to the next significant token, taking documentation comments as pending for the next declaration.
        private int Skip()
        {
            while (_at < _tokens.Count && _tokens[_at].Kind == PascalTokenKind.DocComment)
            {
                // One that trails code on its line documents the undocumented names its statement declared before
                // it; with none, it documents nothing. One on a line of its own documents the next declaration.
                PascalToken doc = _tokens[_at];
                PascalToken? before = _at > 0 ? _tokens[_at - 1] : null;
                bool trailing = before is not null
                    && before.Kind != PascalTokenKind.DocComment
                    && before.EndLine == doc.Line
                    && before.File == doc.File;

                if (trailing)
                {
                    List<PascalDeclaration> targets = StatementBefore(doc);
                    PascalDocComment parsed = PascalDocComment.Parse(doc);
                    if (targets.Count == 0) { _program.StrayDocs.Add(parsed); }
                    foreach (PascalDeclaration target in targets) { target.Doc = parsed; }
                    _at++;
                    continue;
                }

                if (_pending is { } stray) { _program.StrayDocs.Add(stray); }
                _pending = PascalDocComment.Parse(doc);
                _at++;
            }

            return _at;
        }

        private void Next()
        {
            if (Skip() < _tokens.Count) { _at++; }

            // A documentation comment is pending only up to the next statement: a ";" or BEGIN that ends one drops it.
            if (_pending is not null && _at > 0 && (_tokens[_at - 1].IsSymbol(";") || _tokens[_at - 1].Is("BEGIN")))
            {
                _program.StrayDocs.Add(_pending);
                _pending = null;
            }
        }

        private PascalToken? Previous()
        {
            for (int index = _at - 1; index >= 0; index--)
            {
                if (_tokens[index].Kind != PascalTokenKind.DocComment) { return _tokens[index]; }
            }

            return null;
        }

        private bool IsSymbol(int ahead, string symbol)
        {
            int index = Skip();
            for (int seen = 0; index < _tokens.Count; index++)
            {
                if (_tokens[index].Kind == PascalTokenKind.DocComment) { continue; }
                if (seen++ == ahead) { return _tokens[index].IsSymbol(symbol); }
            }

            return false;
        }

        // The undocumented declarations of the statement a trailing comment ends, at its own level: back to the ";",
        // BEGIN or declaration keyword that starts the statement, not inside a "(" or RECORD the comment is outside of,
        // and not past one it is inside of.
        private List<PascalDeclaration> StatementBefore(PascalToken doc)
        {
            const int Reach = 500;
            List<PascalDeclaration> found = [];
            int level = 0;
            for (int index = _at - 1; index >= 0 && index >= _at - Reach; index--)
            {
                PascalToken token = _tokens[index];
                if (token.File != doc.File) { break; }
                if (token.Kind == PascalTokenKind.DocComment) { continue; }
                if (token.IsSymbol(")") || token.Is("END")) { level++; }
                else if (token.IsSymbol("(") || token.Is("RECORD"))
                {
                    if (--level < 0) { break; }
                }
                else if (level == 0 && StartsStatement(token)) { break; }
                else if (level == 0
                    && _declared.TryGetValue(token, out PascalDeclaration? declaration)
                    && declaration.Doc is null)
                {
                    found.Add(declaration);
                }
            }

            return found;
        }

        // Whether a token starts a declaration's or statement's text, so a trailing comment's reach ends there.
        private static bool StartsStatement(PascalToken token) =>
            token.IsSymbol(";")
                || StartsBlock(token)
                || token.Is("PROGRAM")
                || token.Is("UNIT")
                || token.Is("INTERFACE");

        // Whether the token is the last, as a program's final "." is.
        private bool IsEndOfProgram() => Skip() + 1 >= _tokens.Count;

        // Whether a token can only start a declaration, so a statement part that meets it was left without its END.
        private static bool StartsDeclaration(PascalToken token) =>
            token.Is("PROCEDURE")
                || token.Is("FUNCTION")
                || token.Is("SEGMENT")
                || token.Is("CONST")
                || token.Is("TYPE")
                || token.Is("LABEL")
                || token.Is("IMPLEMENTATION");

        private bool IsKeyword(int ahead, string word)
        {
            int index = Skip();
            for (int seen = 0; index < _tokens.Count; index++)
            {
                if (_tokens[index].Kind == PascalTokenKind.DocComment) { continue; }
                if (seen++ == ahead) { return _tokens[index].Is(word); }
            }

            return false;
        }

        private void SkipTo(string symbol)
        {
            while (Current is { } token && !token.IsSymbol(symbol)) { Next(); }
        }
    }
}
