// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Debug;

/// <summary>
///  Storage a memory reference can name directly, whatever the memory map, such as the IIe's auxiliary RAM.
/// </summary>
/// <remarks>
///  <para>
///   A bank's addresses are the CPU addresses its bytes answer at when it is mapped, so <c>aux:$0400</c> is the
///   byte auxiliary RAM holds for text page one.
///  </para>
/// </remarks>
/// <param name="Name">The prefix that names it in memory references and expressions, such as <c>aux</c>.</param>
/// <param name="Label">What it is, such as "Auxiliary RAM".</param>
/// <param name="Areas">
///  The memory area that holds each of <paramref name="Ranges"/>, in order, as <see cref="IDebugMemory.ReadArea"/>
///  reports them.
/// </param>
/// <param name="Ranges">The CPU address ranges it holds bytes for.</param>
/// <param name="Peek">Reads a byte without side effects, or returns null where the bank has none.</param>
/// <param name="Poke">Writes a byte, returning false where the bank has none; null when it is read-only.</param>
/// <param name="InstructionSet">
///  The instruction set of the CPU the bank's addresses are for, when it is not the machine's own, such as the
///  SoftCard's Z80; null for the machine's CPU.
/// </param>
/// <param name="CanPoke">
///  Whether a write reaches an address now, for a bank whose writes can land on ROM or I/O, such as the SoftCard's
///  Z80 through its address translation; null when every byte it has can be written.
/// </param>
/// <param name="ReadsHere">
///  Whether the CPU reads the bank's byte at an address now, for a bank its areas do not tell apart from the CPU's
///  memory, such as an Apple III X-byte's view; null to go by the areas.
/// </param>
/// <param name="WritesHere">
///  Whether the CPU's write at an address changes the bank's byte now, for a bank whose writes go other than its reads,
///  such as the Apple III's RAM under its ROM, written unless write protection is on; null to go by
///  <paramref name="ReadsHere"/>, or by the areas.
/// </param>
/// <param name="PartAt">
///  The part of the bank an address is in, named by the switch that puts it in the CPU's view, such as the IIe's
///  alternate zero page and stack (ALTZP), for the memory map; null for a bank that is all one part.
/// </param>
internal sealed record DebugMemoryBank(
    string Name,
    string Label,
    IReadOnlyList<Enum> Areas,
    IReadOnlyList<(ushort Start, int Length)> Ranges,
    Func<ushort, byte?> Peek,
    Func<ushort, byte, bool>? Poke,
    Retrocore.Isa.InstructionSet? InstructionSet = null,
    Func<ushort, bool>? CanPoke = null,
    Func<ushort, bool>? ReadsHere = null,
    Func<ushort, string?>? PartAt = null,
    Func<ushort, bool>? WritesHere = null)
{
    /// <summary>
    ///  Gets whether the CPU reads the bank's byte at an address now: where it reads one of the bank's areas, or, for
    ///  a bank that is a view of storage the areas do not tell apart, such as the Apple III's X-byte addressing,
    ///  where it reads the same byte.
    /// </summary>
    /// <param name="cpu">The CPU's memory.</param>
    /// <param name="address">The CPU address.</param>
    /// <returns>True when the CPU reads the bank's byte there.</returns>
    internal bool ReadBy(IDebugMemory cpu, ushort address) =>
        ReadsHere?.Invoke(address) ?? Areas.Contains(cpu.ReadArea(address));

    /// <summary>
    ///  Gets whether the CPU writes the bank's byte at an address now, which it can where it does not read it, such
    ///  as the IIe's auxiliary RAM with RAMWRT on and RAMRD off. A read-only bank is never written, and a bank whose
    ///  byte <see cref="ReadsHere"/> tells apart, such as an Apple III X-byte's view, is written where it is read, as
    ///  the CPU writes the RAM it reads.
    /// </summary>
    /// <param name="cpu">The CPU's memory.</param>
    /// <param name="address">The CPU address.</param>
    /// <returns>True when the CPU's writes there change the bank's byte.</returns>
    internal bool WrittenBy(IDebugMemory cpu, ushort address) => Poke is not null
        && (WritesHere?.Invoke(address) ?? ReadsHere?.Invoke(address) ?? Areas.Contains(cpu.WriteArea(address)));

    /// <summary>
    ///  Gets whether a write reaches an address of the bank now.
    /// </summary>
    /// <param name="address">The CPU address.</param>
    /// <returns>True when the bank has a byte there that a write changes.</returns>
    internal bool Writable(ushort address) => Poke is not null
        && Peek(address) is not null
        && (CanPoke?.Invoke(address) ?? true);

    /// <summary>
    ///  Gets the memory area that holds an address.
    /// </summary>
    /// <param name="address">The CPU address.</param>
    /// <returns>The area, or null when the bank has no byte there.</returns>
    internal Enum? AreaOf(ushort address)
    {
        for (int index = 0; index < Ranges.Count; index++)
        {
            if (address >= Ranges[index].Start && address < Ranges[index].Start + Ranges[index].Length)
            {
                return Areas[Math.Min(index, Areas.Count - 1)];
            }
        }

        return null;
    }
}
