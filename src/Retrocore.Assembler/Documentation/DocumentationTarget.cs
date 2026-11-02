// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Documentation;

/// <summary>
///  The result of resolving a link target.
/// </summary>
/// <param name="Kind">What the target is.</param>
/// <param name="Name">The name to show: the resolved symbol's name, so <c>$FDED</c> shows as <c>COUT</c>.</param>
public sealed record DocumentationTarget(DocumentationTargetKind Kind, string Name)
{
    /// <summary>
    ///  Gets the documented topic, for <see cref="DocumentationTargetKind.Topic"/>.
    /// </summary>
    public DocumentationTopic? Topic { get; init; }

    /// <summary>
    ///  Gets the set the target was found in, for a topic or symbol.
    /// </summary>
    public DocumentationSet? Set { get; init; }

    /// <summary>
    ///  Gets a symbol's value.
    /// </summary>
    public long? Value { get; init; }

    /// <summary>
    ///  Gets the section of the topic the link names (<c>&lt;PLOT#Keeps&gt;</c>), or null.
    /// </summary>
    public string? Section { get; init; }

    /// <summary>
    ///  Gets the address of a web or document target, or the path of a document.
    /// </summary>
    public string? Address { get; init; }

    /// <summary>
    ///  Gets whether the target resolved to something a reader can follow.
    /// </summary>
    public bool IsResolved => Kind is not (DocumentationTargetKind.Unresolved or DocumentationTargetKind.Ambiguous);
}
