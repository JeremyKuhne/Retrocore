// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Machines.Commodore;

/// <summary>
///  A Commodore dual drive's ROMs: the DOS processor's 12K, the controller's 1K in its 6530, and the GCR encoding
///  PROM. The 4040's are DOS 2.0; the 2040's, the same hardware, are DOS 1.2.
/// </summary>
public sealed class Cbm4040Roms
{
    private readonly byte[] _dos;
    private readonly byte[] _controller;
    private readonly byte[] _gcr;

    /// <summary>
    ///  Constructs the ROMs from their images.
    /// </summary>
    /// <param name="dos">The DOS, 12K at the DOS processor's <c>$5000-$7FFF</c>.</param>
    /// <param name="controller">The controller's 1K, at its <c>$1C00-$1FFF</c>.</param>
    /// <param name="gcr">The 2K GCR PROM, 901467.</param>
    /// <param name="model">The drive the ROMs are for, <c>4040</c> or <c>2040</c>.</param>
    /// <exception cref="ArgumentException">An image is the wrong size, or the model is neither.</exception>
    public Cbm4040Roms(ReadOnlySpan<byte> dos, ReadOnlySpan<byte> controller, ReadOnlySpan<byte> gcr, string model = "4040")
    {
        if (dos.Length != 0x3000)
        {
            throw new ArgumentException("The drive's DOS is 12,288 bytes.", nameof(dos));
        }

        if (controller.Length != 0x400)
        {
            throw new ArgumentException("The drive's controller ROM is 1,024 bytes.", nameof(controller));
        }

        if (gcr.Length != 0x800)
        {
            throw new ArgumentException("The GCR PROM is 2,048 bytes.", nameof(gcr));
        }

        if (model is not ("4040" or "2040"))
        {
            throw new ArgumentException("The ROMs are a 4040's or a 2040's.", nameof(model));
        }

        _dos = dos.ToArray();
        _controller = controller.ToArray();
        _gcr = gcr.ToArray();
        Model = model;
    }

    /// <summary>
    ///  Gets the drive the ROMs are for: <c>4040</c> or <c>2040</c>.
    /// </summary>
    public string Model { get; }

    /// <summary>
    ///  Gets the DOS.
    /// </summary>
    public ReadOnlySpan<byte> Dos => _dos;

    /// <summary>
    ///  Gets the controller's ROM.
    /// </summary>
    public ReadOnlySpan<byte> Controller => _controller;

    /// <summary>
    ///  Gets the GCR PROM.
    /// </summary>
    public ReadOnlySpan<byte> Gcr => _gcr;

    /// <summary>
    ///  Loads a 4040's ROMs from a directory holding MAME's chip files, as its <c>c4040</c> set unzipped does, or the
    ///  PET sets that carry the 4040's chips.
    /// </summary>
    /// <param name="directory">The directory.</param>
    /// <param name="revision1">DOS 2.0's first revision, 901468-11 to -13, rather than the second, -14 to -16.</param>
    /// <returns>The ROMs.</returns>
    public static Cbm4040Roms LoadFromDirectory(string directory, bool revision1 = false)
    {
        string[] dos = revision1
            ? ["901468-11.uj1", "901468-12.ul1", "901468-13.uh1"]
            : ["901468-14.uj1", "901468-15.ul1", "901468-16.uh1"];

        byte[] image = [.. dos.SelectMany(file => File.ReadAllBytes(Path.Join(directory, file)))];
        return new(
            image,
            File.ReadAllBytes(Path.Join(directory, "901466-04.uk3")),
            File.ReadAllBytes(Path.Join(directory, "901467.uk6")));
    }

    /// <summary>
    ///  Loads a 2040's ROMs from a directory holding MAME's <c>c2040</c> chip files: DOS 1.2, 901468-06 and -07 at
    ///  <c>$6000-$7FFF</c>, and the 6530's 901466-01.
    /// </summary>
    /// <remarks>
    ///  <para>
    ///   DOS 1.2 is 8K. Its board leaves the first ROM socket, UJ1 at <c>$5000</c>, empty, which reads as zeros, as
    ///   MAME's does.
    ///  </para>
    /// </remarks>
    /// <param name="directory">The directory.</param>
    /// <returns>The ROMs.</returns>
    public static Cbm4040Roms Load2040FromDirectory(string directory)
    {
        byte[] image = new byte[0x3000];
        File.ReadAllBytes(Path.Join(directory, "901468-06.ul1")).CopyTo(image, 0x1000);
        File.ReadAllBytes(Path.Join(directory, "901468-07.uh1")).CopyTo(image, 0x2000);
        return new(
            image,
            File.ReadAllBytes(Path.Join(directory, "901466-01.uk3")),
            File.ReadAllBytes(Path.Join(directory, "901467.uk6")),
            "2040");
    }
}
