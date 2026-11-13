// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using System.Globalization;
using Retrocore.Assembler;
using Retrocore.Machines.Apple2;

namespace Retrocore.Debug;

/// <summary>
///  Builds debug modules from the SDK's ROM sources, shipped beside the debug host.
/// </summary>
/// <remarks>
///  <para>
///   Each source is assembled in-process, so stepping uses its source map directly. Today the SDK has the
///   emulated slot-seven block device's firmware, AppleSoft II (Microsoft's MACRO-10 source with Apple's
///   changes as an overlay), the Monitor and the internal $C100-$CFFF firmware, each faithful to the launched
///   model; the manifest of ROMs and variants comes later.
///  </para>
/// </remarks>
internal static class SdkModules
{
    /// <summary>
    ///  Gets AppleSoft II's first address.
    /// </summary>
    internal const int AppleSoftOrigin = 0xD000;

    /// <summary>
    ///  Gets AppleSoft II's size: $D000-$F7FF.
    /// </summary>
    internal const int AppleSoftSize = 0x2800;

    /// <summary>
    ///  Gets the Monitor's first address.
    /// </summary>
    internal const int MonitorOrigin = 0xF800;

    /// <summary>
    ///  Gets the Monitor's size: $F800-$FFFF.
    /// </summary>
    internal const int MonitorSize = 0x800;

    /// <summary>
    ///  Gets the internal firmware's first address.
    /// </summary>
    internal const int FirmwareOrigin = 0xC100;

    /// <summary>
    ///  Gets the internal firmware's size: $C100-$CFFF.
    /// </summary>
    internal const int FirmwareSize = 0xF00;

    /// <summary>
    ///  Gets the video ROM's size: the 4 KiB character generator.
    /// </summary>
    internal const int CharacterGeneratorSize = 0x1000;

    /// <summary>
    ///  Gets the Disk II boot ROM's first address, in slot six.
    /// </summary>
    internal const int DiskIIOrigin = 0xC600;

    /// <summary>
    ///  Gets the size of each Disk II ROM: the boot ROM and the sequencer.
    /// </summary>
    internal const int DiskIIRomSize = 0x100;

    /// <summary>
    ///  Gets DOS 3.3's first address where it runs, on a IIe with 48K or more.
    /// </summary>
    internal const int DosOrigin = 0x9D00;

    /// <summary>
    ///  Gets the size of DOS 3.3 where it runs: $9D00-$BFFF.
    /// </summary>
    internal const int DosSize = 0x2300;

    /// <summary>
    ///  Gets the first address of the DOS 3.3 System Master's image: the relocator, then DOS a page later.
    /// </summary>
    internal const int DosMasterOrigin = 0x1B00;

    /// <summary>
    ///  Gets the size of the DOS 3.3 System Master's image: $1B00-$3FFF.
    /// </summary>
    internal const int DosMasterSize = 0x2500;

    /// <summary>
    ///  The first address of the Apple II's Integer BASIC ROM, with its floating point, Mini-Assembler and SWEET16.
    /// </summary>
    internal const int IntegerBasicOrigin = 0xE000;

    /// <summary>
    ///  The size of the Integer BASIC ROM, $E000-$F7FF.
    /// </summary>
    internal const int IntegerBasicSize = 0x1800;

    /// <summary>
    ///  The first address of Programmer's Aid #1, in a II's D0 socket or a language card.
    /// </summary>
    internal const int ProgrammersAidOrigin = 0xD000;

    /// <summary>
    ///  The size of Programmer's Aid #1, $D000-$D7FF.
    /// </summary>
    internal const int ProgrammersAidSize = 0x800;

    /// <summary>
    ///  The size of the II and II Plus's character generator, 7341-0036.
    /// </summary>
    internal const int BoardCharacterGeneratorSize = 0x800;

    // The II and II Plus's system ROM, $D000-$FFFF.
    private const int BoardRomOrigin = 0xD000;
    private const int BoardRomSize = 0x3000;

    private const int AddressSpaceSize = 0x10000;
    private const int SystemRomOrigin = 0xC000;
    private const int SystemRomSize = 0x4000;

    /// <summary>
    ///  Gets or sets the SDK's ROM source directory when it is not the one beside the debug host.
    /// </summary>
    internal static string? DefaultDirectory { get; set; }

    /// <summary>
    ///  Gets the SDK's ROM source directory: <see cref="DefaultDirectory"/>, or the one beside the debug host.
    /// </summary>
    internal static string RomDirectory => DefaultDirectory ?? Path.Join(AppContext.BaseDirectory, "Sdk", "Roms");

    /// <summary>
    ///  Adds the modules for every SDK ROM source present.
    /// </summary>
    /// <param name="debug">The session's modules.</param>
    /// <param name="model">The emulated model, which selects each ROM's faithful variant.</param>
    /// <param name="directory">The ROM source directory; by default the copy beside the debug host.</param>
    /// <param name="autostart">For the II, whether its Monitor is the Autostart ROM.</param>
    /// <returns>The AppleSoft assembly, for BASIC's addresses; null when its source is missing.</returns>
    internal static AssemblyResult? AddTo(DebugInfo debug, Apple2Model model, string? directory = null, bool autostart = false) =>
        AddTo(debug, model, directory, out _, autostart);

    /// <summary>
    ///  Adds the modules for every SDK ROM source present, and gives Integer BASIC's assembly too.
    /// </summary>
    /// <param name="debug">The session's modules.</param>
    /// <param name="model">The emulated model, which selects each ROM's faithful variant.</param>
    /// <param name="directory">The ROM source directory; by default the copy beside the debug host.</param>
    /// <param name="integer">Integer BASIC's assembly, for its addresses; null when its source is missing.</param>
    /// <param name="autostart">For the II, whether its Monitor is the Autostart ROM.</param>
    /// <returns>The AppleSoft assembly, for BASIC's addresses; null when its source is missing.</returns>
    internal static AssemblyResult? AddTo(
        DebugInfo debug,
        Apple2Model model,
        string? directory,
        out AssemblyResult? integer,
        bool autostart = false)
    {
        AssemblyResult? basic = null;
        integer = null;
        string roms = directory ?? RomDirectory;
        string slot7 = Path.Join(roms, "Slot7.rom.asm");
        if (File.Exists(slot7)) { debug.Add(new SourceMapModule(AssembleRom(slot7), Apple2MemoryArea.Slot7Rom)); }

        // The mouse, ProFile and 3.5 controller cards' firmware reaches nothing inside itself by an absolute address, so
        // it works in any slot: one assembly maps each slot's page, wherever the card's whole ROM is the one installed (a
        // Disk II's boot ROM starts with the same LDX #$20 as the ProFile's and the 3.5 controller's).
        foreach (string card in (ReadOnlySpan<string>)["Mouse.rom.asm", "ProFile.rom.asm", "Disk35.rom.asm"])
        {
            string path = Path.Join(roms, card);
            if (!File.Exists(path)) { continue; }
            AssemblyResult cardRom = AssembleRom(path);
            for (int slot = 1; slot <= 7; slot++)
            {
                int page = 0xC000 | (slot << 8);
                debug.Add(new SourceMapModule(
                    cardRom,
                    Apple2MemoryArea.Slot1Rom + (slot - 1),
                    relocation: page - cardRom.Sections[0].Origin,
                    wholeImage: true));
            }
        }

        // Either boot ROM may be in slot six; each maps only where its bytes are the ones installed.
        foreach (int sectors in (ReadOnlySpan<int>)[16, 13])
        {
            string boot = DiskIIPath($"Boot{sectors}.asm", roms);
            if (File.Exists(boot))
            {
                debug.Add(new SourceMapModule(AssembleDiskII(boot, DiskIIOrigin), Apple2MemoryArea.Slot6Rom));
            }
        }

        // A source line applies only where the running bytes match it, so dumps of other revisions show disassembly.
        string appleSoft = Path.Join(roms, "AppleSoft", "applesoft.mac");
        if (File.Exists(appleSoft))
        {
            basic = AssembleAppleSoft(appleSoft, model);
            debug.Add(new SourceMapModule(basic, Apple2MemoryArea.SystemRom, collapseSingleStatementMacros: true));
        }

        // DOS runs from RAM, so each build maps only while memory holds the bytes it assembles to.
        string dos = DosPath("Dos33.asm", roms);
        if (File.Exists(dos))
        {
            foreach (int year in (ReadOnlySpan<int>)[1983, 1980])
            {
                debug.Add(new SourceMapModule(AssembleDos(dos, master: false, year), Apple2MemoryArea.MainRam));
            }
        }

        string dos32 = DosPath("Dos32.asm", roms);
        if (File.Exists(dos32))
        {
            debug.Add(new SourceMapModule(AssembleDos(dos32, master: false), Apple2MemoryArea.MainRam));
        }

        string monitor = Path.Join(roms, "System", "Monitor.asm");
        if (File.Exists(monitor))
        {
            AssemblyResult monitorBuild = AssembleSystem(monitor, MonitorOrigin, MonitorSize, model, autostart);
            debug.Add(new SourceMapModule(monitorBuild, Apple2MemoryArea.SystemRom));
        }

        // Integer BASIC is the II's ROM and a II Plus's firmware card's, and DOS 3.3's INT loads it into a language
        // card on any model: the 1980 System Master's INTBASIC as the ROM is, the 1983 master's with FORFIX. Each
        // maps only where its bytes are the ones in memory.
        string integerPath = IntegerBasicPath(roms);
        if (File.Exists(integerPath))
        {
            integer = AssembleIntegerBasic(integerPath);
            if (!model.IsIIe()) { debug.Add(new SourceMapModule(integer, Apple2MemoryArea.SystemRom)); }
            debug.Add(new SourceMapModule(integer, Apple2MemoryArea.MainLanguageCard));
            debug.Add(new SourceMapModule(AssembleIntegerBasic(integerPath, forFix: true), Apple2MemoryArea.MainLanguageCard));
        }

        // Programmer's Aid #1 is a chip for the II's D0 socket, and comes with Integer BASIC in the System Masters'
        // INTBASIC: the 1980 masters' as the chip is, the 1983 master's with RAMTESTFIX.
        string programmersAid = ProgrammersAidPath(roms);
        if (File.Exists(programmersAid))
        {
            AssemblyResult chip = AssembleProgrammersAid(programmersAid);
            if (!model.IsIIe()) { debug.Add(new SourceMapModule(chip, Apple2MemoryArea.SystemRom)); }
            debug.Add(new SourceMapModule(chip, Apple2MemoryArea.MainLanguageCard));
            debug.Add(new SourceMapModule(AssembleProgrammersAid(programmersAid, ramTestFix: true), Apple2MemoryArea.MainLanguageCard));
        }

        // The II and II Plus have no built-in firmware.
        if (!model.IsIIe()) { return basic; }

        string firmware = FirmwarePath(model, roms);
        if (File.Exists(firmware))
        {
            debug.Add(new SourceMapModule(AssembleSystem(firmware, FirmwareOrigin, FirmwareSize, model), Apple2MemoryArea.SystemRom));
        }

        return basic;
    }

    /// <summary>
    ///  Builds a model's system and video ROMs from the SDK's sources, byte-identical to its chips.
    /// </summary>
    /// <remarks>
    ///  <para>
    ///   The IIe's system ROM is the internal firmware ($C100-$CFFF), AppleSoft II ($D000-$F7FF) and the Monitor
    ///   ($F800-$FFFF); $C000-$C0FF is soft switches and never reads as ROM, so it is zero. The II and II Plus's is
    ///   <see cref="BuildBoardSystem"/>'s 12 KiB, with their own character generator.
    ///  </para>
    /// </remarks>
    /// <param name="model">The model.</param>
    /// <param name="directory">The ROM source directory; by default the copy beside the debug host.</param>
    /// <param name="autostart">For the II, whether its Monitor is the Autostart ROM.</param>
    /// <returns>The ROMs.</returns>
    /// <exception cref="InvalidDataException">A source has errors.</exception>
    /// <exception cref="FileNotFoundException">A source is missing.</exception>
    internal static Apple2Roms BuildRoms(Apple2Model model, string? directory = null, bool autostart = false)
    {
        string roms = directory ?? RomDirectory;
        if (!model.IsIIe())
        {
            AssemblyResult glyphs = AssembleCharacterGenerator(CharacterGeneratorPath(roms), model);
            return Apple2Roms.FromBoardChips(BuildBoardSystem(model, autostart, roms), glyphs.Sections[0].Bytes.Span);
        }

        byte[] system = new byte[SystemRomSize];
        Place(system, AssembleSystem(FirmwarePath(model, roms), FirmwareOrigin, FirmwareSize, model));
        Place(system, AssembleSystem(Path.Join(roms, "System", "Monitor.asm"), MonitorOrigin, MonitorSize, model));
        AppleSoftImage(AssembleAppleSoft(Path.Join(roms, "AppleSoft", "applesoft.mac"), model))
            .Span
            .CopyTo(system.AsSpan(AppleSoftOrigin - SystemRomOrigin));

        AssemblyResult characters = AssembleCharacterGenerator(CharacterGeneratorPath(roms), model);
        return new(system, characters.Sections[0].Bytes.Span);
    }

    /// <summary>
    ///  Builds the 12 KiB system ROM of an Apple II or II Plus, $D000-$FFFF, from the SDK's sources, as its chips
    ///  hold it: AppleSoft and the Autostart Monitor for the II Plus; Integer BASIC and the original or Autostart
    ///  Monitor for the II, whose $D000-$DFFF sockets are empty ($FF). A firmware card holds the other model's.
    /// </summary>
    /// <param name="model">The II or II Plus.</param>
    /// <param name="autostart">For the II, whether its Monitor is the Autostart ROM.</param>
    /// <param name="directory">The ROM source directory; by default the copy beside the debug host.</param>
    /// <param name="programmersAid">For the II, whether its D0 socket holds Programmer's Aid #1.</param>
    /// <returns>The 12 KiB.</returns>
    /// <exception cref="InvalidDataException">A source has errors.</exception>
    internal static byte[] BuildBoardSystem(
        Apple2Model model,
        bool autostart,
        string? directory = null,
        bool programmersAid = false)
    {
        string roms = directory ?? RomDirectory;
        byte[] system = new byte[BoardRomSize];
        system.AsSpan().Fill(0xFF);
        if (model == Apple2Model.IIPlus)
        {
            AppleSoftImage(AssembleAppleSoft(Path.Join(roms, "AppleSoft", "applesoft.mac"), model))
                .Span
                .CopyTo(system.AsSpan(AppleSoftOrigin - BoardRomOrigin));
        }
        else
        {
            AssembleIntegerBasic(IntegerBasicPath(roms)).Sections[0].Bytes.Span
                .CopyTo(system.AsSpan(IntegerBasicOrigin - BoardRomOrigin));

            if (programmersAid)
            {
                AssembleProgrammersAid(ProgrammersAidPath(roms)).Sections[0].Bytes.Span
                    .CopyTo(system.AsSpan(ProgrammersAidOrigin - BoardRomOrigin));
            }
        }

        AssemblyResult monitor = AssembleSystem(Path.Join(roms, "System", "Monitor.asm"), MonitorOrigin, MonitorSize, model, autostart);
        monitor.Sections[0].Bytes.Span.CopyTo(system.AsSpan(MonitorOrigin - BoardRomOrigin));
        return system;
    }

    /// <summary>
    ///  Gets the root of the Apple II's Integer BASIC ROM source.
    /// </summary>
    /// <param name="directory">The ROM source directory; by default the copy beside the debug host.</param>
    /// <returns>The path of <c>IntegerBasic.asm</c>.</returns>
    internal static string IntegerBasicPath(string? directory = null) =>
        Path.Join(directory ?? RomDirectory, "IntegerBasic", "IntegerBasic.asm");

    /// <summary>
    ///  Assembles the Apple II's Integer BASIC ROM, $E000-$F7FF, byte-identical to its chips 341-0001 to 341-0003.
    /// </summary>
    /// <param name="path">The <c>IntegerBasic.asm</c> source.</param>
    /// <param name="forFix">
    ///  Whether to build the 1983 DOS 3.3 System Master's Integer BASIC, given to the source as <c>FORFIX</c>, which
    ///  fixes FOR's removal of an older loop for the same variable.
    /// </param>
    /// <returns>The assembly.</returns>
    /// <exception cref="InvalidDataException">The source has errors.</exception>
    internal static AssemblyResult AssembleIntegerBasic(string path, bool forFix = false)
    {
        Dictionary<string, long> symbols = new() { ["FORFIX"] = forFix ? 1 : 0 };
        return AssembleSystem(path, IntegerBasicOrigin, IntegerBasicSize, Apple2Model.II, symbols: symbols);
    }

    /// <summary>
    ///  Gets the root of Programmer's Aid #1's source.
    /// </summary>
    /// <param name="directory">The ROM source directory; by default the copy beside the debug host.</param>
    /// <returns>The path of <c>ProgrammersAid.asm</c>.</returns>
    internal static string ProgrammersAidPath(string? directory = null) =>
        Path.Join(directory ?? RomDirectory, "ProgrammersAid", "ProgrammersAid.asm");

    /// <summary>
    ///  Assembles Programmer's Aid #1, $D000-$D7FF, byte-identical to its chip, 341-0016.
    /// </summary>
    /// <param name="path">The <c>ProgrammersAid.asm</c> source.</param>
    /// <param name="ramTestFix">
    ///  Whether to build the 1983 DOS 3.3 System Master's, given to the source as <c>RAMTESTFIX</c>, whose RAM test
    ///  prints a byte where the chip jumps to $02CB.
    /// </param>
    /// <returns>The assembly.</returns>
    /// <exception cref="InvalidDataException">The source has errors.</exception>
    internal static AssemblyResult AssembleProgrammersAid(string path, bool ramTestFix = false)
    {
        Dictionary<string, long> symbols = new() { ["RAMTESTFIX"] = ramTestFix ? 1 : 0 };
        return AssembleSystem(path, ProgrammersAidOrigin, ProgrammersAidSize, Apple2Model.II, symbols: symbols);
    }

    /// <summary>
    ///  Builds the Disk II controller's ROMs from the SDK's sources, byte-identical to its chips.
    /// </summary>
    /// <param name="sectors">16 for the 341-0027 and 341-0028 chips, 13 for 341-0009 and 341-0010.</param>
    /// <param name="directory">The ROM source directory; by default the copy beside the debug host.</param>
    /// <returns>The firmware.</returns>
    /// <exception cref="ArgumentOutOfRangeException"><paramref name="sectors"/> is not 13 or 16.</exception>
    /// <exception cref="InvalidDataException">A source has errors.</exception>
    internal static DiskIIFirmware BuildDiskII(int sectors, string? directory = null)
    {
        if (sectors is not (13 or 16)) { throw new ArgumentOutOfRangeException(nameof(sectors)); }
        AssemblyResult boot = AssembleDiskII(DiskIIPath($"Boot{sectors}.asm", directory), DiskIIOrigin);
        AssemblyResult sequencer = AssembleDiskII(DiskIIPath($"Sequencer{sectors}.asm", directory), origin: 0);
        return new(boot.Sections[0].Bytes.Span, sequencer.Sections[0].Bytes.Span, P6PromLayout.Raw);
    }

    /// <summary>
    ///  Gets a Disk II ROM source.
    /// </summary>
    /// <param name="file">The file, such as <c>Boot16.asm</c>.</param>
    /// <param name="directory">The ROM source directory; by default the copy beside the debug host.</param>
    /// <returns>The path.</returns>
    internal static string DiskIIPath(string file, string? directory = null) =>
        Path.Join(directory ?? RomDirectory, "DiskII", file);

    /// <summary>
    ///  Gets a DOS 3.3 source.
    /// </summary>
    /// <param name="file">The file, such as <c>Dos33.asm</c> or <c>Dos32.asm</c>.</param>
    /// <param name="directory">The SDK source directory; by default the copy beside the debug host.</param>
    /// <returns>The path, in the <c>Dos</c> folder, which holds both versions' sources.</returns>
    internal static string DosPath(string file, string? directory = null) =>
        Path.Join(directory ?? RomDirectory, "Dos", file);

    /// <summary>
    ///  Assembles DOS 3.3: the System Master's image at $1B00, or DOS where it runs at $9D00.
    /// </summary>
    /// <remarks>
    ///  <para>
    ///   1983 is the DOS on the 680-0210-A System Master; 1980 is the one on the 680-0051 masters. DOS 3.2's
    ///   source (<c>Dos32.asm</c>) builds the same way and ignores the year.
    ///  </para>
    /// </remarks>
    /// <param name="path">The <c>Dos33.asm</c> source.</param>
    /// <param name="master">
    ///  Whether to build the master's image, with its relocator, rather than the running copy.
    /// </param>
    /// <param name="year">1983 or 1980: which DOS 3.3 to build.</param>
    /// <returns>The assembly.</returns>
    /// <exception cref="InvalidDataException">The source has errors.</exception>
    internal static AssemblyResult AssembleDos(string path, bool master, int year = 1983)
    {
        string full = Path.GetFullPath(path);
        AssemblyOptions options = new(
            ProcessorVariant.Mos6502,
            master ? DosMasterOrigin : DosOrigin,
            master ? DosMasterSize : DosSize)
        {
            SourceResolver = new FileAssemblySourceResolver(),
            PredefinedSymbols = new Dictionary<string, long> { ["MASTER"] = master ? 1 : 0, ["YEAR"] = year }
        };

        AssemblyResult result = new Assembler.Assembler().Assemble(new AssemblySource(File.ReadAllText(full), full), options);
        return result.Success
            ? result
            : throw new InvalidDataException(string.Join(Environment.NewLine, result.Diagnostics.Select(diagnostic => diagnostic.Message)));
    }

    /// <summary>
    ///  Assembles a Disk II ROM source: a boot ROM at $C600 or a sequencer at 0.
    /// </summary>
    /// <param name="path">The source.</param>
    /// <param name="origin">Its first address.</param>
    /// <returns>The 256-byte assembly.</returns>
    /// <exception cref="InvalidDataException">The source has errors.</exception>
    internal static AssemblyResult AssembleDiskII(string path, int origin)
    {
        string full = Path.GetFullPath(path);
        AssemblyOptions options = new(ProcessorVariant.Mos6502, origin, DiskIIRomSize)
        {
            SourceResolver = new FileAssemblySourceResolver()
        };

        AssemblyResult result = new Assembler.Assembler().Assemble(new AssemblySource(File.ReadAllText(full), full), options);
        return result.Success
            ? result
            : throw new InvalidDataException(string.Join(Environment.NewLine, result.Diagnostics.Select(diagnostic => diagnostic.Message)));
    }

    /// <summary>
    ///  Gets the video ROM's source, which builds either model's chip.
    /// </summary>
    /// <param name="directory">The ROM source directory; by default the copy beside the debug host.</param>
    /// <returns>The path.</returns>
    internal static string CharacterGeneratorPath(string? directory = null) =>
        Path.Join(directory ?? RomDirectory, "System", "CharacterGenerator.asm");

    /// <summary>
    ///  Assembles the character generator for a model: 342-0133 for the original IIe, 342-0265 for the Enhanced
    ///  IIe, 7341-0036 for the II and II Plus.
    /// </summary>
    /// <param name="path">The <c>CharacterGenerator.asm</c> source.</param>
    /// <param name="model">The model, given to the source as <c>IIBOARD</c> and <c>ENHANCED</c>.</param>
    /// <returns>The assembly: 4 KiB for the IIe, 2 KiB for the II and II Plus.</returns>
    /// <exception cref="InvalidDataException">The source has errors.</exception>
    internal static AssemblyResult AssembleCharacterGenerator(string path, Apple2Model model) =>
        AssembleSystem(path, origin: 0, model.IsIIe() ? CharacterGeneratorSize : BoardCharacterGeneratorSize, model);

    /// <summary>
    ///  Gets the internal firmware source for a model; the Enhanced IIe rewrote nearly all of it.
    /// </summary>
    /// <param name="model">The model.</param>
    /// <param name="directory">The ROM source directory; by default the copy beside the debug host.</param>
    /// <returns>The path.</returns>
    internal static string FirmwarePath(Apple2Model model, string? directory = null) =>
        Path.Join(directory ?? RomDirectory, "System", model.IsEnhanced() ? "Firmware.Enhanced.asm" : "Firmware.Original.asm");

    /// <summary>
    ///  Assembles one of the SDK's native system ROM sources for a model.
    /// </summary>
    /// <param name="path">The source.</param>
    /// <param name="origin">Its first address.</param>
    /// <param name="size">Its size.</param>
    /// <param name="model">
    ///  The model, given to the source as <c>ENHANCED</c> (the Enhanced IIe), <c>IIBOARD</c> (the II and II Plus) and
    ///  <c>MONITOR</c> (0 for the II's original Monitor, 1 for the Autostart Monitor, 2 for the IIe's).
    /// </param>
    /// <param name="autostart">For the II, whether its Monitor is the Autostart ROM; the II Plus's always is.</param>
    /// <param name="symbols">More predefined symbols, such as <c>FORFIX</c> for Integer BASIC.</param>
    /// <returns>The assembly, byte-identical to that part of the model's ROM.</returns>
    /// <exception cref="InvalidDataException">The source has errors.</exception>
    internal static AssemblyResult AssembleSystem(
        string path,
        int origin,
        int size,
        Apple2Model model,
        bool autostart = false,
        IReadOnlyDictionary<string, long>? symbols = null)
    {
        string full = Path.GetFullPath(path);
        int monitor = model.IsIIe() ? 2 : model == Apple2Model.IIPlus || autostart ? 1 : 0;
        Dictionary<string, long> predefined = new()
        {
            ["ENHANCED"] = model == Apple2Model.IIeEnhanced ? 1 : 0,
            ["IIBOARD"] = model.IsIIe() ? 0 : 1,
            ["MONITOR"] = monitor
        };

        foreach ((string name, long value) in symbols ?? new Dictionary<string, long>())
        {
            predefined[name] = value;
        }

        AssemblyOptions options = new(ProcessorVariant.Mos6502, origin, size)
        {
            SourceResolver = new FileAssemblySourceResolver(),
            PredefinedSymbols = predefined
        };

        AssemblyResult result = new Assembler.Assembler().Assemble(new AssemblySource(File.ReadAllText(full), full), options);
        return result.Success
            ? result
            : throw new InvalidDataException(string.Join(Environment.NewLine, result.Diagnostics.Select(diagnostic => diagnostic.Message)));
    }

    /// <summary>
    ///  Assembles AppleSoft II, whose ROM at $D000-$F7FF is byte-identical to the given model's.
    /// </summary>
    /// <remarks>
    ///  <para>
    ///   The source also lays out its page-zero storage, so it assembles over the whole address space;
    ///   <see cref="AppleSoftImage(AssemblyResult)"/> gives the ROM itself.
    ///  </para>
    /// </remarks>
    /// <param name="path">The <c>applesoft.mac</c> overlay, beside the <c>m6502.asm</c> it edits.</param>
    /// <param name="model">The model; <c>ENHNCD</c> selects the Enhanced IIe's changes.</param>
    /// <returns>The assembly.</returns>
    /// <exception cref="InvalidDataException">The source has errors.</exception>
    internal static AssemblyResult AssembleAppleSoft(string path, Apple2Model model)
    {
        string full = Path.GetFullPath(path);
        AssemblyOptions options = new(ProcessorVariant.Mos6502, 0, AddressSpaceSize)
        {
            SourceResolver = new FileAssemblySourceResolver(),
            PredefinedSymbols = new Dictionary<string, long>
            {
                ["ENHNCD"] = model == Apple2Model.IIeEnhanced ? 1 : 0,
                ["APLPLS"] = model.IsIIe() ? 0 : 1
            }
        };

        AssemblyResult result = new Assembler.Assembler().Assemble(new AssemblySource(File.ReadAllText(full), full), options);
        return result.Success
            ? result
            : throw new InvalidDataException(string.Join(Environment.NewLine, result.Diagnostics.Select(diagnostic => diagnostic.Message)));
    }

    /// <summary>
    ///  Assembles a ROM source in the source generator's <c>.rom Namespace.Type, origin, size</c> form.
    /// </summary>
    /// <param name="path">The source path.</param>
    /// <returns>The assembly.</returns>
    /// <exception cref="InvalidDataException">The declaration is missing or the source has errors.</exception>
    internal static AssemblyResult AssembleRom(string path)
    {
        string full = Path.GetFullPath(path);
        string[] lines = File.ReadAllLines(full);
        int declaration = Array.FindIndex(lines, line => line.TrimStart().StartsWith(".rom ", StringComparison.OrdinalIgnoreCase));
        string[] fields = declaration < 0 ? [] : lines[declaration].TrimStart()[5..].Split(',');
        if (fields.Length != 3)
        {
            throw new InvalidDataException($"{full}: expected one '.rom Namespace.Type, origin, size' declaration.");
        }

        // The declaration is generator metadata; blanking it keeps every other line where it was.
        lines[declaration] = "";
        AssemblyOptions options = new(ProcessorVariant.Mos6502, Number(fields[1]), Number(fields[2]))
        {
            SourceResolver = new FileAssemblySourceResolver()
        };

        AssemblyResult result = new Assembler.Assembler().Assemble(new AssemblySource(string.Join('\n', lines), full), options);
        return result.Success
            ? result
            : throw new InvalidDataException(string.Join(Environment.NewLine, result.Diagnostics.Select(diagnostic => diagnostic.Message)));
    }

    /// <summary>
    ///  Gets the ROM bytes of an AppleSoft II assembly.
    /// </summary>
    /// <param name="result">An assembly from <see cref="AssembleAppleSoft(string, Apple2Model)"/>.</param>
    /// <returns>The bytes at $D000-$F7FF.</returns>
    internal static ReadOnlyMemory<byte> AppleSoftImage(AssemblyResult result) =>
        result.Sections[0].Bytes.Slice(AppleSoftOrigin, AppleSoftSize);

    private static void Place(byte[] system, AssemblyResult result)
    {
        AssemblySection section = result.Sections[0];
        section.Bytes.Span.CopyTo(system.AsSpan(section.Origin - SystemRomOrigin));
    }

    private static int Number(string text)
    {
        string value = text.Trim();
        return value.StartsWith('$')
            ? int.Parse(value.AsSpan(1), NumberStyles.HexNumber, CultureInfo.InvariantCulture)
            : int.Parse(value, CultureInfo.InvariantCulture);
    }
}
