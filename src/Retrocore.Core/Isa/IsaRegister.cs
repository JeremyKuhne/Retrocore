// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Isa;

/// <summary>
///  A CPU register.
/// </summary>
/// <param name="Name">The name, as the native syntax and debugger write it.</param>
/// <param name="Bits">The width in bits.</param>
public sealed record IsaRegister(string Name, int Bits);
