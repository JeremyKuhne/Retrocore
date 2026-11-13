// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using System.Text;

namespace Retrocore.Media;

/// <summary>
///  A driver in a <c>SOS.DRIVER</c> file.
/// </summary>
/// <param name="Comment">Its comment, such as its copyright.</param>
/// <param name="Code">Its code, assembled at origin 0, starting with its first DIB.</param>
/// <param name="Relocations">The offsets of the words that SOS relocates.</param>
public sealed record SosDriver(string Comment, byte[] Code, int[] Relocations)
{
    /// <summary>
    ///  Gets the name of the driver's first device, such as <c>.CONSOLE</c>.
    /// </summary>
    public string Name => Code.Length >= 20 ? Encoding.ASCII.GetString(Code, 5, Code[4] & 0xF) : "";
}
