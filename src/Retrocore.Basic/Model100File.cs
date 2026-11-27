// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Basic;

/// <summary>
///  A file in the Model 100's RAM.
/// </summary>
/// <param name="Name">The name and extension, as the menu shows it, such as <c>PROG.BA</c>.</param>
/// <param name="Type">The kind.</param>
/// <param name="Address">Where its bytes start.</param>
public sealed record Model100File(string Name, Model100FileType Type, int Address);
