// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using System.Text;
using Retrocore.Assembler;
using Retrocore.Machines.Apple3;

namespace Retrocore.Debug;

/// <summary>
///  Maps SOS's drivers to the SDK's sources as SOS loads them: each driver's source assembled for the address and
///  bank SOS moved it to.
/// </summary>
/// <remarks>
///  <para>
///   SOS's loader relocates each driver in SOS.DRIVER into a bank of its choosing and enters its devices in the
///   device manager's system device table: where each device's DIB has its name, and its bank. A driver's code starts with its first
///   DIB, so that DIB's name says which source it is and its address where the code starts. The source is assembled
///   there and maps in that bank; as everywhere, a line applies only where memory holds its bytes.
///  </para>
/// </remarks>
internal sealed class SosDriverModules
{
    // A DIB: the link, the entry point, the device's name as a length and 15 characters, ..., the release at $1E.
    private const int DibName = 4;
    private const int DibRelease = 0x1E;

    // How many of a driver's first bytes must match memory for its source to be the one loaded.
    private const int Sample = 256;

    // Each driver's first device, and the folders of the sources that can be it under Sos/Drivers: more than one
    // when drivers share a name, as the RAM disk drivers for Titan's card do.
    private static readonly Dictionary<string, string[]> s_sources = new(StringComparer.Ordinal)
    {
        [".CONSOLE"] = ["Console"],
        [".RS232"] = ["Rs232"],
        [".PRINTER"] = ["Printer"],
        [".GRAFIX"] = ["Grafix"],
        [".AUDIO"] = ["Audio"],
        [".SILENTYPE"] = ["Silentype"],
        [".PROFILE"] = ["Profile"],
        [".FMTD1"] = ["Fmtd1"],
        [".RAM"] = ["Ram", "TitanRam"]
    };

    private readonly Apple3Bus _bus;
    private readonly string _drivers;
    private readonly ushort _maxDeviceNumber;
    private readonly ushort _dibLow;
    private readonly ushort _dibHigh;
    private readonly ushort _bank;
    private readonly ushort _version;
    private readonly byte[] _versionText;
    private readonly HashSet<(string Name, ushort Dib, byte Bank)> _mapped = [];

    /// <summary>
    ///  Prepares to map drivers for a kernel.
    /// </summary>
    /// <param name="bus">The machine's bus.</param>
    /// <param name="kernel">SOS's kernel, assembled, for the device table's addresses.</param>
    /// <param name="drivers">The <c>Sos/Drivers</c> folder.</param>
    internal SosDriverModules(Apple3Bus bus, AssemblyResult kernel, string drivers)
    {
        _bus = bus;
        _drivers = drivers;
        Dictionary<string, long> symbols = kernel.SymbolDefinitions.ToDictionary(symbol => symbol.Name, symbol => symbol.Value);
        _maxDeviceNumber = Symbol(symbols, "DEVMGR::MAX_DNUM");
        _dibLow = Symbol(symbols, "DEVMGR::SDT_DIBL");
        _dibHigh = Symbol(symbols, "DEVMGR::SDT_DIBH");
        _bank = Symbol(symbols, "DEVMGR::SDT_BANK");
        _version = Symbol(symbols, "SYSGLOB::SOSVER");
        _versionText = Encoding.ASCII.GetBytes("SOS 1.3");
    }

    /// <summary>
    ///  Adds a module for each driver SOS has loaded since the last call.
    /// </summary>
    /// <param name="debug">The session's modules.</param>
    /// <returns>Whether it added any.</returns>
    internal bool Scan(DebugInfo debug)
    {
        if (!KernelIsRunning()) { return false; }
        int devices = _bus.Peek(_maxDeviceNumber);
        bool added = false;
        for (int device = 1; device <= devices && device < 25; device++)
        {
            // The table points at each DIB's name, 4 bytes into it.
            ushort dib = (ushort)((_bus.Peek((ushort)(_dibLow + device)) | (_bus.Peek((ushort)(_dibHigh + device)) << 8)) - DibName);
            byte bank = _bus.Peek((ushort)(_bank + device));
            if (dib is < 0x2000 or > 0x9FE0) { continue; }

            string name = DeviceName(bank, dib);
            if (!s_sources.TryGetValue(name, out string[]? folders) || !_mapped.Add((name, dib, bank))) { continue; }

            int release = _bus.PeekBank(bank, (ushort)(dib + DibRelease)) | (_bus.PeekBank(bank, (ushort)(dib + DibRelease + 1)) << 8);
            foreach (string folder in folders)
            {
                string root = Path.Join(_drivers, folder, folder + ".asm");
                if (!File.Exists(root) || Assemble(root, folder, dib, release) is not { } driver) { continue; }
                if (folders.Length > 1 && !Matches(driver, bank, dib)) { continue; }

                debug.Add(new SourceMapModule(driver, _bus.BankArea(bank)));
                added = true;
                break;
            }
        }

        return added;
    }

    // Whether memory holds the driver's first bytes, after its comment record when it has one. SOS sets some of a
    // DIB's fields as it chains and starts devices, so nine in ten matching is enough.
    private bool Matches(AssemblyResult driver, byte bank, ushort dib)
    {
        ReadOnlySpan<byte> bytes = driver.Sections[0].Bytes.Span;
        int start = bytes[0] == 0xFF && bytes[1] == 0xFF ? 4 + (bytes[2] | (bytes[3] << 8)) : 0;
        int count = Math.Min(Sample, Math.Min(bytes.Length - start, 0xA000 - dib));
        int same = 0;
        for (int index = 0; index < count; index++)
        {
            if (_bus.PeekBank(bank, (ushort)(dib + index)) == bytes[start + index]) { same++; }
        }

        return same * 10 >= count * 9;
    }

    // SOS 1.3's kernel is in place once SYSGLOB's version text is.
    private bool KernelIsRunning()
    {
        for (int index = 0; index < _versionText.Length; index++)
        {
            if (_bus.Peek((ushort)(_version + index)) != _versionText[index]) { return false; }
        }

        return true;
    }

    private string DeviceName(byte bank, ushort dib)
    {
        int length = _bus.PeekBank(bank, (ushort)(dib + DibName)) & 0x0F;
        Span<char> name = stackalloc char[length];
        for (int index = 0; index < length; index++)
        {
            name[index] = (char)(_bus.PeekBank(bank, (ushort)(dib + DibName + 1 + index)) & 0x7F);
        }

        return new string(name);
    }

    // The driver's source assembled with its code at the DIB's address; the console's 1.30 is a build of its own.
    private static AssemblyResult? Assemble(string root, string folder, ushort origin, int release)
    {
        string text = File.ReadAllText(root);
        string path = root;
        if (folder == "Console" && release == 0x1300)
        {
            path = Path.Join(Path.GetDirectoryName(root), "_Console130.asm");
            text = $"RELEASE_130 = 1\n.include \"{Path.GetFileName(root)}\"\n";
        }

        AssemblyOptions options = new("Mos6502", origin, 0x10000 - origin)
        {
            SourceResolver = new FileAssemblySourceResolver()
        };

        AssemblyResult result = new Assembler.Assembler().Assemble(new AssemblySource(text, path), options);
        return result.Success ? result : null;
    }

    private static ushort Symbol(Dictionary<string, long> symbols, string name) =>
        symbols.TryGetValue(name, out long value)
            ? checked((ushort)value)
            : throw new InvalidDataException($"SOS's kernel source has no {name}.");
}
