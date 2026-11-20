// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using System.Text.Json.Nodes;

namespace Retrocore.Desktop;

/// <summary>
///  The machines Retrocore can start, with their settings, as the extension's catalog (<c>machines.ts</c>) has them.
/// </summary>
internal static class MachineCatalog
{
    private static readonly MachineChoice s_sound = new("sound", "Sound",
    [
        new("Speaker", "speaker"),
        new("Speaker and Mockingboard", "mockingboard", "Puts the Mockingboard in slot 4"),
        new("Off", "off"),
    ], "speaker");

    private static readonly MachineChoice s_ram = new("ramKilobytes", "Memory",
        [new("48 KB", 48), new("32 KB", 32), new("16 KB", 16)], 48);

    private static readonly MachineChoice s_lowercase = new("lowercase", "Lowercase",
        [new("Without the lowercase modification", Value: false), new("With the lowercase modification", Value: true)], Default: false);

    private static readonly MachineChoice s_model4Ram = new("ramKilobytes", "Memory", [new("128 KB", 128), new("64 KB", 64)], 128);

    private static readonly MachineChoice s_model2Ram = new("ramKilobytes", "Memory",
        [new("64 KB", 64), new("128 KB", 128), new("256 KB", 256), new("512 KB", 512), new("32 KB", 32)], 64);

    private static readonly MachineChoice s_cocoSound = new("sound", "Sound",
        [new("On", "speaker", "The DAC, cassette and single-bit sound through the TV"), new("Off", "off")], "speaker");

    private static readonly MachineChoice s_petRam = new("ramKilobytes", "Memory",
        [new("8 KB", 8), new("16 KB", 16), new("32 KB", 32), new("4 KB", 4, "As the 2001-4 shipped")], 8);

    private static readonly MachineChoice s_pet4032Ram = new("ramKilobytes", "Memory",
        [new("32 KB", 32, "The 4032"), new("16 KB", 16, "The 4016"), new("8 KB", 8)], 32);

    private static readonly MachineChoice s_basic4Revision = new("basicRevision", "BASIC 4",
    [
        new("Revised", "revised", "901465-23 at $B000"),
        new("Original", "original", "901465-19, the first chip"),
    ], "revised");

    private static readonly MachineChoice s_petSnow = new("snow", "Snow",
        [new("On", Value: true, "Accesses to video RAM while the screen is drawn show, as on the 2001's board"), new("Off", Value: false)],
        Default: true);

    // The 2001 with BASIC 2 launches without snow, so its choice starts off.
    private static readonly MachineChoice s_petSnowOff = s_petSnow with { Default = false };

    private static readonly MachineChoice s_petSound = new("sound", "Sound",
        [new("On", "speaker", "The VIA's CB2, as a speaker on the user port plays it"), new("Off", "off")], "speaker");

    private static readonly MachineChoice s_cocoDisk = new("diskController", "Disk controller",
    [
        new("None", Value: false, "Tapes and ROM packs"),
        new("Disk controller", Value: true, "Disk Extended Color BASIC and four drives"),
    ], Default: false);

    private static readonly MachineChoice s_bbcSound = new("sound", "Sound",
        [new("On", "speaker", "The SN76489 through the internal speaker"), new("Off", "off")], "speaker");

    private static readonly MachineChoice s_model3Ram = new("ramKilobytes", "Memory",
        [new("48 KB", 48), new("32 KB", 32), new("16 KB", 16)], 48);

    private static MachineChoice Slot0(string initial) => new("slot0", "Slot 0",
    [
        new("Language card", "languageCard", "16 KB of RAM at $D000-$FFFF, which DOS 3.3 loads the other BASIC into"),
        new("Firmware card", "firmwareCard", "The other BASIC in ROM"),
        new("Empty", "empty"),
    ], initial);

    private static Dictionary<string, string> Options(params (string Key, string Value)[] options) =>
        options.ToDictionary(option => option.Key, option => option.Value);

    /// <summary>
    ///  Gets the machines, in the order Switch Machine lists them.
    /// </summary>
    internal static IReadOnlyList<CatalogMachine> Machines { get; } =
    [
        new("apple2-iie-enhanced", "Apple IIe (enhanced)", "65C02, 128 KB, 80 columns and MouseText",
            Options(("machine", "apple2"), ("model", "iie-enhanced")), [s_sound]),
        new("apple2-iie", "Apple IIe", "6502, 128 KB and 80 columns",
            Options(("machine", "apple2"), ("model", "iie")), [s_sound]),
        new("apple2-iiplus", "Apple II Plus", "6502, AppleSoft and the Autostart Monitor, 48 KB and a language card",
            Options(("machine", "apple2"), ("model", "iiplus")), [Slot0("languageCard"), s_ram, s_sound]),
        new("apple2-ii", "Apple II", "6502, Integer BASIC and the original Monitor, 48 KB",
            Options(("machine", "apple2"), ("model", "ii")),
            [
                new("monitor", "Monitor",
                [
                    new("Original", "original", "Reset stops at the Monitor's * prompt"),
                    new("Autostart", "autostart", "Boots a disk or starts BASIC"),
                ], "original"),
                Slot0("empty"),
                s_ram,
                new("boardRevision", "Board", [new("Revision 1 and later", 1), new("Revision 0", 0, "Four hi-res colors")], 1),
                new("programmersAid", "D0 socket",
                [
                    new("Empty", Value: false),
                    new("Programmer's Aid #1", Value: true, "Hi-res graphics, renumber, tape verify and more"),
                ], Default: false),
                s_sound,
            ]),
        new("apple3", "Apple III", "6502A at 1 or 2 MHz, 256 KB and the built-in drive",
            Options(("machine", "apple3")),
            [
                new("ramKilobytes", "Memory",
                [
                    new("256 KB", 256),
                    new("128 KB", 128, "The first Apple III"),
                    new("512 KB", 512, "With a third-party upgrade"),
                ], 256),
            ]),
        new("trs80-model1-level2", "TRS-80 Model I (Level II)", "Z80, Level II BASIC, 48 KB and the Expansion Interface",
            Options(("machine", "trs80-model1")),
            [
                new("expansionInterface", "Expansion Interface",
                [
                    new("With the Expansion Interface", Value: true, "48 KB, the clock interrupt and disks"),
                    new("Without it", Value: false, "16 KB, tapes only"),
                ], Default: true),
                s_lowercase,
            ]),
        new("trs80-model1-level1", "TRS-80 Model I (Level I)", "Z80, Level I BASIC and 4 KB",
            Options(("machine", "trs80-model1"), ("rom", "level1")), [s_lowercase]),
        new("trs80-model3", "TRS-80 Model III", "Z80 at 2 MHz, the Model III ROM, 48 KB and the FD1793",
            Options(("machine", "trs80-model3"), ("model", "3")), [s_model3Ram]),
        new("trs80-model3-level1", "TRS-80 Model III (Level I)", "Z80 at 2 MHz, the Model III's Level I BASIC and 250 baud tapes",
            Options(("machine", "trs80-model3"), ("model", "3"), ("rom", "level1")), [s_model3Ram]),
        new("trs80-model4", "TRS-80 Model 4", "Z80 at 4 MHz, the Model III ROM, 128 KB, 80x24 and the FD1793",
            Options(("machine", "trs80-model3"), ("model", "4")), [s_model4Ram]),
        new("trs80-model4p", "TRS-80 Model 4P", "Z80 at 4 MHz, the 4P's boot ROM, 128 KB, 80x24 and the FD1793",
            Options(("machine", "trs80-model3"), ("model", "4p")), [s_model4Ram]),
        new("trs80-model2", "TRS-80 Model II", "Z80 at 4 MHz, 64 KB, 80x24 and 8-inch disks",
            Options(("machine", "trs80-model2"), ("model", "2")), [s_model2Ram]),
        new("trs80-model12", "TRS-80 Model 12", "The Model II's successor: Z80 at 4 MHz, 80x24 and 8-inch disks",
            Options(("machine", "trs80-model2"), ("model", "12")), [s_model2Ram]),
        new("trs80-model16", "TRS-80 Model 16 (Z80 side)", "The Model 16, 16B or Tandy 6000 running Model II software; the 68000 board is not emulated",
            Options(("machine", "trs80-model2"), ("model", "16")), [s_model2Ram]),
        new("apple1", "Apple-1", "6502, the Woz Monitor, 4 KB plus 4 KB at $E000, and the cassette interface",
            Options(("machine", "apple1")),
            [
                new("ramKilobytes", "Memory", [new("4 KB", 4), new("8 KB", 8)], 4),
                new("highRam", "$E000 bank", [new("4 KB at $E000", Value: true, "Where BASIC loads and runs"), new("Empty", Value: false)], Default: true),
                new("cassetteInterface", "Cassette interface",
                [
                    new("The Apple Cassette Interface", Value: true, "Started from the Monitor with C100R"),
                    new("Empty slot", Value: false),
                ], Default: true),
            ]),
        new("coco1", "TRS-80 Color Computer", "6809, Extended Color BASIC 1.1 and 16 KB",
            Options(("machine", "coco"), ("model", "coco1")),
            [
                new("ramKilobytes", "Memory",
                [
                    new("16 KB", 16),
                    new("32 KB", 32),
                    new("64 KB", 64),
                    new("4 KB", 4, "Color BASIC alone"),
                ], 16),
                s_cocoDisk,
                s_cocoSound,
            ]),
        new("coco2", "TRS-80 Color Computer 2", "6809, Extended Color BASIC 1.1 and 64 KB",
            Options(("machine", "coco"), ("model", "coco2")),
            [
                new("lowercase", "Video chip",
                [
                    new("MC6847", Value: false, "Uppercase, lowercase shown inverse"),
                    new("MC6847T1", Value: true, "True lowercase, as on the CoCo 2B"),
                ], Default: false),
                s_cocoDisk,
                s_cocoSound,
            ]),
        new("coco3", "TRS-80 Color Computer 3", "6809, Extended Color BASIC 2.0, the GIME and 128 KB",
            Options(("machine", "coco"), ("model", "coco3")),
            [
                new("ramKilobytes", "Memory", [new("128 KB", 128), new("512 KB", 512)], 128),
                new("monitor", "Monitor",
                [
                    new("Composite", "composite", "A TV or composite monitor"),
                    new("RGB", "rgb", "The CM-8 RGB monitor"),
                ], "composite"),
                s_cocoDisk,
                s_cocoSound,
            ]),
        new("pet2001-basic2", "Commodore PET 2001 with BASIC 2", "6502, BASIC 2 (the upgrade ROMs), two Datasettes and 8 KB",
            Options(("machine", "pet"), ("model", "pet2001-basic2")),
            [s_petRam, s_petSnowOff, s_petSound]),
        new("pet2001", "Commodore PET 2001", "6502, BASIC 1, two Datasettes and 8 KB",
            Options(("machine", "pet"), ("model", "pet2001")),
            [
                s_petRam,
                new("basicRevision", "BASIC 1",
                [
                    new("Revised", "revised", "901447-09, as most 2001s have"),
                    new("Original", "original", "901447-01, the first chip"),
                ], "revised"),
                s_petSnow,
                s_petSound,
            ]),
        new("pet4032", "Commodore PET 4032", "6502, BASIC 4 with its disk commands, a 4040 disk drive and 32 KB",
            Options(("machine", "pet"), ("model", "pet4032")),
            [s_pet4032Ram, s_basic4Revision, s_petSound]),
        new("pet4032-business", "Commodore PET 4032 (business keyboard)",
            "6502, BASIC 4, the business keyboard, a 4040 disk drive and 32 KB",
            Options(("machine", "pet"), ("model", "pet4032-business")),
            [s_pet4032Ram, s_basic4Revision, s_petSound]),
        new("bbcb", "BBC Micro Model B", "6502 at 2 MHz, MOS 1.20, BASIC II, DNFS 1.20 and 32 KB",
            Options(("machine", "bbc"), ("model", "bbcb")),
            [
                new("diskInterface", "Disk interface",
                [
                    new("Intel 8271", Value: true, "Acorn DFS and two drives"),
                    new("None", Value: false, "Tapes only, with PAGE at &E00"),
                ], Default: true),
                s_bbcSound,
            ]),
        new("bbca", "BBC Micro Model A", "6502 at 2 MHz, MOS 1.20, BASIC II and 16 KB",
            Options(("machine", "bbc"), ("model", "bbca")),
            [s_bbcSound]),
        new("altair", "MITS Altair 8800", "8080, a terminal on the 88-2SIO or 88-SIO, the 88-ACR cassette, 88-DCDD 8-inch disks and 64 KB",
            Options(("machine", "altair")),
            [
                new("ramKilobytes", "Memory",
                [
                    new("64 KB", 64),
                    new("48 KB", 48),
                    new("32 KB", 32),
                    new("16 KB", 16),
                    new("4 KB", 4, "As the first Altairs shipped"),
                ], 64),
                new("console", "Terminal",
                [
                    new("On the 88-2SIO", "2sio", "Ports $10 and $11; 4.0 BASICs with the switches down"),
                    new("On the 88-SIO", "sio", "Ports $00 and $01; 4K BASIC 3.2 with the switches down"),
                ], "2sio"),
                new("upperCase", "Caps lock", [new("Off", Value: false), new("On", Value: true, "Letters type as capitals, as Altair BASIC needs")], Default: false),
                new("diskController", "Disk controller",
                [
                    new("None", Value: false),
                    new("88-DCDD", Value: true, "Four 8-inch drives, with DBL at $FF00 to boot drive 0"),
                ], Default: false),
            ]),
        new("kaypro2", "Kaypro II", "Z80 at 2.5 MHz, 64 KB, 80x24 and two drives, running CP/M 2.2",
            Options(("machine", "kaypro2")), []),
    ];

    // The models a launch option names, as the debug host reads them, by machine: an alias, or none for its default.
    private static readonly Dictionary<string, Dictionary<string, string>> s_models = new()
    {
        ["apple2"] = new() { [""] = "iie-enhanced", ["enhanced"] = "iie-enhanced", ["original"] = "iie" },
        ["coco"] = new() { [""] = "coco2" },
        ["pet"] = new() { [""] = "pet2001-basic2" },
        ["bbc"] = new() { [""] = "bbcb" },
        ["trs80-model3"] = new()
        {
            [""] = "3",
            ["III"] = "3",
            ["model3"] = "3",
            ["model4"] = "4",
            ["4P"] = "4p",
            ["model4p"] = "4p"
        },
        ["trs80-model2"] = new()
        {
            [""] = "2",
            ["II"] = "2",
            ["model2"] = "2",
            ["model12"] = "12",
            ["16b"] = "16",
            ["6000"] = "16",
            ["model16"] = "16"
        },
    };

    // The machine names the debug host takes for another: the Model 4 is the Model III's machine, a 4 unless it says.
    private static readonly Dictionary<string, (string Machine, string Model)> s_aliases = new()
    {
        ["apple2e"] = ("apple2", ""),
        ["trs80-model4"] = ("trs80-model3", "4"),
    };

    /// <summary>
    ///  Gets the machine a launch configuration's machine name is, as the debug host reads it: <c>apple2e</c> is an
    ///  Apple II, and <c>trs80-model4</c> a Model III.
    /// </summary>
    /// <param name="machine">The name.</param>
    /// <returns>The machine it names.</returns>
    internal static string Kind(string machine) => s_aliases.TryGetValue(machine, out (string Machine, string Model) alias) ? alias.Machine : machine;

    /// <summary>
    ///  Finds a machine by its id.
    /// </summary>
    /// <param name="id">The machine's id.</param>
    /// <returns>The machine, or null.</returns>
    internal static CatalogMachine? ById(string id) => Machines.FirstOrDefault(machine => machine.Id == id);

    /// <summary>
    ///  Gets the launch configuration that starts a machine as it is.
    /// </summary>
    /// <param name="machine">The machine.</param>
    /// <returns>Its configuration, named for it.</returns>
    internal static JsonObject Configuration(CatalogMachine machine)
    {
        JsonObject configuration = new() { ["name"] = machine.Label };
        foreach ((string key, string value) in machine.Configuration) { configuration[key] = value; }
        return configuration;
    }

    /// <summary>
    ///  Gets the catalog machine a launch configuration starts, as the debug host reads its machine, model and rom.
    /// </summary>
    /// <param name="configuration">The launch configuration.</param>
    /// <returns>The machine, or null for one the catalog lacks.</returns>
    internal static CatalogMachine? Find(JsonObject configuration)
    {
        string machine = Text(configuration["machine"]) ?? "";
        (string Machine, string Model)? alias = s_aliases.TryGetValue(machine, out (string, string) found) ? found : null;
        string kind = alias?.Machine ?? machine;
        string named = Text(configuration["model"]) ?? alias?.Model ?? "";
        string model = s_models.TryGetValue(kind, out Dictionary<string, string>? models) && models.TryGetValue(named, out string? known) ? known : named;

        // The Model I and the Model III choose Level I or Level II BASIC by their rom.
        bool roms = kind is "trs80-model1" or "trs80-model3";
        string rom = roms ? Text(configuration["rom"]) ?? "level2" : "";
        return Machines.FirstOrDefault(candidate => candidate.Configuration["machine"] == kind
            && (candidate.Configuration.TryGetValue("model", out string? own) ? own : "") == model
            && (!roms || (candidate.Configuration.TryGetValue("rom", out string? romOwn) ? romOwn : "level2") == rom));
    }

    /// <summary>
    ///  Gets the value a launch configuration gives a setting: its own, or what it is when left out, as the debug host
    ///  decides: the setting's default, except that disks given bring their disk controller.
    /// </summary>
    /// <param name="choice">The setting.</param>
    /// <param name="configuration">The launch configuration.</param>
    /// <returns>The value.</returns>
    internal static object Value(MachineChoice choice, JsonObject configuration) =>
        configuration[choice.Option] is JsonValue value && Plain(value) is { } plain ? plain : Implied(choice, configuration);

    /// <summary>
    ///  Gets a launch configuration with a setting changed, leaving the option out when it is what it would be without it.
    /// </summary>
    /// <param name="configuration">The configuration.</param>
    /// <param name="choice">The setting.</param>
    /// <param name="value">Its new value.</param>
    /// <returns>A new configuration.</returns>
    internal static JsonObject WithSetting(JsonObject configuration, MachineChoice choice, object value)
    {
        JsonObject changed = (JsonObject)configuration.DeepClone();
        if (Equals(value, Implied(choice, configuration)))
        {
            changed.Remove(choice.Option);
        }
        else
        {
            changed[choice.Option] = Node(value);
        }

        return changed;
    }

    /// <summary>
    ///  Gets whether a launch configuration starts with disks in its drives.
    /// </summary>
    /// <param name="configuration">The configuration.</param>
    /// <returns>True when it names disks.</returns>
    internal static bool StartsWithDisks(JsonObject configuration) => configuration["disks"] is JsonArray
    {
        Count: > 0
    };

    /// <summary>
    ///  Gets a value as JSON.
    /// </summary>
    /// <param name="value">A string, number or bool.</param>
    /// <returns>Its JSON.</returns>
    internal static JsonNode Node(object value) => value switch
    {
        bool flag => JsonValue.Create(flag),
        int number => JsonValue.Create(number),
        _ => JsonValue.Create(value.ToString() ?? ""),
    };

    private static object Implied(MachineChoice choice, JsonObject configuration) =>
        choice.Option == "diskController" && StartsWithDisks(configuration) ? true : choice.Default;

    // A JSON value as the catalog's values are: a string, a whole number or a bool.
    private static object? Plain(JsonValue value)
    {
        if (value.TryGetValue(out bool flag)) { return flag; }
        if (value.TryGetValue(out int number)) { return number; }
        if (value.TryGetValue(out double real) && real == Math.Floor(real) && real is >= int.MinValue and <= int.MaxValue)
        {
            return (int)real;
        }

        return value.TryGetValue(out string? text) ? text : null;
    }

    private static string? Text(JsonNode? node) => node is JsonValue value && value.TryGetValue(out string? text) ? text : null;
}