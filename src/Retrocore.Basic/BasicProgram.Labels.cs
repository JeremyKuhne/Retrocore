// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using System.Text.RegularExpressions;

namespace Retrocore.Basic;

public sealed partial class BasicProgram
{
    // The words a line number follows, longest first where one starts another; and whether each takes a list
    // (ON X GOTO a,b) and must have a line (GOTO).
    private static readonly (string Word, bool List, bool Required)[] s_jumps =
    [
        ("GOSUB", true, true),
        ("GOTO", true, true),
        ("THEN", false, false),
        ("ELSE", false, false),
        ("RESUME", false, false),
        ("RESTORE", false, false),
        ("DELETE", false, false),
        ("LLIST", false, false),
        ("LIST", false, false),
        ("EDIT", false, false),
        ("DEL", false, false),
        ("RUN", false, false)
    ];

    /// <summary>
    ///  Finds where a statement line names a label in place of a line number.
    /// </summary>
    /// <remarks>
    ///  <para>
    ///   A name after GOTO or GOSUB, and each in an ON list, is always a label, since BASIC takes only numbers there;
    ///   Integer BASIC takes expressions there, so for it a name is a label only when one of that name is defined.
    ///   After THEN, ELSE, RUN, LIST, RESUME and the like, a name is a label only when one of that name is defined
    ///   and nothing but the statement's end follows it, so <c>THEN A = 1</c> stays an assignment.
    ///  </para>
    /// </remarks>
    /// <param name="dialect">The dialect, for its remarks.</param>
    /// <param name="text">The statements.</param>
    /// <param name="labels">The labels defined.</param>
    /// <returns>
    ///  Each reference: where it is, the label's uppercase name, whether it must be a label, and the word it follows.
    /// </returns>
    public static List<(int Start, int End, string Name, bool Required, string Word)> LabelReferences(
        BasicDialect dialect,
        string text,
        IReadOnlyDictionary<string, BasicLabel> labels)
    {
        ArgumentNullException.ThrowIfNull(dialect);
        ArgumentNullException.ThrowIfNull(text);
        ArgumentNullException.ThrowIfNull(labels);
        List<(int, int, string, bool, string)> references = [];
        bool inString = false;
        for (int index = 0; index < text.Length; index++)
        {
            char character = text[index];
            if (inString)
            {
                inString = character != '"';
                continue;
            }

            if (character == '"')
            {
                inString = true;
                continue;
            }

            if (character == '\'' && (dialect == BasicDialect.Level2 || dialect == BasicDialect.Mbasic || dialect is ColorBasicDialect))
            {
                break;
            }

            // The PET's CRUNCH takes the first reserved word in token order at each place and goes on past it, with no
            // word boundaries, so THEN right after a digit is a jump and the end of FOR and an EM after it are no REM.
            // BASIC 1 skips spaces inside a word too, so R E M is a remark there.
            if (dialect is PetBasicDialect)
            {
                // BASIC 2 and 4's GO TO, with spaces between, is the GO token then TO, a jump all the same.
                if (!Spaced(dialect) && GoTo().Match(text, index) is { Success: true } go && go.Index == index)
                {
                    bool sub = go.Groups["word"].Value.Equals("SUB", StringComparison.OrdinalIgnoreCase);
                    index = Targets(text, index + go.Length, sub ? s_jumps[0] : s_jumps[1], labels, references) - 1;
                    continue;
                }

                (string? word, int length) = KeywordAt(dialect, text, index);
                if (word is null) { continue; }
                if (word == "REM") { break; }
                if (word == "DATA")
                {
                    index = SkipData(text, index);
                    continue;
                }

                // The word found is the jump: CRUNCH takes it whatever comes before, as in IF A=1THEN.
                int spacedJump = Array.FindIndex(s_jumps, candidate => candidate.Word == word);
                if (spacedJump >= 0)
                {
                    index = Targets(text, index + length, s_jumps[spacedJump], labels, references) - 1;
                    continue;
                }

                index += length - 1;
                continue;
            }

            // BBC BASIC finds words only in capitals, so reminder is a name, and a * at a statement's start hands the
            // rest of the line to the MOS, so *RENAME GOTO done is a file name, not a jump.
            if (dialect is BbcBasicDialect)
            {
                if (character == '*' && StatementStart(text, index)) { break; }
                if (string.CompareOrdinal(text, index, "REM", 0, 3) == 0) { break; }
                if (string.CompareOrdinal(text, index, "DATA", 0, 4) == 0)
                {
                    index = SkipData(text, index);
                    continue;
                }

                if (!char.IsAsciiLetterUpper(character)) { continue; }
            }

            // Business BASIC and MBASIC take REM and DATA only set apart from names, as REMAIN is a variable.
            bool separated = dialect == BasicDialect.BusinessBasic || dialect == BasicDialect.Mbasic;
            if (separated ? SetApart(text, index, "REM") : StartsWord(text, index, "REM")) { break; }
            if (separated ? SetApart(text, index, "DATA") : StartsWord(text, index, "DATA"))
            {
                index = SkipData(text, index);
                continue;
            }

            if (Jump(dialect, text, index, out int after) is not { } jump) { continue; }
            index = Targets(text, after, jump, labels, references) - 1;
        }

        // Integer BASIC's and BBC BASIC's GOTO and GOSUB take any expression, such as GOSUB T, so a name is a label
        // only when one of that name is defined.
        if (dialect is IntegerBasicDialect or BbcBasicDialect)
        {
            references.RemoveAll(reference => !labels.ContainsKey(reference.Item3));
            for (int index = 0; index < references.Count; index++)
            {
                references[index] = references[index] with { Item4 = false };
            }
        }

        return references;
    }

    /// <summary>
    ///  Gets a line's statements with each label it names replaced by its line's number, as they are stored.
    /// </summary>
    /// <param name="dialect">The dialect.</param>
    /// <param name="line">The line.</param>
    /// <param name="labels">The labels.</param>
    /// <returns>The statements.</returns>
    internal static string Resolved(BasicDialect dialect, BasicTextLine line, IReadOnlyDictionary<string, BasicLabel> labels) =>
        Resolve(dialect, line, [with(labels)], []);

    // Puts the numbers of the labels a line names in place of their names.
    private static string Resolve(
        BasicDialect dialect,
        BasicTextLine line,
        Dictionary<string, BasicLabel> labels,
        List<BasicDiagnostic> diagnostics)
    {
        string text = line.Statements;

        // BASIC 1 may spell a jump G O T O, which holds no GO.
        if (labels.Count == 0 && !Spaced(dialect) && !text.Contains("GO", StringComparison.OrdinalIgnoreCase))
        {
            return text;
        }

        List<(int Start, int End, string Name, bool Required, string Word)> references = LabelReferences(dialect, text, labels);
        for (int index = references.Count - 1; index >= 0; index--)
        {
            (int start, int end, string name, bool required, _) = references[index];
            if (labels.TryGetValue(name, out BasicLabel? label))
            {
                text = $"{text[..start]}{label.Number}{text[end..]}";
            }
            else if (required)
            {
                Error(diagnostics, line.Line, $"There is no label {name}.", line.Column + start, line.Column + end);
            }
        }

        return text;
    }

    // The jump word starting at an index, and where the text after it starts. Business BASIC takes a word only with
    // a separator before and after it, a period being part of a name, so GOTOCOUNT=1 is an assignment there.
    private static (string Word, bool List, bool Required)? Jump(BasicDialect dialect, string text, int index, out int after)
    {
        after = index;
        // Business BASIC and MBASIC take a word only set apart from names, which hold periods in both.
        bool separated = dialect == BasicDialect.BusinessBasic || dialect == BasicDialect.Mbasic;
        if (index > 0 && InName(text[index - 1], separated)) { return null; }
        int end = -1;
        (string Word, bool List, bool Required)? found = null;
        if (GoTo().Match(text, index) is { Success: true } go && go.Index == index)
        {
            // GO TO, and Color BASIC's GO SUB, with spaces between.
            end = index + go.Length;
            found = go.Groups["word"].Value.Equals("SUB", StringComparison.OrdinalIgnoreCase) ? s_jumps[0] : s_jumps[1];
        }
        else
        {
            bool spaced = Spaced(dialect);
            foreach ((string word, bool list, bool required) jump in s_jumps)
            {
                int length = spaced
                    ? SpacedLength(text, index, jump.word)
                    : string.Compare(text, index, jump.word, 0, jump.word.Length, StringComparison.OrdinalIgnoreCase) == 0 ? jump.word.Length : -1;

                if (length >= 0)
                {
                    end = index + length;
                    found = jump;
                    break;
                }
            }
        }

        if (found is null) { return null; }
        if (separated && end < text.Length && InName(text[end], separated)) { return null; }
        after = end;
        return found;
    }

    // Whether a character can be part of a name; Business BASIC's and MBASIC's names hold periods.
    private static bool InName(char character, bool periods) =>
        char.IsAsciiLetterOrDigit(character) || (periods && character == '.');

    // Reads the line numbers and labels after a jump word: one, or a list after GOTO and GOSUB.
    private static int Targets(
        string text,
        int at,
        (string Word, bool List, bool Required) jump,
        IReadOnlyDictionary<string, BasicLabel> labels,
        List<(int, int, string, bool, string)> references)
    {
        while (true)
        {
            at = SkipSpaces(text, at);
            if (Name().Match(text, at) is { Success: true } name && name.Index == at)
            {
                string label = name.Groups["name"].Value.ToUpperInvariant();
                int end = at + name.Length;
                int next = SkipSpaces(text, end);
                bool alone = next >= text.Length || text[next] == ':' || StartsWord(text, next, "ELSE");
                if (!jump.Required && !(labels.ContainsKey(label) && alone))
                {
                    // Not a label, such as GOTO in THEN GOTO: the scan goes on from the word itself.
                    return at;
                }

                references.Add((at, end, label, jump.Required, jump.Word));
                at = end;
            }
            else
            {
                while (at < text.Length && char.IsAsciiDigit(text[at])) { at++; }
            }

            int separator = SkipSpaces(text, at);
            if (!jump.List || separator >= text.Length || text[separator] != ',') { return at; }
            at = separator + 1;
        }
    }

    private static int SkipSpaces(string text, int at)
    {
        while (at < text.Length && text[at] == ' ') { at++; }
        return at;
    }

    // Skips a DATA statement, which ends at a colon outside quotes.
    private static int SkipData(string text, int index)
    {
        bool inString = false;
        for (int at = index; at < text.Length; at++)
        {
            if (text[at] == '"') { inString = !inString; }
            if (text[at] == ':' && !inString) { return at; }
        }

        return text.Length;
    }

    // Whether a word starts at an index with no name's character, a period included, before or after it.
    private static bool SetApart(string text, int index, string word)
    {
        if (index > 0 && InName(text[index - 1], periods: true)) { return false; }
        if (string.Compare(text, index, word, 0, word.Length, StringComparison.OrdinalIgnoreCase) != 0)
        {
            return false;
        }

        int end = index + word.Length;
        return end >= text.Length || !InName(text[end], periods: true);
    }

    // Whether a place starts a statement: the line's start, after a colon, or after THEN or ELSE.
    private static bool StatementStart(string text, int index)
    {
        int before = index - 1;
        while (before >= 0 && text[before] == ' ') { before--; }
        if (before < 0 || text[before] == ':') { return true; }
        return before >= 3 && string.CompareOrdinal(text, before - 3, "THEN", 0, 4) == 0
            || before >= 3 && string.CompareOrdinal(text, before - 3, "ELSE", 0, 4) == 0;
    }

    private static bool StartsWord(string text, int index, string word, bool spaced = false)
    {
        if (index > 0 && char.IsAsciiLetterOrDigit(text[index - 1])) { return false; }
        if (!spaced)
        {
            return string.Compare(text, index, word, 0, word.Length, StringComparison.OrdinalIgnoreCase) == 0;
        }

        return SpacedLength(text, index, word) >= 0;
    }

    // The first reserved word in token order at an index, as the PET's CRUNCH finds it (on BASIC 1 with spaces skipped
    // inside it), and the characters it takes; none when the character there starts no word.
    private static (string? Word, int Length) KeywordAt(BasicDialect dialect, string text, int index)
    {
        bool spaced = Spaced(dialect);
        foreach (string keyword in dialect.Keywords)
        {
            int length = spaced
                ? SpacedLength(text, index, keyword)
                : string.Compare(text, index, keyword, 0, keyword.Length, StringComparison.OrdinalIgnoreCase) == 0 ? keyword.Length : -1;

            if (length > 0) { return (keyword, length); }
        }

        return (null, 0);
    }

    // Whether a dialect skips spaces inside reserved words, as BASIC 1's RESCON does.
    private static bool Spaced(BasicDialect dialect) => dialect is PetBasicDialect { Version: 1 };

    // How many characters a reserved word takes from an index with spaces between its letters, or -1 when it is not
    // there.
    private static int SpacedLength(string text, int index, string word)
    {
        int at = index;
        for (int letter = 0; letter < word.Length; letter++, at++)
        {
            while (letter > 0 && at < text.Length && text[at] == ' ') { at++; }
            if (at >= text.Length || char.ToUpperInvariant(text[at]) != word[letter]) { return -1; }
        }

        return at - index;
    }

    [GeneratedRegex(@"GO\s+(?<word>TO|SUB)", RegexOptions.IgnoreCase)]
    private static partial Regex GoTo();

    [GeneratedRegex(@"@?(?<name>[A-Za-z_][A-Za-z0-9_]*)")]
    private static partial Regex Name();
}
