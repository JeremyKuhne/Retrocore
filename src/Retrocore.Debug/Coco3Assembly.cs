// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Assembler;

namespace Retrocore.Debug;

/// <summary>
///  The CoCo 3's ROM, built from the SDK's sources.
/// </summary>
/// <param name="ExtendedBasic">Extended Color BASIC 1.1 with the CoCo 3's patches, at <c>$8000</c>.</param>
/// <param name="ColorBasic">Color BASIC 1.2 with the CoCo 3's patches, at <c>$A000</c>.</param>
/// <param name="Coco3">The CoCo 3's start-up and Super Extended Color BASIC, at <c>$C000</c>.</param>
/// <param name="Image">The 32 KB image, <c>$8000-$FFFF</c>.</param>
internal sealed record Coco3Assembly(AssemblyResult ExtendedBasic, AssemblyResult ColorBasic, AssemblyResult Coco3, byte[] Image);
