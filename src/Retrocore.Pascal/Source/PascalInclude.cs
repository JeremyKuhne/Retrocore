// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Pascal.Source;

/// <summary>
///  An include directive, <c>(*$I NAME.TEXT*)</c>, and the file it names.
/// </summary>
/// <param name="Token">The directive.</param>
/// <param name="Name">The name it gives, without a volume.</param>
/// <param name="Path">The file it reads, or null when there is none.</param>
public sealed record PascalInclude(PascalToken Token, string Name, string? Path);
