// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Debug.Project;

/// <summary>
///  A machine as the extension's catalog names it, the names Start Machine and favorites use: the launch options that
///  make it that machine, its family's platform folder, and its CPU.
/// </summary>
/// <remarks>
///  <para>
///   The ids and launch options are the extension's (<c>extension/src/machines.ts</c>), which
///   <c>launchConfiguration</c> there spreads into the launch configuration that <c>startFlow.ts</c> starts; a test keeps the two tables the same.
///  </para>
/// </remarks>
/// <param name="Id">The catalog's id, such as <c>apple2-iiplus</c>; it also names the model's platform folder.</param>
/// <param name="Machine">The launch's <c>machine</c>, such as <c>apple2</c>.</param>
/// <param name="Model">The launch's <c>model</c>, or null for a machine that has none.</param>
/// <param name="Rom">The launch's <c>rom</c>, or null for the machine's default ROM.</param>
/// <param name="Family">
///  The family's platform folder, <c>src/platform/&lt;family&gt;/</c>, such as <c>apple2</c>.
/// </param>
/// <param name="Cpu">The machine's CPU.</param>
internal sealed record CatalogMachine(string Id, string Machine, string? Model, string? Rom, string Family, ProjectCpu Cpu)
{
    /// <summary>
    ///  Gets every machine in the catalog, in its order.
    /// </summary>
    internal static IReadOnlyList<CatalogMachine> All { get; } =
    [
        Of("apple2-iie-enhanced", "apple2", "apple2", ProjectCpu.Rockwell65C02, model: "iie-enhanced"),
        Of("apple2-iie", "apple2", "apple2", ProjectCpu.Mos6502, model: "iie"),
        Of("apple2-iiplus", "apple2", "apple2", ProjectCpu.Mos6502, model: "iiplus"),
        Of("apple2-ii", "apple2", "apple2", ProjectCpu.Mos6502, model: "ii"),
        Of("apple3", "apple3", "apple3", ProjectCpu.Mos6502),
        Of("trs80-model1-level2", "trs80-model1", "trs80", ProjectCpu.Z80),
        Of("trs80-model1-level1", "trs80-model1", "trs80", ProjectCpu.Z80, rom: "level1"),
        Of("trs80-model3", "trs80-model3", "trs80", ProjectCpu.Z80, model: "3"),
        Of("trs80-model3-level1", "trs80-model3", "trs80", ProjectCpu.Z80, model: "3", rom: "level1"),
        Of("trs80-model4", "trs80-model3", "trs80", ProjectCpu.Z80, model: "4"),
        Of("trs80-model4p", "trs80-model3", "trs80", ProjectCpu.Z80, model: "4p"),
        Of("trs80-model2", "trs80-model2", "trs80", ProjectCpu.Z80, model: "2"),
        Of("trs80-model12", "trs80-model2", "trs80", ProjectCpu.Z80, model: "12"),
        Of("trs80-model16", "trs80-model2", "trs80", ProjectCpu.Z80, model: "16"),
        Of("apple1", "apple1", "apple1", ProjectCpu.Mos6502),
        Of("coco1", "coco", "coco", ProjectCpu.M6809, model: "coco1"),
        Of("coco2", "coco", "coco", ProjectCpu.M6809, model: "coco2"),
        Of("coco3", "coco", "coco", ProjectCpu.M6809, model: "coco3"),
        Of("pet2001-basic2", "pet", "pet", ProjectCpu.Mos6502, model: "pet2001-basic2"),
        Of("pet2001", "pet", "pet", ProjectCpu.Mos6502, model: "pet2001"),
        Of("pet4032", "pet", "pet", ProjectCpu.Mos6502, model: "pet4032"),
        Of("pet4032-business", "pet", "pet", ProjectCpu.Mos6502, model: "pet4032-business"),
        Of("bbcb", "bbc", "bbc", ProjectCpu.Mos6502, model: "bbcb"),
        Of("bbca", "bbc", "bbc", ProjectCpu.Mos6502, model: "bbca"),
        Of("atari800", "atari800", "atari", ProjectCpu.Mos6502, model: "atari800"),
        Of("atari400", "atari800", "atari", ProjectCpu.Mos6502, model: "atari400"),
        Of("altair", "altair", "altair", ProjectCpu.I8080),
        Of("kaypro2", "kaypro2", "kaypro", ProjectCpu.Z80)
    ];

    /// <summary>
    ///  Finds a machine by its catalog id.
    /// </summary>
    /// <param name="id">The id, such as <c>pet4032</c>; ids are lowercase and compared exactly.</param>
    /// <returns>The machine, or null when the catalog has no such id.</returns>
    internal static CatalogMachine? Find(string id) => All.FirstOrDefault(machine => machine.Id == id);

    private static CatalogMachine Of(string id, string machine, string family, ProjectCpu cpu, string? model = null, string? rom = null) =>
        new(id, machine, model, rom, family, cpu);
}