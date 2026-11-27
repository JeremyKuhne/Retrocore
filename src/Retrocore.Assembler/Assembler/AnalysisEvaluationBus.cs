// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Cpu;

namespace Retrocore.Assembler;

/// <summary>
///  The bus <see cref="AnalysisEvaluator"/> runs an instruction on: it serves the instruction's own bytes and memory
///  the analysis knows, and notes any other read, and any port.
/// </summary>
internal sealed class AnalysisEvaluationBus : IProcessorBus, IIoBus
{
    private readonly byte[] _bytes = new byte[8];
    private ushort _start;
    private int _length;
    private byte[] _reads = new byte[8];
    private int _readLength;
    private Func<ushort, int>? _known;

    /// <summary>
    ///  Gets whether the instruction did something the analysis cannot follow: more reads than it was given values
    ///  for, or a port.
    /// </summary>
    internal bool Failed { get; private set; }

    /// <summary>
    ///  Gets how many bytes the instruction read other than its own and the code after them.
    /// </summary>
    internal int ReadCount { get; private set; }

    /// <summary>
    ///  Gets how many bytes the instruction wrote, its pushes included.
    /// </summary>
    internal int WriteCount { get; private set; }

    /// <summary>
    ///  Gets the bus ready for an instruction.
    /// </summary>
    /// <param name="pc">Where the instruction is.</param>
    /// <param name="bytes">Its bytes.</param>
    /// <param name="reads">The values its reads of other memory get, in the order it reads.</param>
    /// <param name="known">The value of a byte the caller knows, or -1; such reads take no value from reads.</param>
    internal void Start(ushort pc, ReadOnlySpan<byte> bytes, ReadOnlySpan<byte> reads, Func<ushort, int>? known)
    {
        _known = known;
        _start = pc;
        _length = Math.Min(bytes.Length, _bytes.Length);
        bytes[.._length].CopyTo(_bytes);
        if (reads.Length > _reads.Length) { _reads = new byte[reads.Length]; }
        reads.CopyTo(_reads);
        _readLength = reads.Length;
        ReadCount = 0;
        WriteCount = 0;
        Failed = false;
    }

    /// <inheritdoc/>
    public byte Read(ushort address)
    {
        int offset = (ushort)(address - _start);
        if (offset < _length) { return _bytes[offset]; }
        if (_known?.Invoke(address) is int value and >= 0) { return (byte)value; }
        int read = ReadCount++;
        if (read < _readLength) { return _reads[read]; }
        Failed = true;
        return 0;
    }

    /// <inheritdoc/>
    public void Write(ushort address, byte value) => WriteCount++;

    /// <inheritdoc/>
    public byte In(ushort port)
    {
        Failed = true;
        return 0;
    }

    /// <inheritdoc/>
    public void Out(ushort port, byte value) => Failed = true;
}
