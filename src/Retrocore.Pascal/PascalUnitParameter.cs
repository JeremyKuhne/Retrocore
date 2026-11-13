// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Pascal;

/// <summary>
///  A parameter of a unit's procedure.
/// </summary>
/// <param name="Name">Its name.</param>
/// <param name="IsReference">Whether it is a <c>VAR</c> parameter.</param>
/// <param name="Type">Its type's name, such as <c>INTEGER</c>; null for an untyped <c>VAR</c> parameter.</param>
public sealed record PascalUnitParameter(string Name, bool IsReference, string? Type);
