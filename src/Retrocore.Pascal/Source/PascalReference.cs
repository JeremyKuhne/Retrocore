// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Pascal.Source;

/// <summary>
///  A name the source uses, and the scope it is used in.
/// </summary>
/// <param name="Token">The name's token.</param>
/// <param name="Scope">The scope it is in.</param>
/// <param name="AfterDot">Whether it follows a <c>.</c>, so that it names a field.</param>
/// <param name="InWith">Whether it is in a <c>WITH</c> statement's body, so that it may name a field.</param>
public sealed record PascalReference(PascalToken Token, PascalScope Scope, bool AfterDot, bool InWith = false);
