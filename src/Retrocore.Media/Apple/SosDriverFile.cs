// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using System.Text;

namespace Retrocore.Media;

/// <summary>
///  A <c>SOS.DRIVER</c> file: the drivers SOS loads at boot, each relocatable.
/// </summary>
/// <remarks>
///  <para>
///   The file starts with <c>SOS DRVR</c>, then a comment (a 2-byte length and its text), then the drivers. Each
///   driver is a comment, its code assembled at origin 0, and its relocation table, each with a 2-byte length;
///   a comment length of <c>$FFFF</c> ends the file. A driver's code starts with its first device information
///   block (DIB): the link to the next, the entry point, then the device's name as a length and 15 characters.
///  </para>
///  <para>
///   The relocation table lists the offsets, 2 bytes each, of the code's words that hold addresses in the code.
///   SOS adds the driver's load address to each as it moves the driver into place.
///  </para>
/// </remarks>
public sealed class SosDriverFile
{
    private static readonly byte[] s_signature = "SOS DRVR"u8.ToArray();

    private SosDriverFile(string comment, IReadOnlyList<SosDriver> drivers)
    {
        Comment = comment;
        Drivers = drivers;
    }

    /// <summary>
    ///  Gets the file's own comment.
    /// </summary>
    public string Comment { get; }

    /// <summary>
    ///  Gets the drivers, in the file's order.
    /// </summary>
    public IReadOnlyList<SosDriver> Drivers { get; }

    /// <summary>
    ///  Reads a driver file.
    /// </summary>
    /// <param name="data">The file's contents.</param>
    /// <returns>Its drivers.</returns>
    /// <exception cref="InvalidDataException">The data is not a driver file.</exception>
    public static SosDriverFile Read(ReadOnlySpan<byte> data)
    {
        if (data.Length < 10 || !data[..8].SequenceEqual(s_signature))
        {
            throw new InvalidDataException("A SOS.DRIVER file starts with \"SOS DRVR\".");
        }

        int offset = 8;
        string comment = Encoding.ASCII.GetString(Field(data, ref offset));
        List<SosDriver> drivers = [];
        while (offset + 2 <= data.Length && (data[offset] | (data[offset + 1] << 8)) != 0xFFFF)
        {
            string driverComment = Encoding.ASCII.GetString(Field(data, ref offset));
            byte[] code = Field(data, ref offset).ToArray();
            ReadOnlySpan<byte> table = Field(data, ref offset);
            int[] relocations = new int[table.Length / 2];
            for (int index = 0; index < relocations.Length; index++)
            {
                relocations[index] = table[index * 2] | (table[(index * 2) + 1] << 8);
            }

            drivers.Add(new SosDriver(driverComment, code, relocations));
        }

        return new SosDriverFile(comment, drivers);
    }

    // A 2-byte length and that many bytes.
    private static ReadOnlySpan<byte> Field(ReadOnlySpan<byte> data, ref int offset)
    {
        if (offset + 2 > data.Length) { throw new InvalidDataException("The driver file ends inside a length."); }
        int length = data[offset] | (data[offset + 1] << 8);
        offset += 2;
        if (offset + length > data.Length) { throw new InvalidDataException("The driver file ends inside a field."); }
        ReadOnlySpan<byte> field = data.Slice(offset, length);
        offset += length;
        return field;
    }
}
