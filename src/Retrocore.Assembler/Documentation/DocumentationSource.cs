// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Documentation;

/// <summary>
///  One document of the bibliography that <c>Also:</c> entries cite by key.
/// </summary>
/// <param name="Key">The key, such as <c>A2RM</c>.</param>
/// <param name="Title">The document's title.</param>
/// <param name="Year">When it was published, as written.</param>
/// <param name="Publisher">Who published it.</param>
/// <param name="Link">Where to read it, or empty.</param>
public sealed record DocumentationSource(string Key, string Title, string Year, string Publisher, string Link)
{
    /// <summary>
    ///  Gets the title with its year and publisher, as hover shows it.
    /// </summary>
    public string Description => string.Join(", ", new[] { Title, Publisher, Year }.Where(part => part.Length != 0));
}
