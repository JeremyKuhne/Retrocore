// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Debug;

/// <summary>
///  A revision of an image file the user saw and agreed to replace: the file as a conflict showed it, or as it was
///  when they chose it for Save As.
/// </summary>
/// <param name="Sha256">
///  The revision's SHA-256, or null for no file there, as an image deleted since its disk was read from it.
/// </param>
internal sealed record Overwrite(string? Sha256);
