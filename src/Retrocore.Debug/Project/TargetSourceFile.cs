// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Assembler;

namespace Retrocore.Debug.Project;

/// <summary>
///  A source file a target assembles, in the order it assembles them.
/// </summary>
/// <param name="Path">The file's full path.</param>
/// <param name="Dialect">The dialect, or null for native unless its first-line pragma names one.</param>
internal sealed record TargetSourceFile(string Path, AssemblyDialect? Dialect);