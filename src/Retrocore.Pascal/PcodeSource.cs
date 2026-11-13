// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Pascal;

/// <summary>
///  A code file written as p-code source.
/// </summary>
/// <param name="Text">The source.</param>
/// <param name="Notes">The segments it writes as data, and why; empty when it reads them all.</param>
public sealed record PcodeSource(string Text, IReadOnlyList<string> Notes);
