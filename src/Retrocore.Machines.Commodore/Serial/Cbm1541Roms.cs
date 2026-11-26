// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Machines.Commodore.Serial;

/// <summary>
///  A 1540's or 1541's DOS 2.6: two 8K ROMs, at <c>$C000</c> and <c>$E000</c>.
/// </summary>
/// <remarks>
///  <para>
///   Both drives have 325302-01 at <c>$C000</c>. The 1540's second ROM is 325303-01, whose serial bus timing is the
///   VIC-20's; the 1541's is 901229, in revisions 01 to 06, slowed for the 64's VIC-II, which takes the bus away from
///   the processor. A 1541 works with either computer, a 1540 only with the VIC-20.
///  </para>
/// </remarks>
public sealed class Cbm1541Roms
{
    private readonly byte[] _low;
    private readonly byte[] _high;

    /// <summary>
    ///  Constructs the ROMs from their images.
    /// </summary>
    /// <param name="low">325302-01, at <c>$C000-$DFFF</c>.</param>
    /// <param name="high">The second ROM, at <c>$E000-$FFFF</c>.</param>
    /// <param name="model">The drive, <c>1541</c> or <c>1540</c>.</param>
    /// <exception cref="ArgumentException">An image is not 8K, or the model is neither.</exception>
    public Cbm1541Roms(ReadOnlySpan<byte> low, ReadOnlySpan<byte> high, string model = "1541")
    {
        if (low.Length != 0x2000)
        {
            throw new ArgumentException("The drive's ROM at $C000 is 8,192 bytes.", nameof(low));
        }

        if (high.Length != 0x2000)
        {
            throw new ArgumentException("The drive's ROM at $E000 is 8,192 bytes.", nameof(high));
        }

        if (model is not ("1541" or "1540"))
        {
            throw new ArgumentException("The ROMs are a 1541's or a 1540's.", nameof(model));
        }

        _low = low.ToArray();
        _high = high.ToArray();
        Model = model;
    }

    /// <summary>
    ///  Gets the drive the ROMs are for: <c>1541</c> or <c>1540</c>.
    /// </summary>
    public string Model { get; }

    /// <summary>
    ///  Gets the ROM at <c>$C000</c>.
    /// </summary>
    public ReadOnlySpan<byte> Low => _low;

    /// <summary>
    ///  Gets the ROM at <c>$E000</c>.
    /// </summary>
    public ReadOnlySpan<byte> High => _high;

    /// <summary>
    ///  Loads a 1541's ROMs from a directory of MAME's <c>c1541</c> chip files.
    /// </summary>
    /// <param name="directory">The directory.</param>
    /// <param name="revision">901229's revision: 1, 2, 3, 5 or 6 (MAME's default, and the last).</param>
    /// <returns>The ROMs.</returns>
    /// <exception cref="ArgumentOutOfRangeException">The revision is not one MAME has a dump of.</exception>
    public static Cbm1541Roms Load1541FromDirectory(string directory, int revision = 6)
    {
        string high = revision switch
        {
            1 => "901229-01.uab5",
            2 => "901229-02.uab5",
            3 => "901229-03.uab5",
            5 => "901229-05 ae.uab5",
            6 => "901229-06 aa.uab5",
            _ => throw new ArgumentOutOfRangeException(nameof(revision), "901229 is dumped in revisions 1, 2, 3, 5 and 6.")
        };

        return new(File.ReadAllBytes(Path.Join(directory, "325302-01.uab4")), File.ReadAllBytes(Path.Join(directory, high)));
    }

    /// <summary>
    ///  Loads a 1540's ROMs from a directory of MAME's <c>c1540</c> chip files.
    /// </summary>
    /// <param name="directory">The directory.</param>
    /// <returns>The ROMs.</returns>
    public static Cbm1541Roms Load1540FromDirectory(string directory) => new(
        File.ReadAllBytes(Path.Join(directory, "325302-01.uab4")),
        File.ReadAllBytes(Path.Join(directory, "325303-01.uab5")),
        "1540");
}
