// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Debug.Project;

/// <summary>
///  What every build of a target is given besides its sources: the SDK's <c>RC_</c> defines, and the folders its
///  <c>&lt;cpu.inc&gt;</c>, <c>&lt;machine.inc&gt;</c> and <c>&lt;environment.inc&gt;</c> come from.
/// </summary>
/// <remarks>
///  <para>
///   The build, the <c>project</c> launch and the language server all take a target's symbols and SDK paths from
///   here, so a source chooses the same code in each.
///  </para>
///  <para>
///   The defines are <c>RC_SDK</c>, the SDK's major version; <c>RC_CPU_&lt;cpu&gt;</c>, 1 for the target's CPU and
///   every CPU whose code it runs (<c>RC_CPU_6502</c> and <c>RC_CPU_65C02</c> for a <c>65c02</c> target);
///   <c>RC_MACHINE_&lt;family&gt;</c>, 1 for the machine's family (<c>RC_MACHINE_APPLE2</c>);
///   <c>RC_MODEL_&lt;machine&gt;</c>, 1 for the exact machine by its catalog id (<c>RC_MODEL_APPLE2_IIE_ENHANCED</c>,
///   <c>RC_MODEL_PET4032</c>); <c>RC_ENV_&lt;environment&gt;</c>, 1 for the environment (<c>RC_ENV_BARE</c>);
///   <c>RC_RAM_KB</c>, the machine's RAM, its <c>ramKilobytes</c> option or the launch's default;
///   <c>RC_SCREEN_COLUMNS</c> and <c>RC_SCREEN_ROWS</c>, the text screen the machine's ROM starts in; and
///   <c>RC_TARGET</c>, the target's name, as a textual definition of a quoted string.
///  </para>
///  <para>
///   In each name, a catalog id's, family's, CPU's or environment's letters are capitals, and its <c>-</c> and
///   <c>.</c> are <c>_</c>.
///  </para>
/// </remarks>
internal static class TargetDefines
{
    /// <summary>
    ///  The prefix of the SDK's names, which a project may not define.
    /// </summary>
    internal const string Prefix = "RC_";

    /// <summary>
    ///  The textual definition of the target's name.
    /// </summary>
    internal const string TargetName = "RC_TARGET";

    // Each machine's RAM, in kilobytes, when its target gives no ramKilobytes: the launch's own default, counted as the
    // option counts it, so the Apple II's is the RAM on its board, 48K, without a language card or auxiliary memory.
    private static readonly Dictionary<string, int> s_ram = new()
    {
        ["apple2-iie-enhanced"] = 48,
        ["apple2-iie"] = 48,
        ["apple2-iiplus"] = 48,
        ["apple2-ii"] = 48,
        ["apple3"] = 256,
        ["trs80-model1-level2"] = 48,
        ["trs80-model1-level1"] = 4,
        ["trs80-model3"] = 48,
        ["trs80-model3-level1"] = 48,
        ["trs80-model4"] = 128,
        ["trs80-model4p"] = 128,
        ["trs80-model2"] = 64,
        ["trs80-model12"] = 64,
        ["trs80-model16"] = 64,
        ["trs80-model100"] = 32,
        ["tandy102"] = 32,
        ["apple1"] = 4,
        ["coco1"] = 16,
        ["coco2"] = 64,
        ["coco3"] = 128,
        ["pet2001-basic2"] = 8,
        ["pet2001"] = 8,
        ["pet4032"] = 32,
        ["pet4032-business"] = 32,
        ["bbcb"] = 32,
        ["bbca"] = 16,
        ["atari800"] = 48,
        ["atari400"] = 16,
        ["altair"] = 64,
        ["kaypro2"] = 64
    };

    // Each family's text screen as its ROM starts it, columns by rows: the Model 4 and 4P start in the Model III's
    // 64 by 16, the Model II, 12 and 16 in 80 by 24, the Altair's and Kaypro's terminals are 80 by 24, and the
    // Model 100's LCD is 40 by 8.
    private static readonly Dictionary<string, (int Columns, int Rows)> s_screens = new()
    {
        ["apple1"] = (40, 24),
        ["apple2"] = (40, 24),
        ["apple3"] = (40, 24),
        ["trs80"] = (64, 16),
        ["coco"] = (32, 16),
        ["pet"] = (40, 25),
        ["bbc"] = (40, 25),
        ["atari"] = (40, 24),
        ["altair"] = (80, 24),
        ["kaypro"] = (80, 24),
        ["trs80-model100"] = (40, 8)
    };

    private static readonly HashSet<string> s_eightyColumns = ["trs80-model2", "trs80-model12", "trs80-model16"];

    /// <summary>
    ///  Gets the SDK's defines for a target.
    /// </summary>
    /// <param name="target">The target.</param>
    /// <returns>Each define's value.</returns>
    internal static Dictionary<string, long> Symbols(ProjectTarget target)
    {
        Dictionary<string, long> symbols = new(StringComparer.Ordinal)
        {
            ["RC_SDK"] = int.TryParse(target.Project.Sdk, out int major) ? major : 0
        };

        foreach (ProjectCpu cpu in ProjectCpu.All.Where(target.Cpu.Runs))
        {
            symbols[$"RC_CPU_{Part(cpu.Name)}"] = 1;
        }

        symbols[$"RC_MACHINE_{Part(target.Machine.Family)}"] = 1;
        symbols[$"RC_MODEL_{Part(target.Machine.Id)}"] = 1;
        symbols[$"RC_ENV_{Part(target.Environment)}"] = 1;
        symbols["RC_RAM_KB"] = RamKilobytes(target);
        (int columns, int rows) = Screen(target.Machine);
        symbols["RC_SCREEN_COLUMNS"] = columns;
        symbols["RC_SCREEN_ROWS"] = rows;
        return symbols;
    }

    /// <summary>
    ///  Gets the SDK's textual definitions for a target: <c>RC_TARGET</c>, its name as a quoted string.
    /// </summary>
    /// <param name="target">The target.</param>
    /// <returns>Each definition's text.</returns>
    internal static Dictionary<string, string> Texts(ProjectTarget target) =>
        new(StringComparer.Ordinal) { [TargetName] = $"\"{target.Name}\"" };

    /// <summary>
    ///  Gets the folders angle-bracket includes search for a target, in order: the machine's own header folder, its
    ///  family's, the environment's, the CPU's and its family's, then the SDK version's root and the SDK's root.
    /// </summary>
    /// <param name="target">The target.</param>
    /// <param name="sdk">The SDK's root, the host's <c>Sdk/</c> folder.</param>
    /// <returns>The folders that exist, and the two roots.</returns>
    /// <remarks>
    ///  <para>
    ///   So <c>.include &lt;machine.inc&gt;</c> finds the machine's header, and a model's header reaches its
    ///   family's as <c>&lt;machines/&lt;family&gt;/machine.inc&gt;</c> through the version's root.
    ///  </para>
    /// </remarks>
    internal static List<string> SdkPaths(ProjectTarget target, string sdk)
    {
        string version = Path.Join(sdk, target.Project.Sdk);
        List<string> folders =
        [
            Path.Join(version, "machines", target.Machine.Id),
            Path.Join(version, "machines", target.Machine.Family),
            Path.Join(version, "environments", target.Environment),
            Path.Join(version, "cpus", target.Cpu.Name),
            Path.Join(version, "cpus", CpuFamily(target.Cpu).Name)
        ];

        return [.. folders.Distinct(StringComparer.Ordinal).Where(Directory.Exists), version, sdk];
    }

    /// <summary>
    ///  Gets a name as it appears in a define: capitals, with <c>-</c> and <c>.</c> as <c>_</c>.
    /// </summary>
    /// <param name="name">The name, such as <c>apple2-iie-enhanced</c>.</param>
    /// <returns>The define's part, such as <c>APPLE2_IIE_ENHANCED</c>.</returns>
    internal static string Part(string name) => name.ToUpperInvariant().Replace('-', '_').Replace('.', '_');

    /// <summary>
    ///  Gets the target's RAM in kilobytes, as <c>RC_RAM_KB</c> gives it.
    /// </summary>
    /// <param name="target">The target.</param>
    /// <returns>The RAM.</returns>
    // The target's RAM: its ramKilobytes, or the machine's default. The Model I's default follows its Expansion
    // Interface, which a Level II machine has unless its target says not and a Level I one only when it says so:
    // 48K with it, otherwise 16K under Level II and 4K under Level I, as the launch has it.
    internal static int RamKilobytes(ProjectTarget target)
    {
        // Read as the launch reads it. One that is not a whole number leaves the define the default; a size the
        // machine does not offer is the define's value as given, and the launch refuses it.
        try
        {
            if (target.Options.Int("ramKilobytes") is { } kilobytes) { return kilobytes; }
        }
        catch (ArgumentException)
        {
            // The launch refuses it.
        }

        if (target.Machine.Machine == "trs80-model1")
        {
            bool level1 = target.Machine.Rom == "level1";
            bool expansion = target.Options["expansionInterface"]?.GetValueKind() switch
            {
                System.Text.Json.JsonValueKind.True => true,
                System.Text.Json.JsonValueKind.False => false,
                _ => !level1
            };

            return expansion ? 48 : level1 ? 4 : 16;
        }

        return s_ram.GetValueOrDefault(target.Machine.Id);
    }

    private static (int Columns, int Rows) Screen(CatalogMachine machine) =>
        s_eightyColumns.Contains(machine.Id) ? (80, 24) : s_screens.GetValueOrDefault(machine.Family);

    // The CPU whose folder holds the family's shared header: the NMOS 6502 for every 65C02, the 8080 for the 8085.
    private static ProjectCpu CpuFamily(ProjectCpu cpu) =>
        cpu.Runs(ProjectCpu.Mos6502) ? ProjectCpu.Mos6502 : cpu.Runs(ProjectCpu.I8080) && cpu != ProjectCpu.Z80 ? ProjectCpu.I8080 : cpu;
}
