// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Assembler;

/// <summary>
///  Decodes high-bit, CR-separated Merlin text extracted by a caller from a disk image.
/// </summary>
public static class MerlinText
{
    /// <summary>
    ///  Clears character high bits and omits trailing NUL padding.
    /// </summary>
    /// <param name="bytes">The already extracted text bytes, not a whole disk image.</param>
    /// <param name="path">The diagnostic source path.</param>
    /// <returns>A Merlin-tagged source document.</returns>
    public static AssemblySource Decode(ReadOnlySpan<byte> bytes, string path = "")
    {
        int length = bytes.Length;
        while (length != 0 && (bytes[length - 1] & 0x7F) == 0) { length--; }
        char[] text = new char[length];
        for (int index = 0; index < length; index++)
        {
            byte value = (byte)(bytes[index] & 0x7F);
            if (value == 0) { throw new ArgumentException("Merlin text contains an embedded NUL.", nameof(bytes)); }
            text[index] = (char)value;
        }

        return new(new string(text), path, AssemblyDialect.Merlin);
    }
}
