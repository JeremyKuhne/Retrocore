// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Media;
using System.Globalization;
using System.Text.Json.Nodes;

namespace Retrocore.Debug;

/// <summary>
///  A disk the host holds out of its drive: one a person discarded or reverted, kept so Undo can put it back, or one
///  the machine ejected with changes not saved, kept so it can be saved, put back or let go.
/// </summary>
/// <param name="Medium">The disk.</param>
/// <param name="Label">What its drive called it, such as its image's path.</param>
/// <param name="Format">Its image format, such as <c>2MG</c>.</param>
/// <param name="Why">
///  How it left its drive: <c>discarded</c>, <c>reverted</c> or <c>ejected</c>; or <c>discardedEjected</c>, an ejected
///  disk let go, which Undo puts back among the drive's ejected disks.
/// </param>
internal sealed record KeptDisk(IMedium Medium, string Label, string Format, string Why)
{
    /// <summary>
    ///  Gets the id the protocol names it by, such as <c>k-3f9c…</c>.
    /// </summary>
    internal string Id { get; } = $"k-{Guid.NewGuid():N}";

    /// <summary>
    ///  Gets when it left its drive, in UTC.
    /// </summary>
    internal DateTime When { get; } = DateTime.UtcNow;

    /// <summary>
    ///  Gets or sets what its drive calls it after a save, such as the image it was saved to.
    /// </summary>
    internal string Label { get; set; } = Label;

    /// <summary>
    ///  Gets or sets its image format after a save.
    /// </summary>
    internal string Format { get; set; } = Format;

    /// <summary>
    ///  Writes it as the device list gives it.
    /// </summary>
    /// <returns><c>{ id, label, format, why, when, changed }</c>.</returns>
    internal JsonObject ToJson() => new()
    {
        ["id"] = Id,
        ["label"] = Label,
        ["format"] = Format,
        ["why"] = Why,
        ["when"] = When.ToString("O", CultureInfo.InvariantCulture),
        ["changed"] = Medium.IsDirty,
    };
}
