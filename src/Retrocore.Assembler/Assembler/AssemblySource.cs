// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Assembler;

/// <summary>
///  Caller-supplied immutable source text; no file I/O or compiler-host dependency.
/// </summary>
public sealed class AssemblySource
{
    // Split when first wanted, by the documentation pass for Also: names; racing threads split alike.
    private string[]? _lines;

    // The Also: names, read when first wanted; s_noAlsoNames once read for a source that gives none. Built whole and
    // then published, so racing threads read alike.
    private Dictionary<int, (string[] Names, bool Macro)>? _alsoNames;
    private static readonly Dictionary<int, (string[] Names, bool Macro)> s_noAlsoNames = [];

    /// <summary>
    ///  Creates a source document.
    /// </summary>
    /// <param name="text">The source text.</param>
    /// <param name="path">The source identifier.</param>
    /// <param name="dialect">Optional resolver-supplied syntax metadata.</param>
    public AssemblySource(string text, string path = "", AssemblyDialect? dialect = null)
    {
        Text = text ?? throw new ArgumentNullException(nameof(text));
        Path = path ?? throw new ArgumentNullException(nameof(path));
        if (dialect is { } value && !Enum.IsDefined(value)) { throw new ArgumentOutOfRangeException(nameof(dialect)); }
        Dialect = dialect;
    }

    /// <summary>
    ///  Creates a source document whose lines the caller has already split.
    /// </summary>
    /// <param name="text">The source text.</param>
    /// <param name="lines">
    ///  The text's lines as <see cref="Documentation.DocumentationParser.Lines(string)"/> splits them, which are only
    ///  read, so a caller can share them.
    /// </param>
    /// <param name="path">The source identifier.</param>
    internal AssemblySource(string text, string[] lines, string path)
        : this(text, path) => _lines = lines;

    /// <summary>
    ///  Gets original source text.
    /// </summary>
    public string Text { get; }

    /// <summary>
    ///  Gets the text's lines without their terminators, as the documentation parser reads them. They are shared and
    ///  must not be written.
    /// </summary>
    internal string[] Lines => _lines ??= Documentation.DocumentationParser.Lines(Text);

    /// <summary>
    ///  Gets the historical names the text's <c>;; Also:</c> sections give, by the definition's line, read once for
    ///  the preprocessor and the compiler, and for every assembly a shared source is in.
    /// </summary>
    /// <value>The names and whether the line is in a macro's body, or null when the text gives none.</value>
    internal IReadOnlyDictionary<int, (string[] Names, bool Macro)>? AlsoNames
    {
        get
        {
            Dictionary<int, (string[] Names, bool Macro)> names = _alsoNames ??= AssemblyAlsoNames.Read(this) ?? s_noAlsoNames;
            return ReferenceEquals(names, s_noAlsoNames) ? null : names;
        }
    }

    /// <summary>
    ///  Gets the caller's source identifier.
    /// </summary>
    public string Path { get; }

    /// <summary>
    ///  Gets resolver-supplied dialect metadata, below a first-line pragma in precedence.
    /// </summary>
    public AssemblyDialect? Dialect { get; }
}
