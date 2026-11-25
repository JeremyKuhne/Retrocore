// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Assembler;
using Retrocore.Documentation;
using Retrocore.Machines.Apple2;
using System.Text.RegularExpressions;

namespace Retrocore.Debug;

/// <summary>
///  The names the SDK's sources give a machine's addresses: the Monitor's entry points and page-zero locations, the
///  soft switches, the firmware's, BASIC's and DOS's routines and storage, each with the file that defines it.
/// </summary>
/// <remarks>
///  <para>
///   Each source is assembled as the debugger assembles it for the model, so each name has the address it has on that
///   machine; DOS's are where it runs in 48K or more. Where several names share an address, the Monitor's and the
///   hardware equates' come first, then the firmware's, BASIC's and DOS's; within a source a label comes before an
///   equate, and an earlier definition before a later one. A name in a scope keeps its qualified name, such as
///   <c>LowRes::Plot</c>, as do its inner labels (<c>Disassembler::Decode::Opcode</c>). Names that end in an underscore
///   and a number, as a routine's numbered inner labels do (<c>ROUTINE_1</c>), are left out, and so are values in the
///   sources that follow the style guide (equates named as it names values, such as <c>SCREEN_WIDTH</c>, but not in
///   such a source's Equates.asm, which holds locations). Page zero takes only the Monitor's and the hardware's names,
///   as programs reuse BASIC's and DOS's page-zero storage for their own. In page zero a name in a scope, which is the
///   name one family of routines gives a byte, comes after every other name, so a program's use of the byte takes its
///   shared name (<c>PlotMask</c>, not <c>Disassembler::FormatBits</c>).
///  </para>
/// </remarks>
internal static partial class MachineSymbols
{
    /// <summary>
    ///  Gets the names for a machine and its DOS.
    /// </summary>
    /// <param name="model">The model.</param>
    /// <param name="dos">The DOS: <c>3.3</c> (1983), <c>3.3-1980</c>, <c>3.2</c> or <c>none</c>.</param>
    /// <param name="directory">The SDK's ROM source directory; by default the copy beside the debug host.</param>
    /// <returns>For each address, its name and the file that defines it.</returns>
    /// <exception cref="ArgumentException">The DOS is not one of those.</exception>
    internal static Dictionary<ushort, (string Name, string File)> For(Apple2Model model, string dos, string? directory = null)
    {
        if (dos is not ("3.3" or "3.3-1980" or "3.2" or "none"))
        {
            throw new ArgumentException("--dos must be 3.3, 3.3-1980, 3.2 or none.");
        }

        string roms = directory ?? SdkModules.RomDirectory;
        string monitor = Path.Join(roms, "System", "Monitor.asm");
        string firmware = SdkModules.FirmwarePath(model, roms);
        string appleSoft = SdkModules.AppleSoftPath(roms);
        string integer = SdkModules.IntegerBasicPath(roms);
        string dos33 = SdkModules.DosPath("Dos33.asm", roms);
        string dos32 = SdkModules.DosPath("Dos32.asm", roms);
        int year = dos == "3.3" ? 1983 : 1980;

        List<AssemblyResult> builds = [];
        if (File.Exists(monitor))
        {
            builds.Add(SdkModules.AssembleSystem(monitor, SdkModules.MonitorOrigin, SdkModules.MonitorSize, model, autostart: true));
        }

        if (model.IsIIe() && File.Exists(firmware))
        {
            builds.Add(SdkModules.AssembleSystem(firmware, SdkModules.FirmwareOrigin, SdkModules.FirmwareSize, model));
        }

        if (model == Apple2Model.II && File.Exists(integer)) { builds.Add(SdkModules.AssembleIntegerBasic(integer)); }
        if (model != Apple2Model.II && File.Exists(appleSoft))
        {
            builds.Add(SdkModules.AssembleAppleSoft(appleSoft, model));
        }

        if (dos.StartsWith("3.3", StringComparison.Ordinal) && File.Exists(dos33))
        {
            builds.Add(SdkModules.AssembleDos(dos33, master: false, year));
        }

        if (dos == "3.2" && File.Exists(dos32)) { builds.Add(SdkModules.AssembleDos(dos32, master: false)); }

        List<(ushort Address, string Name, string File, int Rank, bool Constant, int Order)> candidates = [];
        Dictionary<string, string[]?> styled = [with(StringComparer.Ordinal)];
        int order = 0;
        foreach (AssemblyResult build in builds)
        {
            foreach (AssemblySymbol symbol in build.SymbolDefinitions)
            {
                if (symbol.Location is not { } location || symbol.Value is < 0 or > 0xFFFF) { continue; }
                if (!Identifier().IsMatch(symbol.Name) || InnerLabel().IsMatch(symbol.Name)) { continue; }

                if (symbol.IsConstant && IsValue(symbol.Name, location, styled)) { continue; }
                string file = ModuleFile(location.Path);
                int rank = Rank(file);

                // Programs reuse BASIC's and DOS's page-zero storage for their own, so only the Monitor's and the
                // hardware's names go there.
                if (symbol.Value < 0x100 && rank > 1) { continue; }
                candidates.Add(((ushort)symbol.Value, symbol.Name, file, rank, symbol.IsConstant, order++));
            }
        }

        Dictionary<ushort, (string, string)> names = [];

        HashSet<string> taken = [with(StringComparer.Ordinal)];
        foreach (var candidate in candidates
            .OrderBy(candidate => candidate.Address < 0x100 && candidate.Name.Contains("::", StringComparison.Ordinal))
            .ThenBy(candidate => candidate.Rank)
            .ThenBy(candidate => candidate.Constant)
            .ThenBy(candidate => candidate.Order))
        {
            if (names.ContainsKey(candidate.Address) || !taken.Add(candidate.Name)) { continue; }
            names.Add(candidate.Address, (candidate.Name, candidate.File));
        }

        return names;
    }

    // Whether an equate in a source that follows the style guide is a value rather than an address. There locations
    // are PascalCase, so a value is one named in capitals (SCREEN_WIDTH, COLUMNS, AddressMode::ABSOLUTE) or a .set
    // variable, in either form. Such a source's Equates.asm holds only locations, keeping Apple's capital names for
    // them until they are converted (CV, LOC1), so only its .set variables are values. Other sources name their
    // locations in capitals too, so the rule cannot tell their values from them and leaves both.
    private static bool IsValue(string name, AssemblyLocation location, Dictionary<string, string[]?> styled)
    {
        string path = location.Path;
        if (!styled.TryGetValue(path, out string[]? lines))
        {
            // The style is the first line's pragma, so only a source that has it is read in full.
            lines = File.Exists(path) && DocumentationParser.IsStrict(File.ReadLines(path).FirstOrDefault() ?? "")
                ? File.ReadAllLines(path)
                : null;

            styled[path] = lines;
        }

        if (lines is null) { return false; }
        if (location.Line < lines.Length && SetVariable().IsMatch(lines[location.Line])) { return true; }

        return Path.GetFileName(path) != "Equates.asm" && (ValueName().IsMatch(name) || CapitalName().IsMatch(name));
    }

    /// <summary>
    ///  Gets the file a definition is from, as a module: a part in a folder beside the module's main file, such as
    ///  Monitor/Screen.asm beside Monitor.asm, is from the main file, so it ranks as the module does.
    /// </summary>
    /// <param name="path">The definition's source path.</param>
    /// <returns>The module's file name.</returns>
    internal static string ModuleFile(string path)
    {
        string? folder = Path.GetDirectoryName(path);
        string? parent = folder is null ? null : Path.GetDirectoryName(folder);
        if (folder is not null && parent is not null)
        {
            string main = $"{Path.GetFileName(folder)}.asm";
            if (File.Exists(Path.Join(parent, main))) { return main; }
        }

        return Path.GetFileName(path);
    }

    /// <summary>
    ///  Orders names from several modules so that the unranked ones, a program's, come first in the order given, and
    ///  then the ranked ones, the SDK's, by <see cref="Rank(string)"/>: where they name one address, the Monitor's,
    ///  the hardware's and the firmware's come before BASIC's and DOS's.
    /// </summary>
    /// <remarks>
    ///  <para>
    ///   AppleSoft's <c>TerminalPosition</c> and the Monitor's <c>CursorColumn</c> both name $24, and
    ///   <c>CursorColumn</c> comes first; names of one rank stay in the order given. Ranks are by module file name, as <see cref="ModuleFile(string)"/> gives it, so
    ///   a name from a Monitor, firmware or BASIC source (<c>AppleSoft.*</c>, <c>MsBasic.*</c> or <c>m6502.asm</c>)
    ///   comes before one from any other source, such as PET BASIC's <c>Commodore.Equates.asm</c> or its kernal's.
    ///  </para>
    /// </remarks>
    /// <param name="names">
    ///  Each name, its value, the source that defines it (a name with none ranks with the other sources'), and whether
    ///  it is ranked, in the modules' order.
    /// </param>
    /// <returns>
    ///  The names and values, the unranked first, then the ranked by lowest <see cref="Rank(string)"/>.
    /// </returns>
    internal static IEnumerable<(string Name, long Value)> ByRank(
        IEnumerable<(string Name, long Value, string? Path, bool Ranked)> names)
    {
        Dictionary<string, int> ranks = [];
        int RankOf(string? path)
        {
            if (path is null) { return Rank(""); }
            if (!ranks.TryGetValue(path, out int rank)) { ranks[path] = rank = Rank(ModuleFile(path)); }
            return rank;
        }

        return [.. names.Select(name => (name.Name, name.Value, Rank: name.Ranked ? RankOf(name.Path) : -1))
            .OrderBy(name => name.Rank)
            .Select(name => (name.Name, name.Value))];
    }

    /// <summary>
    ///  Gets which names win at a shared address: the Monitor's, the hardware's, the firmware's, BASIC's, then DOS's
    ///  and everything else's.
    /// </summary>
    /// <param name="file">The module's file, from <see cref="ModuleFile(string)"/>.</param>
    /// <returns>The rank, lowest first.</returns>
    internal static int Rank(string file) => file switch
    {
        "Monitor.asm" or "MonitorEntries.asm" => 0,
        "IIeEquates.asm" or "FirmwareEquates.asm" => 1,
        _ when file.StartsWith("Firmware", StringComparison.Ordinal) => 2,
        "m6502.asm" or "applesoft.mac" or "AppleSoft.asm" => 3,
        _ when file.StartsWith("AppleSoft.", StringComparison.Ordinal)
            || file.StartsWith("MsBasic.", StringComparison.Ordinal) => 3,
        _ => 4
    };

    // A plain or qualified identifier, such as CharacterOut or LowRes::Plot.
    [GeneratedRegex("^[A-Za-z_][A-Za-z0-9_]*(::[A-Za-z_][A-Za-z0-9_]*)*$")]
    private static partial Regex Identifier();

    // A value's name, such as SCREEN_WIDTH: capitals and digits with an underscore between words.
    [GeneratedRegex("(^|::)[A-Z0-9]+(_[A-Z0-9]+)+$")]
    private static partial Regex ValueName();

    // A .set variable's line: .set Name, value or Name .set value.
    [GeneratedRegex(@"^\s*(\S+\s+)?\.set\b", RegexOptions.IgnoreCase)]
    private static partial Regex SetVariable();

    // A name in capitals and digits, such as COLUMNS or AddressMode::ABSOLUTE.
    [GeneratedRegex("(^|::)[A-Z][A-Z0-9]*$")]
    private static partial Regex CapitalName();

    // A routine's numbered inner label, such as CMDPROMPT_2.
    [GeneratedRegex("_[0-9]+$")]
    private static partial Regex InnerLabel();
}
