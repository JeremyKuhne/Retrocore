// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Isa;

/// <summary>
///  A flag bit within a status register.
/// </summary>
/// <param name="Name">The flag's letter or name, such as <c>C</c>.</param>
/// <param name="Register">The register holding it.</param>
/// <param name="Bit">Its bit number.</param>
public sealed record IsaFlag(string Name, string Register, int Bit)
{
    /// <summary>
    ///  Gets the words documentation names the flag by, the same on every CPU, such as <c>carry</c>. A flag with
    ///  none, such as the Z80's undocumented bits, cannot be named in documentation.
    /// </summary>
    public IReadOnlyList<string> Words { get; init; } = [];

    /// <summary>
    ///  Gets what the flag means, for hover text.
    /// </summary>
    public string Description { get; init; } = "";
}
