// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Pascal;

/// <summary>
///  A procedure or function a unit's interface declares.
/// </summary>
/// <param name="Name">Its name.</param>
/// <param name="IsFunction">Whether it is a function.</param>
/// <param name="Parameters">Its parameters, in the order they are declared.</param>
/// <param name="Result">A function's result type's name, such as <c>INTEGER</c>; null for a procedure.</param>
public sealed record PascalUnitProcedure(string Name, bool IsFunction, IReadOnlyList<PascalUnitParameter> Parameters, string? Result);
