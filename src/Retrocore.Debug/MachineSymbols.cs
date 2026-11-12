// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using System.Text.RegularExpressions;
using Retrocore.Assembler;
using Retrocore.Machines.Apple2;

namespace Retrocore.Debug;

/// <summary>
///  The names the SDK's sources give a machine's addresses: the Monitor's entry points and page-zero locations, the
///  soft switches, the firmware's, BASIC's and DOS's routines and storage, each with the file that defines it.
/// </summary>
/// <remarks>
///  <para>
///   Each source is assembled as the debugger assembles it for the model, so each name has the address it has on
///   that machine; DOS's are where it runs in 48K or more. Where several names share an address, the Monitor's and
///   the hardware equates' come first, then the firmware's, BASIC's and DOS's; within a source a label comes before
///   an equate, and an earlier definition before a later one. A routine's inner labels (<c>ROUTINE_1</c>) are left
///   out, and page zero takes only the Monitor's and the hardware's names, as programs reuse BASIC's and DOS's
///   page-zero storage for their own.
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
        string appleSoft = Path.Join(roms, "AppleSoft", "applesoft.mac");
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
        int order = 0;
        foreach (AssemblyResult build in builds)
        {
            foreach (AssemblySymbol symbol in build.SymbolDefinitions)
            {
                if (symbol.Location is not { } location || symbol.Value is < 0 or > 0xFFFF) { continue; }
                if (!Identifier().IsMatch(symbol.Name) || InnerLabel().IsMatch(symbol.Name)) { continue; }
                string file = Path.GetFileName(location.Path);
                int rank = Rank(file);

                // Programs reuse BASIC's and DOS's page-zero storage for their own, so only the Monitor's and the
                // hardware's names go there.
                if (symbol.Value < 0x100 && rank > 1) { continue; }
                candidates.Add(((ushort)symbol.Value, symbol.Name, file, rank, symbol.IsConstant, order++));
            }
        }

        Dictionary<ushort, (string, string)> names = [];
        HashSet<string> taken = new(StringComparer.Ordinal);
        foreach (var candidate in candidates
            .OrderBy(candidate => candidate.Rank)
            .ThenBy(candidate => candidate.Constant)
            .ThenBy(candidate => candidate.Order))
        {
            if (names.ContainsKey(candidate.Address) || !taken.Add(candidate.Name)) { continue; }
            names.Add(candidate.Address, (candidate.Name, candidate.File));
        }

        return names;
    }

    // Which names win at a shared address: the Monitor's, the hardware's, the firmware's, BASIC's, then DOS's.
    private static int Rank(string file) => file switch
    {
        "Monitor.asm" or "MonitorEntries.asm" => 0,
        "IIeEquates.asm" or "FirmwareEquates.asm" => 1,
        _ when file.StartsWith("Firmware", StringComparison.Ordinal) => 2,
        "m6502.asm" or "applesoft.mac" => 3,
        _ => 4
    };

    [GeneratedRegex("^[A-Za-z_][A-Za-z0-9_]*$")]
    private static partial Regex Identifier();

    // A routine's numbered inner label, such as CMDPROMPT_2.
    [GeneratedRegex("_[0-9]+$")]
    private static partial Regex InnerLabel();
}
