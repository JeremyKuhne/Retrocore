// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Debug.Project;

/// <summary>
///  A CPU a project or target can name, with the instruction set <c>.cpu</c> selects for it and the CPUs whose code
///  it also runs.
/// </summary>
/// <remarks>
///  <para>
///   Compatibility follows supersets: <c>6502</c> code runs on every 65C02, the 65SC02's instructions (the
///   <c>65c02</c> baseline) on the Rockwell and WDC parts, the Rockwell's bit instructions on the WDC part, and
///   <c>8080</c> code on the 8085 and the Z80.
///  </para>
/// </remarks>
internal sealed class ProjectCpu
{
    private readonly string[] _runs;

    private ProjectCpu(string name, string assemblerName, params string[] runs)
    {
        Name = name;
        AssemblerName = assemblerName;
        _runs = [name, .. runs];
    }

    /// <summary>
    ///  Gets the NMOS 6502.
    /// </summary>
    internal static ProjectCpu Mos6502 { get; } = new("6502", "Mos6502");

    /// <summary>
    ///  Gets the CMOS instructions every 65C02 has, the 65SC02's.
    /// </summary>
    internal static ProjectCpu Cmos65C02 { get; } = new("65c02", "65SC02", "6502");

    /// <summary>
    ///  Gets the Rockwell R65C02, with the bit instructions, as the enhanced IIe runs it.
    /// </summary>
    internal static ProjectCpu Rockwell65C02 { get; } = new("r65c02", "Rockwell65C02", "6502", "65c02");

    /// <summary>
    ///  Gets the WDC W65C02S, with <c>WAI</c> and <c>STP</c> as well.
    /// </summary>
    internal static ProjectCpu Wdc65C02 { get; } = new("w65c02", "Wdc65C02", "6502", "65c02", "r65c02");

    /// <summary>
    ///  Gets the Intel 8080.
    /// </summary>
    internal static ProjectCpu I8080 { get; } = new("8080", "I8080");

    /// <summary>
    ///  Gets the Intel 8085.
    /// </summary>
    internal static ProjectCpu I8085 { get; } = new("8085", "I8085", "8080");

    /// <summary>
    ///  Gets the Zilog Z80.
    /// </summary>
    internal static ProjectCpu Z80 { get; } = new("z80", "Z80", "8080");

    /// <summary>
    ///  Gets the Motorola 6809.
    /// </summary>
    internal static ProjectCpu M6809 { get; } = new("6809", "M6809");

    /// <summary>
    ///  Gets every CPU a project can name.
    /// </summary>
    internal static IReadOnlyList<ProjectCpu> All { get; } =
        [Mos6502, Cmos65C02, Rockwell65C02, Wdc65C02, I8080, I8085, Z80, M6809];

    /// <summary>
    ///  Gets the name a project gives it, such as <c>6502</c> or <c>z80</c>.
    /// </summary>
    internal string Name { get; }

    /// <summary>
    ///  Gets the instruction set's name as <c>.cpu</c> selects it, such as <c>Mos6502</c>.
    /// </summary>
    internal string AssemblerName { get; }

    /// <summary>
    ///  Finds a CPU by the name a project gives it or by its instruction set's name, in any case.
    /// </summary>
    /// <param name="name">The name, such as <c>65c02</c> or <c>Rockwell65C02</c>.</param>
    /// <returns>The CPU, or null for a name that is neither.</returns>
    internal static ProjectCpu? Find(string name) => All.FirstOrDefault(cpu =>
        string.Equals(cpu.Name, name, StringComparison.OrdinalIgnoreCase)
            || string.Equals(cpu.AssemblerName, name, StringComparison.OrdinalIgnoreCase));

    /// <summary>
    ///  Finds a CPU by the name a project gives it, exactly as the schema lists it.
    /// </summary>
    /// <param name="name">The name, such as <c>65c02</c>.</param>
    /// <returns>The CPU, or null for a name a project cannot give.</returns>
    internal static ProjectCpu? Named(string name) => All.FirstOrDefault(cpu => cpu.Name == name);

    /// <summary>
    ///  Tests whether this CPU runs another's code: whether it has every instruction the other has.
    /// </summary>
    /// <param name="other">The other CPU.</param>
    /// <returns>Whether it does; a CPU runs its own code.</returns>
    internal bool Runs(ProjectCpu other) => _runs.Contains(other.Name);

    /// <inheritdoc/>
    public override string ToString() => Name;
}