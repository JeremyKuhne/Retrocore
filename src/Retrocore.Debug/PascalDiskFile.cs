// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Debug;

/// <summary>
///  A file on an Apple Pascal disk.
/// </summary>
/// <param name="Name">Its name.</param>
/// <param name="Kind">Its kind: <c>Code</c>, <c>Text</c>, <c>Data</c> and so on.</param>
/// <param name="Length">Its length in bytes.</param>
/// <param name="Modified">When it was last changed, where the volume says.</param>
internal sealed record PascalDiskFile(string Name, string Kind, int Length, DateOnly? Modified);
