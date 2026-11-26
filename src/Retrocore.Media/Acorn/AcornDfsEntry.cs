// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Media.Acorn;

/// <summary>
///  A file in a DFS catalogue and the sector it starts at.
/// </summary>
/// <param name="File">The file.</param>
/// <param name="StartSector">Its first sector, counting from track 0's sector 0.</param>
public sealed record AcornDfsEntry(AcornDfsFile File, int StartSector);
