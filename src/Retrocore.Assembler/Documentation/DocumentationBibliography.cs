// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Documentation;

/// <summary>
///  The documents historical names come from: the table in <c>Bibliography.md</c>, whose rows are
///  <c>| Key | Title | Year | Publisher | Link |</c>.
/// </summary>
public sealed class DocumentationBibliography
{
    private readonly Dictionary<string, DocumentationSource> _sources;

    private DocumentationBibliography(Dictionary<string, DocumentationSource> sources) => _sources = sources;

    /// <summary>
    ///  Gets the documents, by key.
    /// </summary>
    public IReadOnlyDictionary<string, DocumentationSource> Sources => _sources;

    /// <summary>
    ///  Reads bibliographies' tables; a key in a later one replaces the same key in an earlier one.
    /// </summary>
    /// <param name="texts">The Markdown texts.</param>
    /// <returns>The documents.</returns>
    public static DocumentationBibliography Parse(params IEnumerable<string> texts)
    {
        Dictionary<string, DocumentationSource> sources = [with(StringComparer.Ordinal)];
        foreach (string text in texts)
        {
            foreach (string raw in text.Split('\n'))
            {
                string line = raw.Trim();
                if (!line.StartsWith('|') || !line.EndsWith('|')) { continue; }
                string[] cells = [.. line[1..^1].Split('|').Select(cell => cell.Trim())];
                if (cells.Length < 2) { continue; }
                string key = cells[0].Trim('`');

                // The header row and the separator row are not documents.
                if (key.Length == 0 || key.Equals("Key", StringComparison.OrdinalIgnoreCase) || key.All(c => c is '-' or ':'))
                {
                    continue;
                }

                sources[key] = new(key, Cell(cells, 1), Cell(cells, 2), Cell(cells, 3), Link(Cell(cells, 4)));
            }
        }

        return new(sources);
    }

    /// <summary>
    ///  Finds a document.
    /// </summary>
    /// <param name="key">Its key.</param>
    /// <returns>The document, or null.</returns>
    public DocumentationSource? Find(string key) => _sources.TryGetValue(key, out DocumentationSource? source) ? source : null;

    private static string Cell(string[] cells, int index) => index < cells.Length ? cells[index] : "";

    // A Markdown link "[text](url)" or "<url>" becomes its URL.
    private static string Link(string cell)
    {
        int open = cell.IndexOf("](", StringComparison.Ordinal);
        return open >= 0 && cell.EndsWith(')') ? cell[(open + 2)..^1] : cell.Trim('<', '>');
    }
}
