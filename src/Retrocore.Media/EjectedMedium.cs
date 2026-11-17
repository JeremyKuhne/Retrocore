// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Media;

/// <summary>
///  A medium the machine ejected from a drive by itself, and what the drive called it.
/// </summary>
/// <param name="Medium">The medium.</param>
/// <param name="Label">What the host called it, such as its image's path.</param>
/// <param name="Format">Its image format, such as <c>2MG</c>.</param>
public sealed record EjectedMedium(IMedium Medium, string Label, string Format);
