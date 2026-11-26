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
    private Func<ushort, int>? _memory;

    /// <summary>
    ///  Gets whether the instruction read something the analysis does not know.
    /// </summary>
    internal bool Failed { get; private set; }

    /// <summary>
    ///  Gets the bus ready for an instruction.
    /// </summary>
    /// <param name="pc">Where the instruction is.</param>
    /// <param name="bytes">Its bytes.</param>
    /// <param name="memory">The value of a byte of memory, or -1 when it is not known.</param>
    internal void Start(ushort pc, ReadOnlySpan<byte> bytes, Func<ushort, int> memory)
    {
        _start = pc;
        _length = Math.Min(bytes.Length, _bytes.Length);
        bytes[.._length].CopyTo(_bytes);
        _memory = memory;
        Failed = false;
    }

    /// <inheritdoc/>
    public byte Read(ushort address)
    {
        int offset = (ushort)(address - _start);
        if (offset < _length) { return _bytes[offset]; }
        int value = _memory?.Invoke(address) ?? -1;
        if (value < 0)
        {
            Failed = true;
            return 0;
        }

        return (byte)value;
    }

    /// <inheritdoc/>
    public void Write(ushort address, byte value)
    {
    }

    /// <inheritdoc/>
    public byte In(ushort port)
    {
        Failed = true;
        return 0;
    }

    /// <inheritdoc/>
    public void Out(ushort port, byte value) => Failed = true;
}
