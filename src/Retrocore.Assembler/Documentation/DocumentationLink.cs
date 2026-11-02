// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Documentation;

/// <summary>
///  A link in documentation text: <c>&lt;Target&gt;</c>, <c>&lt;text at Target&gt;</c> or a bare URL.
/// </summary>
/// <param name="Text">The text to show.</param>
/// <param name="Target">The target as written.</param>
/// <param name="Start">The index of the link in its text.</param>
/// <param name="Length">The length of the link in its text.</param>
public sealed record DocumentationLink(string Text, string Target, int Start, int Length)
{
    /// <summary>
    ///  Gets whether the target is a web address.
    /// </summary>
    public bool IsUrl => Target.StartsWith("http://", StringComparison.OrdinalIgnoreCase)
        || Target.StartsWith("https://", StringComparison.OrdinalIgnoreCase);

    /// <summary>
    ///  Gets whether the target is a documentation file in the repository (<c>doc:path</c>).
    /// </summary>
    public bool IsDocument => Target.StartsWith("doc:", StringComparison.OrdinalIgnoreCase);
}
