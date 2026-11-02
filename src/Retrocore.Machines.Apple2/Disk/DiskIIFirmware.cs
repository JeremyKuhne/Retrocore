// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Machines.Apple2;

/// <summary>
///  Caller-supplied P5 boot firmware and P6 sequencer truth table. No Apple firmware is bundled.
/// </summary>
public sealed class DiskIIFirmware
{
    private readonly byte[] _boot;
    private readonly byte[] _sequencer = new byte[256];

    /// <summary>
    ///  Copies boot firmware and normalizes the specified P6 wiring to state/Q7/Q6/latch/pulse indexing.
    /// </summary>
    /// <param name="boot">The 256-byte P5/P5A card ROM.</param>
    /// <param name="sequencer">The 256-byte P6 sequencer PROM.</param>
    /// <param name="layout">The PROM's layout; a raw dump of the chip either way.</param>
    public DiskIIFirmware(ReadOnlySpan<byte> boot, ReadOnlySpan<byte> sequencer, P6PromLayout layout = P6PromLayout.Raw)
    {
        if (boot.Length != 256 || sequencer.Length != 256)
        {
            throw new ArgumentException("Disk II requires a 256-byte boot ROM and a 256-byte sequencer PROM.");
        }

        if (!Enum.IsDefined(layout)) { throw new ArgumentOutOfRangeException(nameof(layout)); }
        _boot = boot.ToArray();
        // The chip's address pins A7-A0 carry state bits 3 and 2, state bit 0, the read pulse, Q7, Q6, QA and
        // state bit 1; its data pins D7-D4 the next state's bits 3-0, which feed back through the state latch.
        // The 341-0028 dump reads 6-and-2 nibbles only so wired; its table is then the one Beneath Apple ProDOS prints.
        // A dump read from the boot ROM's socket, as the known 341-0010 one is, is first put back in the chip's order.
        for (int source = 0; source < 256; source++)
        {
            int destination = (source & 192) | ((source & 32) >> 1) | ((source & 1) << 5) | (source & 14) | ((source >> 4) & 1);
            _sequencer[destination] = layout == P6PromLayout.BootSocket
                ? FromBootSocket(sequencer, source)
                : sequencer[source];
        }
    }

    /// <summary>
    ///  Reads the byte at a sequencer address from a dump made in the boot ROM's socket, which exchanges address
    ///  lines A5 and A7 and reverses data lines D7-D4.
    /// </summary>
    /// <param name="dump">The dump.</param>
    /// <param name="address">The address on the sequencer's own pins.</param>
    /// <returns>The byte on the sequencer's own pins.</returns>
    internal static byte FromBootSocket(ReadOnlySpan<byte> dump, int address)
    {
        int value = dump[(address & 0x5F) | ((address >> 2) & 0x20) | ((address << 2) & 0x80)];
        int next = value >> 4;
        return (byte)((value & 0x0F) | ((next & 1) << 7) | ((next & 2) << 5) | ((next & 4) << 3) | ((next & 8) << 1));
    }

    /// <summary>
    ///  Gets immutable boot firmware for C600-C6FF.
    /// </summary>
    public ReadOnlySpan<byte> Boot => _boot;

    /// <summary>
    ///  Gets normalized sequencer truth-table data.
    /// </summary>
    internal ReadOnlySpan<byte> Sequencer => _sequencer;
}
