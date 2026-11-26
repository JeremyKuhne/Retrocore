// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Media;

/// <summary>
///  A <c>SOS.INTERP</c> file: the program SOS starts once it has loaded, such as Business BASIC or Apple III Pascal,
///  at a fixed address in the system bank.
/// </summary>
/// <remarks>
///  <para>
///   The file starts with <c>SOS NTRP</c>, then a header: a 2-byte count and that many bytes, which SOS's loader
///   skips. Then come the address the code runs at and its length, 2 bytes each, and the code. The loader moves the
///   code to that address in the system bank and starts it at its first byte; the code must end at or below the
///   kernel, at <c>$B800</c>. Nothing is relocated. Bytes after the code are ignored.
///  </para>
/// </remarks>
/// <param name="LoadAddress">The address the code runs at, and its entry point.</param>
/// <param name="Code">The code.</param>
/// <param name="Header">The header the loader skips; empty for most interpreters.</param>
public sealed record SosInterpreterFile(int LoadAddress, byte[] Code, byte[] Header)
{
    /// <summary>
    ///  The lowest address an interpreter can run at: the start of the system bank's <c>$2000-$9FFF</c>.
    /// </summary>
    public const int LowestAddress = 0x2000;

    /// <summary>
    ///  Where SOS 1.3's kernel starts, at or below which an interpreter must end.
    /// </summary>
    public const int KernelAddress = 0xB800;

    private const int LabelSize = 8;

    private static ReadOnlySpan<byte> Label => "SOS NTRP"u8;

    /// <summary>
    ///  Reads an interpreter file.
    /// </summary>
    /// <param name="data">The file's contents.</param>
    /// <returns>Its load address, code and header.</returns>
    /// <exception cref="InvalidDataException">
    ///  The data does not start with <c>SOS NTRP</c>, or ends inside its header or code.
    /// </exception>
    public static SosInterpreterFile Read(ReadOnlySpan<byte> data)
    {
        if (data.Length < LabelSize + 2 || !data[..LabelSize].SequenceEqual(Label))
        {
            throw new InvalidDataException("A SOS.INTERP file starts with \"SOS NTRP\".");
        }

        int headerSize = Word(data, LabelSize);
        int offset = LabelSize + 2 + headerSize;
        if (offset + 4 > data.Length)
        {
            throw new InvalidDataException("The interpreter file ends inside its header.");
        }

        int address = Word(data, offset);
        int length = Word(data, offset + 2);
        if (offset + 4 + length > data.Length)
        {
            throw new InvalidDataException("The interpreter file ends inside its code.");
        }

        return new SosInterpreterFile(
            address,
            data.Slice(offset + 4, length).ToArray(),
            data.Slice(LabelSize + 2, headerSize).ToArray());
    }

    /// <summary>
    ///  Writes an interpreter file that <see cref="Read"/> reads back.
    /// </summary>
    /// <param name="loadAddress">
    ///  The address the code runs at and starts from: <see cref="LowestAddress"/> or above, with the code ending at
    ///  or below <see cref="KernelAddress"/>.
    /// </param>
    /// <param name="code">The code, assembled to run at the load address; at least one byte.</param>
    /// <param name="header">
    ///  The header the loader skips, or empty. Keep it small: SOS reads only the file's first 60K or so, into the
    ///  memory below its own.
    /// </param>
    /// <returns>The file's contents.</returns>
    /// <exception cref="ArgumentException">The code is empty, or the header is $10000 bytes or more.</exception>
    /// <exception cref="ArgumentOutOfRangeException">
    ///  The load address is below <see cref="LowestAddress"/>, or the code runs past <see cref="KernelAddress"/>.
    /// </exception>
    public static byte[] Write(int loadAddress, ReadOnlySpan<byte> code, ReadOnlySpan<byte> header = default)
    {
        if (code.IsEmpty) { throw new ArgumentException("An interpreter has code.", nameof(code)); }
        if (header.Length > 0xFFFF)
        {
            throw new ArgumentException("The header is $10000 bytes or more.", nameof(header));
        }

        if (loadAddress < LowestAddress || loadAddress + code.Length > KernelAddress)
        {
            throw new ArgumentOutOfRangeException(
                nameof(loadAddress),
                $"An interpreter runs from ${LowestAddress:X4} to the kernel at ${KernelAddress:X4}; {code.Length} bytes at ${loadAddress:X4} do not fit.");
        }

        byte[] file = new byte[LabelSize + 2 + header.Length + 4 + code.Length];
        Label.CopyTo(file);
        int offset = LabelSize;
        offset = PutWord(file, offset, header.Length);
        header.CopyTo(file.AsSpan(offset));
        offset += header.Length;
        offset = PutWord(file, offset, loadAddress);
        offset = PutWord(file, offset, code.Length);
        code.CopyTo(file.AsSpan(offset));
        return file;
    }

    private static int Word(ReadOnlySpan<byte> data, int offset) => data[offset] | (data[offset + 1] << 8);

    private static int PutWord(byte[] data, int offset, int value)
    {
        data[offset] = (byte)value;
        data[offset + 1] = (byte)(value >> 8);
        return offset + 2;
    }
}
