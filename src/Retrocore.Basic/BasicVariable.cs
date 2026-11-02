// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Basic;

/// <summary>
///  A simple variable or function in BASIC's variable table.
/// </summary>
/// <param name="Name">Its name as BASIC stores it, one or two characters, with its type's suffix.</param>
/// <param name="Kind">What it holds.</param>
/// <param name="Address">Where its entry starts.</param>
/// <param name="ValueAddress">Where its value starts.</param>
public sealed record BasicVariable(string Name, BasicVariableKind Kind, int Address, int ValueAddress);
