// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Media;
using System.Text.Json.Nodes;

namespace Retrocore.Debug;

/// <summary>
///  A changed disk as a checkpoint takes it, under the machine's lock.
/// </summary>
/// <param name="Medium">Its medium id.</param>
/// <param name="Type">What kind of medium it is, such as <c>WozDisk</c>, to read it back as.</param>
/// <param name="Version">Its version.</param>
/// <param name="Snapshot">Its snapshot, or null when the journal already holds this version.</param>
/// <param name="Entry">Its drive, label, format, image and whether the machine ejected it.</param>
/// <param name="MidWrite">Whether its drive was writing as the snapshot was taken.</param>
/// <param name="Waiting">
///  Whether its snapshot waits for its drive to stop writing: the journal keeps the version it holds already.
/// </param>
internal sealed record JournalDisk(
    Guid Medium,
    string Type,
    long Version,
    MediumSnapshot? Snapshot,
    JsonObject Entry,
    bool MidWrite = false,
    bool Waiting = false);
