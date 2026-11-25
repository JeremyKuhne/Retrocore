// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Media.Floppy;

/// <summary>
///  A sector a DMK track's table finds, with where its data field is, so a save writes it back in place.
/// </summary>
/// <param name="Sector">The sector as read.</param>
/// <param name="Id">The offset of its ID address mark in the track.</param>
/// <param name="Data">The offset of its data address mark in the track.</param>
/// <param name="Step">
///  How far apart the field's bytes are: 2 for a doubled single-density byte, and 1 otherwise.
/// </param>
internal readonly record struct DmkField(FloppySector Sector, int Id, int Data, int Step);
