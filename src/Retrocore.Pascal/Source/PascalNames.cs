// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Pascal.Source;

/// <summary>
///  Apple Pascal's names: what the Compiler reads of them, its reserved words and its standard identifiers.
/// </summary>
public static class PascalNames
{
    /// <summary>
    ///  The letters of a name the Compiler reads.
    /// </summary>
    public const int Significant = 8;

    // The reserved words of Apple Pascal: 1.1's, as its interpreter's IdSearch table has them (each read to 8
    // letters), and OTHERWISE, which 1.3's Compiler adds (its IDSCAN's table, where SEPARATE is not one). Every
    // version's sources share names, so a name is none of any version's.
    private static readonly HashSet<string> s_keywords =
    [
        .. new[]
        {
            "AND", "ARRAY", "BEGIN", "CASE", "CONST", "DIV", "DO", "DOWNTO", "ELSE", "END", "EXTERNAL", "FILE", "FOR",
            "FORWARD", "FUNCTION", "GOTO", "IF", "IMPLEMENTATION", "IN", "INTERFACE", "LABEL", "MOD", "NOT", "OF", "OR",
            "OTHERWISE",
            "PACKED", "PROCEDURE", "PROGRAM", "RECORD", "REPEAT", "SEGMENT", "SEPARATE", "SET", "THEN", "TO", "TYPE",
            "UNIT", "UNTIL", "USES", "VAR", "WHILE", "WITH"
        }.Select(Key)
    ];

    // The standard identifiers of Apple Pascal and Apple III Pascal: the predeclared types, constants, files,
    // procedures and functions, and the words that are reserved only where they appear (INTRINSIC, CODE, DATA).
    private static readonly HashSet<string> s_standard =
    [
        .. new[]
        {
            "INTEGER", "REAL", "BOOLEAN", "CHAR", "STRING", "TEXT", "INTERACTIVE", "TRUE", "FALSE", "NIL", "MAXINT",
            "INPUT", "OUTPUT", "KEYBOARD", "READ", "READLN", "WRITE", "WRITELN", "EOF", "EOLN", "GET", "PUT", "RESET",
            "REWRITE", "CLOSE", "SEEK", "PAGE", "ORD", "CHR", "SUCC", "PRED", "ODD", "ABS", "SQR", "TRUNC", "ROUND",
            "NEW", "DISPOSE", "MARK", "RELEASE", "MEMAVAIL", "VARAVAIL", "VARNEW", "VARDISPOSE", "LENGTH", "COPY",
            "CONCAT", "POS", "INSERT", "DELETE", "STR", "MOVELEFT", "MOVERIGHT", "FILLCHAR", "SIZEOF", "SCAN",
            "UNITREAD", "UNITWRITE", "UNITCLEAR", "UNITSTATUS", "UNITBUSY", "UNITWAIT", "BLOCKREAD", "BLOCKWRITE",
            "IORESULT", "GOTOXY", "EXIT", "HALT", "TREESEARCH", "IDSEARCH", "TIME", "PWROFTEN", "LOG", "EXP", "SQRT",
            "SIN", "COS", "ATAN", "LN", "INTRINSIC", "CODE", "DATA"
        }.Select(Key)
    ];

    /// <summary>
    ///  Gets what the Compiler reads of a name: its first 8 letters in upper case, underscores left out.
    /// </summary>
    /// <param name="name">The name.</param>
    /// <returns>Its key.</returns>
    public static string Key(string name)
    {
        string upper = name.Replace("_", "", StringComparison.Ordinal).ToUpperInvariant();
        return upper.Length > Significant ? upper[..Significant] : upper;
    }

    /// <summary>
    ///  Gets whether a word is reserved.
    /// </summary>
    /// <param name="word">The word, in any case.</param>
    /// <returns>Whether it is.</returns>
    public static bool IsKeyword(string word) => s_keywords.Contains(Key(word));

    /// <summary>
    ///  Gets whether a name is one of Pascal's standard identifiers.
    /// </summary>
    /// <param name="name">The name, in any case.</param>
    /// <returns>Whether it is.</returns>
    public static bool IsStandard(string name) => s_standard.Contains(Key(name));
}
