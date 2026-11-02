// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Debug.Language;

/// <summary>
///  What a References request includes.
/// </summary>
/// <param name="IncludeDeclaration">Whether the definition is one of the references.</param>
internal sealed record ReferenceContext(bool IncludeDeclaration);
