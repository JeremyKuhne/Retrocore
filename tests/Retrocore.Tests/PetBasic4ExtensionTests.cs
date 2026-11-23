// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using System.Text;
using Retrocore.Assembler;
using Retrocore.Debug;
using Retrocore.Documentation;
using Retrocore.Machines.Commodore;

namespace Retrocore.Tests;

/// <summary>
///  Checks the native BASIC 4 monitor and disk-command extension against both MACRO-10 builds.
/// </summary>
[TestClass]
public sealed class PetBasic4ExtensionTests
{
    private const ushort ReturnAddress = 0x5000;
    private const int InputCounter = 0x0700;
    private const int InputBytes = 0x0710;
    private static string PetInputs => Path.Join(BasicNames.Inputs, "Pet");
    private static string BasicInputs => Path.Join(PetInputs, "Basic");

    private static readonly string[] s_files =
    [
        "Commodore.Basic4Extension.asm",
        "Commodore.Basic4SystemEquates.asm",
        "Commodore.Basic4Monitor.asm",
        "Commodore.Basic4Record.asm",
        "Commodore.Basic4DiskCommands.asm",
        "Commodore.Basic4DiskParser.asm",
        "Commodore.Basic4RomEnd.asm"
    ];

    /// <summary>
    ///  Both BASIC 4 revisions retain the complete extension, including every legacy label and the ROM padding.
    /// </summary>
    /// <param name="original">Whether to assemble the original $B000 chip.</param>
    [TestMethod]
    [DataRow(data: false)]
    [DataRow(data: true)]
    public void ExtensionMatchesLegacyBytesLabelsAndEmittedSpan(bool original)
    {
        AssemblyResult legacy = Legacy(original);
        AssemblyResult native = AssembleExtension(legacy, original ? 0 : 1);
        int start = checked((int)legacy.Symbol("CALLE"));
        const int end = 0xE000;

        start.Should().Be(0xD472);
        native.Symbol("LASTWR").Should().Be(start);
        native.Symbol("EXTENSION_END").Should().Be(end);
        AssertEmittedSpan(legacy, start, end, exact: false);
        AssertEmittedSpan(native, start, end, exact: true);
        ReadOnlySpan<byte> expected = legacy.Sections[0].Bytes.Span.Slice(start, end - start);
        ReadOnlySpan<byte> actual = native.Sections[0].Bytes.Span.Slice(start, end - start);
        int firstDifference = actual.CommonPrefixLength(expected);
        firstDifference.Should().Be(expected.Length, $"the first different byte is at ${start + firstDifference:X4}");

        AssemblySymbol[] labels = legacy.SymbolDefinitions
            .Where(symbol => !symbol.IsConstant && symbol.Value >= start && symbol.Value < end)
            .ToArray();

        labels.Should().NotBeEmpty();
        foreach (AssemblySymbol label in labels)
        {
            AssemblySymbol nativeLabel = native.FindDefinition(label.Name)
                ?? throw new AssertFailedException($"The native module does not define legacy label {label.Name}.");

            nativeLabel.Value.Should().Be(label.Value, $"{label.Name} must retain its ROM address");
            AssemblyLocation location = nativeLabel.Location
                ?? throw new AssertFailedException($"{label.Name} needs a physical definition.");

            location.Path.Should().NotBe("<predefined>", $"{label.Name} belongs to the extension");
        }

        foreach (AssemblySymbol definition in native.SymbolDefinitions.Where(symbol =>
            symbol.IsConstant
                && symbol.Location is { } location
                && (Path.GetFileName(location.Path).Equals("Commodore.Basic4SystemEquates.asm", StringComparison.OrdinalIgnoreCase)
                    || Path.GetFileName(location.Path).Equals("Commodore.Basic4DiskCommands.asm", StringComparison.OrdinalIgnoreCase))))
        {
            legacy.TryGetCounterpart(native, definition.Name, out long overlay).Should().BeTrue(
                $"{definition.Name} must be in the overlay by its name or a historical name");

            definition.Value.Should().Be(overlay, $"{definition.Name} must match the overlay");
        }
    }

    /// <summary>
    ///  The extension composes immediately after the existing BASIC 4 initialization and messages.
    /// </summary>
    /// <param name="original">Whether BASIC uses the original chip.</param>
    [TestMethod]
    [DataRow(data: false)]
    [DataRow(data: true)]
    public void InitializationAndExtensionComposeInRomOrder(bool original)
    {
        AssemblyResult legacy = Legacy(original);
        Dictionary<string, long> symbols = Dependencies(legacy);
        foreach (string name in (string[])["FCERR", "INITAT", "ROMLOC", "STROUT", "SCRTCH"])
        {
            symbols.Add(name, legacy.Symbol(name));
        }

        string source = $"""
            .cpu Mos6502
            .include "Commodore.Platform.asm"
            .include "Commodore.Basic4Extension.asm"
            .org ${legacy.Symbol("INIT"):X4}
                COMMODORE_INITIALIZE 0, 0, 0, 0, 2, 1, 0
                COMMODORE_MEMORY_PROBE 0, 0, 1, 1, 0, $55
                COMMODORE_START_PROGRAM 0, 0, 0, 0, SIGNON
                COMMODORE_START_MESSAGES 0
            LASTWR:
                COMMODORE_BASIC4_EXTENSION {(original ? 0 : 1)}
            COMPOSED_END:
            """;

        AssemblyResult native = Assemble(source, symbols);
        int start = checked((int)legacy.Symbol("INIT"));
        const int end = 0xE000;
        native.Symbol("LASTWR").Should().Be(legacy.Symbol("CALLE"));
        native.Symbol("COMPOSED_END").Should().Be(end);
        AssertEmittedSpan(legacy, start, end, exact: false);
        AssertEmittedSpan(native, start, end, exact: true);
        ReadOnlySpan<byte> expected = legacy.Sections[0].Bytes.Span.Slice(start, end - start);
        ReadOnlySpan<byte> actual = native.Sections[0].Bytes.Span.Slice(start, end - start);
        int firstDifference = actual.CommonPrefixLength(expected);
        firstDifference.Should().Be(expected.Length, $"the first different byte is at ${start + firstDifference:X4}");
        foreach (AssemblySymbol label in legacy.SymbolDefinitions.Where(
            symbol => !symbol.IsConstant && symbol.Value >= start && symbol.Value < end))
        {
            native.SymbolsWithHistoricalNames.Should().ContainKey(label.Name);
            native.Symbol(label.Name).Should().Be(label.Value, $"{label.Name} must retain its ROM address");
        }
    }

    /// <summary>
    ///  The extension's routines and platform definitions have valid native documentation.
    /// </summary>
    /// <param name="original">Whether to assemble the original $B000 chip.</param>
    [TestMethod]
    [DataRow(data: false)]
    [DataRow(data: true)]
    public void ExtensionDocumentationResolvesForEachRevision(bool original)
    {
        AssemblyResult native = AssembleExtension(Legacy(original), original ? 0 : 1);
        DocumentationSet docs = DocumentationSet.Create(
            s_files.Select(file => Path.Join(BasicInputs, file))
                .Select(path => DocumentationParser.Parse(File.ReadAllText(path), path)), native);

        foreach (string name in (string[])
            [
                "CALLE", "BRKE", "MGO", "RECORD", "CATLOG", "DOPEN", "APPEND", "ERRCHL", "GETDS",
                "FORMAT", "DCLOSE", "BOBREC", "COLECT", "BACKUP", "DCOPY", "CONCAT", "DSAVE", "DLOAD",
                "RENAME", "DSCRTC", "RUSURE", "OLDCLR", "SENDP", "DOSPAR", "UNIT", "NEWNAM", "DSLINK", "SIGNON"
            ])
        {
            docs.Find(name).Should().NotBeNull($"{name} must be documented");
        }

        List<DocumentationDiagnostic> diagnostics = new DocumentationResolver(docs).Check();
        diagnostics.Should().BeEmpty(string.Join(Environment.NewLine, diagnostics.Select(diagnostic =>
            $"{Path.GetFileName(diagnostic.Path)}:{diagnostic.Line + 1}: {diagnostic.Message}")));
    }

    /// <summary>
    ///  A revision selector outside the supported original and revised chips is rejected.
    /// </summary>
    [TestMethod]
    public void InvalidRevisionIsRejected()
    {
        AssemblyResult result = BuildExtension(Legacy(original: false), 2);
        result.Success.Should().BeFalse();
        result.Diagnostics.Select(diagnostic => diagnostic.Message).Should()
            .Contain(message => message.Contains("revised is 0 or 1"));
    }

    /// <summary>
    ///  Opening the definitions alone supplies the BASIC 4 workspace without emitting ROM bytes.
    /// </summary>
    [TestMethod]
    public void StandaloneExtensionSuppliesTheBasic4Workspace()
    {
        string source = """
            .cpu Mos6502
            .include "Commodore.Basic4Extension.asm"
            """;

        AssemblyResult native = Assemble(source, new Dictionary<string, long>());
        AssemblyResult legacy = Legacy(original: false);
        foreach (string name in (string[])["TXTPTR", "CHRGOT", "CQSTAT", "DSDESC"])
        {
            native.Symbol(name).Should().Be(legacy.Symbol(name));
        }

        native.SourceMap.Where(entry => entry.Size > 0).Should().BeEmpty();
    }

    /// <summary>
    ///  The extension cannot be emitted at a different address or with a non-BASIC-4 workspace.
    /// </summary>
    [TestMethod]
    public void WrongAddressAndWorkspaceAreRejected()
    {
        AssemblyResult legacy = Legacy(original: false);
        AssemblyResult displaced = BuildExtension(legacy, revised: 1, origin: 0xD473);
        displaced.Success.Should().BeFalse();
        displaced.Diagnostics.Select(diagnostic => diagnostic.Message).Should()
            .Contain(message => message.Contains("extension must begin at $D472"));

        string source = """
            .cpu Mos6502
            .include "Commodore.Equates.asm"
            .include "Commodore.Basic4Extension.asm"
            """;

        AssemblyResult wrongWorkspace = new Assembler.Assembler().Assemble(
            new AssemblySource(source, Path.Join(BasicInputs, "Basic4WrongWorkspaceTest.asm")),
            new AssemblyOptions(ProcessorVariant.Mos6502, 0, 0x10000)
            {
                SourceResolver = new FileAssemblySourceResolver()
            });

        wrongWorkspace.Success.Should().BeFalse();
        wrongWorkspace.Diagnostics.Select(diagnostic => diagnostic.Message).Should()
            .Contain(message => message.Contains("disk-status workspace"));
    }

    /// <summary>
    ///  Later BASIC 4's terminal and scratch placement cannot be replaced by an early-ROM layout.
    /// </summary>
    /// <param name="setting">The incompatible workspace switch.</param>
    [TestMethod]
    [DataRow("TERMINAL_FIRST")]
    [DataRow("NULCMD")]
    [DataRow("LOCAL_TRMPOS")]
    public void EarlyTerminalPlacementIsRejected(string setting)
    {
        Dictionary<string, long> symbols = Dependencies(Legacy(original: false));
        symbols.Add(setting, 1);
        string source = """
            .cpu Mos6502
            .include "Commodore.Equates.asm"
            .include "Commodore.Basic4Extension.asm"
            """;

        AssemblyResult result = new Assembler.Assembler().Assemble(
            new AssemblySource(source, Path.Join(BasicInputs, "Basic4WrongTerminalTest.asm")),
            new AssemblyOptions(ProcessorVariant.Mos6502, 0, 0x10000)
            {
                SourceResolver = new FileAssemblySourceResolver(),
                PredefinedSymbols = BasicNames.WithCurrentNames(symbols)
            });

        result.Success.Should().BeFalse();
        result.Diagnostics.Select(diagnostic => diagnostic.Message).Should()
            .Contain(message => message.Contains("later terminal and scratch workspace"));
    }

    /// <summary>
    ///  The disk parser accepts valid drive and unit parameters and rejects duplicates and out-of-range values.
    /// </summary>
    /// <param name="text">Tokenized parameter bytes, in hexadecimal.</param>
    /// <param name="flags">The expected parser flags on success.</param>
    /// <param name="drive1">The first drive on success.</param>
    /// <param name="drive2">The second drive on success.</param>
    /// <param name="device">The primary device on success.</param>
    /// <param name="destination">The return or error entry.</param>
    [TestMethod]
    [DataRow("", 0x00, 0, 0, 8, "RETURN")]
    [DataRow("4431", 0x10, 1, 1, 8, "RETURN")]
    [DataRow("4431A44430", 0x30, 1, 0, 8, "RETURN")]
    [DataRow("5533", 0x08, 0, 0, 3, "RETURN")]
    [DataRow("4432", 0, 0, 0, 0, "ERROR")]
    [DataRow("5532", 0, 0, 0, 0, "ERROR")]
    [DataRow("44312C4430", 0, 0, 0, 0, "SNERR")]
    public void DiskParserValidatesDriveAndUnitParameters(
        string text,
        int flags,
        int drive1,
        int drive2,
        int device,
        string destination)
    {
        foreach (bool original in new[] { false, true })
        {
            AssemblyResult legacy = Legacy(original);
            AssemblyResult native = AssembleExtension(legacy, original ? 0 : 1);
            foreach (bool useNative in new[] { false, true })
            {
                RecordingBus bus = new();
                legacy.Sections[0].Bytes.Span.CopyTo(bus.Memory);
                if (useNative)
                {
                    int start = checked((int)native.Symbol("CALLE"));
                    native.Sections[0].Bytes.Span.Slice(start, 0xE000 - start).CopyTo(bus.Memory.AsSpan(start));
                }

                InstallCharacterReader(bus, native, legacy);
                int reader = checked((int)native.Symbol("CHRGET"));
                int textPointer = checked((int)native.Symbol("TXTPTR"));
                bus.Memory[textPointer] = 0x00;
                bus.Memory[textPointer + 1] = 0x06;
                Convert.FromHexString(text).CopyTo(bus.Memory, 0x0600);

                // This stub evaluates one decimal digit, advancing the real character reader afterwards.
                byte[] getByte =
                [
                    0xA0, 0x00, 0xB1, (byte)textPointer, 0x38, 0xE9, 0x30, 0xAA,
                    0x20, (byte)reader, (byte)(reader >> 8), 0x60
                ];

                getByte.CopyTo(bus.Memory, checked((int)native.Symbol("GETBYT")));
                Processor<RecordingBus> cpu = Start(bus, native, "DOSPAR");
                ushort finish = destination == "RETURN" ? ReturnAddress : checked((ushort)native.Symbol(destination));
                RunUntil(cpu, finish, 600);
                if (destination == "RETURN")
                {
                    cpu.Registers.Accumulator.Should().Be((byte)flags);
                    bus.Memory[checked((int)native.Symbol("PRSCHK"))].Should().Be((byte)flags);
                    bus.Memory[checked((int)native.Symbol("DRIVE1"))].Should().Be((byte)drive1);
                    bus.Memory[checked((int)native.Symbol("DRIVE2"))].Should().Be((byte)drive2);
                    bus.Memory[checked((int)native.Symbol("FA"))].Should().Be((byte)device);
                }
                else if (destination == "ERROR")
                {
                    cpu.Registers.X.Should().Be((byte)native.Symbol("ERRFC"));
                }
            }
        }
    }

    /// <summary>
    ///  RECORD accepts an optional position from 1 through 254 and rejects invalid quantities and trailing text.
    /// </summary>
    /// <param name="text">The RECORD parameters.</param>
    /// <param name="position">The record position on success.</param>
    /// <param name="destination">The disk entry or error reached.</param>
    [TestMethod]
    [DataRow("#1,5", 1, "BOBREC")]
    [DataRow("#1,5,1", 1, "BOBREC")]
    [DataRow("#1,(5),254", 254, "BOBREC")]
    [DataRow("#1,5,0", 0, "ERROR")]
    [DataRow("#1,5,255", 0, "ERROR")]
    [DataRow("#0,5", 0, "ERROR")]
    [DataRow("#1,5,1,1", 0, "SNERR")]
    public void RecordParsesAndValidatesItsPosition(string text, int position, string destination)
    {
        foreach (bool original in new[] { false, true })
        {
            AssemblyResult legacy = Legacy(original);
            AssemblyResult native = AssembleExtension(legacy, original ? 0 : 1);
            foreach (bool useNative in new[] { false, true })
            {
                RecordingBus bus = new();
                legacy.Sections[0].Bytes.Span.CopyTo(bus.Memory);
                if (useNative)
                {
                    int start = checked((int)native.Symbol("CALLE"));
                    native.Sections[0].Bytes.Span.Slice(start, 0xE000 - start).CopyTo(bus.Memory.AsSpan(start));
                }

                InstallCharacterReader(bus, native, legacy);
                int textPointer = checked((int)native.Symbol("TXTPTR"));
                bus.Memory[textPointer] = 0x00;
                bus.Memory[textPointer + 1] = 0x06;
                Encoding.ASCII.GetBytes(text + "\0").CopyTo(bus.Memory, 0x0600);
                Processor<RecordingBus> cpu = Start(bus, native, "RECORD");
                RunUntil(cpu, checked((ushort)native.Symbol(destination)), 10_000);
                if (destination == "BOBREC")
                {
                    bus.Memory[checked((int)native.Symbol("LA"))].Should().Be(1);
                    bus.Memory[checked((int)native.Symbol("RECPOS"))].Should().Be((byte)position);
                    int record = checked((int)native.Symbol("POKER"));
                    (bus.Memory[record] | (bus.Memory[record + 1] << 8)).Should().Be(5);
                }
                else if (destination == "ERROR")
                {
                    cpu.Registers.X.Should().Be((byte)native.Symbol("ERRFC"));
                }
            }
        }
    }

    /// <summary>
    ///  Disk filenames allow 16 characters, plus an optional replacement prefix, and reject duplicates.
    /// </summary>
    /// <param name="length">The evaluated string length.</param>
    /// <param name="replacement">Whether the first character is @.</param>
    /// <param name="duplicate">Whether this filename position is already occupied.</param>
    /// <param name="priorFlags">The existing parser flags.</param>
    /// <param name="destination">The return or error entry.</param>
    /// <param name="errorName">The expected BASIC error offset, when applicable.</param>
    [TestMethod]
    [DataRow(0, false, false, 0, "ERROR", "ERRFC")]
    [DataRow(16, false, false, 0, "RETURN", "")]
    [DataRow(17, false, false, 0, "ERROR", "ERRLS")]
    [DataRow(17, true, false, 0, "RETURN", "")]
    [DataRow(18, true, false, 0, "ERROR", "ERRLS")]
    [DataRow(1, false, true, 0, "SNERR", "")]
    [DataRow(1, true, false, 0x80, "SNERR", "")]
    public void FilenameParserEnforcesLengthReplacementAndDuplicateRules(
        int length,
        bool replacement,
        bool duplicate,
        int priorFlags,
        string destination,
        string errorName)
    {
        AssemblyResult legacy = Legacy(original: false);
        AssemblyResult native = AssembleExtension(legacy, revised: 1);
        foreach (bool useNative in new[] { false, true })
        {
            RecordingBus bus = new();
            legacy.Sections[0].Bytes.Span.CopyTo(bus.Memory);
            if (useNative)
            {
                int start = checked((int)native.Symbol("CALLE"));
                native.Sections[0].Bytes.Span.Slice(start, 0xE000 - start).CopyTo(bus.Memory.AsSpan(start));
            }

            bus.Memory[checked((int)native.Symbol("FRMEVL"))] = 0x60;
            int index = checked((int)native.Symbol("INDEX1"));
            byte[] fetch =
            [
                0xA9, 0x00, 0x85, (byte)index,
                0xA9, 0x06, 0x85, (byte)(index + 1),
                0xA9, (byte)length, 0x60
            ];

            fetch.CopyTo(bus.Memory, checked((int)native.Symbol("FRESTR")));
            bus.Memory[0x0600] = replacement ? (byte)'@' : (byte)'A';
            int flags = checked((int)native.Symbol("PRSCHK"));
            bus.Memory[flags] = (byte)priorFlags;
            StatusRegister status = StatusRegister.Unused | (duplicate ? 0 : StatusRegister.Zero);
            Processor<RecordingBus> cpu = Start(bus, native, "NEWNAM", status: status);
            ushort finish = destination == "RETURN" ? ReturnAddress : checked((ushort)native.Symbol(destination));
            RunUntil(cpu, finish, 60);
            if (destination == "RETURN")
            {
                cpu.Registers.Accumulator.Should().Be((byte)length);
                cpu.Registers.X.Should().Be(0);
                cpu.Registers.Y.Should().Be(6);
                bus.Memory[flags].Should().Be(replacement ? (byte)0x80 : (byte)priorFlags);
            }
            else if (destination == "ERROR")
            {
                cpu.Registers.X.Should().Be((byte)native.Symbol(errorName));
            }
        }
    }

    /// <summary>
    ///  Template substitutions construct sequential and relative DOPEN filenames.
    /// </summary>
    /// <param name="recordLength">Zero for sequential output, otherwise a relative-record length.</param>
    /// <param name="expected">The constructed filename, in hexadecimal.</param>
    [TestMethod]
    [DataRow(0, "313A41422C572C53")]
    [DataRow(40, "313A41422C4C2C28")]
    public void DiskTemplateBuildsSequentialAndRelativeNames(int recordLength, string expected)
    {
        AssemblyResult native = AssembleExtension(Legacy(original: false), revised: 1);
        RecordingBus bus = NativeBus(native);
        int filename = checked((int)native.Symbol("FNADR"));
        bus.Memory[filename] = 0x00;
        bus.Memory[filename + 1] = 0x06;
        bus.Memory[0x0600] = (byte)'A';
        bus.Memory[0x0601] = (byte)'B';
        bus.Memory[checked((int)native.Symbol("FNLEN"))] = 2;
        bus.Memory[checked((int)native.Symbol("DRIVE1"))] = 1;
        bus.Memory[checked((int)native.Symbol("LRECL"))] = (byte)recordLength;
        bus.Memory[checked((int)native.Symbol("SATUS"))] = 0x55;
        Processor<RecordingBus> cpu = Start(bus, native, "SENDP", accumulator: 7, y: 2);
        RunUntil(cpu, ReturnAddress, 250);
        int buffer = checked((int)native.Symbol("TBUFF"));
        byte[] expectedBytes = Convert.FromHexString(expected);
        bus.Memory.AsSpan(buffer, expectedBytes.Length).ToArray().Should().Equal(expectedBytes);
        bus.Memory[checked((int)native.Symbol("FNLEN"))].Should().Be((byte)expectedBytes.Length);
        (bus.Memory[filename] | (bus.Memory[filename + 1] << 8)).Should().Be(buffer);
        bus.Memory[checked((int)native.Symbol("SATUS"))].Should().Be(0);
    }

    /// <summary>
    ///  Reading and invalidating DS$ preserves the linked allocator's metadata.
    /// </summary>
    /// <param name="original">Whether BASIC uses the original chip.</param>
    [TestMethod]
    [DataRow(data: false)]
    [DataRow(data: true)]
    public void DiskStatusAllocationAndInvalidationMaintainTheBacklink(bool original)
    {
        AssemblyResult native = AssembleExtension(Legacy(original), original ? 0 : 1);
        RecordingBus bus = NativeBus(native);
        byte[] allocation = [0xA2, 0x00, 0xA0, 0x40, 0x60];
        allocation.CopyTo(bus.Memory, checked((int)native.Symbol("GETSPA")));
        foreach (string entry in (string[])["TALK", "SECND", "UNTLK"])
        {
            bus.Memory[checked((int)native.Symbol(entry))] = 0x60;
        }

        const string response = "00, OK,00,00\r";
        InstallInput(bus, checked((int)native.Symbol("ACPTR")), response);
        int descriptor = checked((int)native.Symbol("DSDESC"));
        int status = checked((int)native.Symbol("SATUS"));
        int device = checked((int)native.Symbol("FA"));
        bus.Memory[status] = 0x55;
        Processor<RecordingBus> cpu = Start(bus, native, "ERRCHL");
        RunUntil(cpu, ReturnAddress, 600);
        bus.Memory[descriptor].Should().Be(40);
        bus.Memory[descriptor + 1].Should().Be(0);
        bus.Memory[descriptor + 2].Should().Be(0x40);
        bus.Memory[device].Should().Be(8);
        bus.Memory[status].Should().Be(0);
        byte[] expected = Encoding.ASCII.GetBytes(response[..^1] + "\0");
        bus.Memory.AsSpan(0x4000, expected.Length).ToArray().Should().Equal(expected);
        bus.Memory[0x4000 + 40].Should().Be((byte)descriptor);
        bus.Memory[0x4000 + 41].Should().Be(0);

        bus.Memory[status] = 0xFF;
        cpu = Start(bus, native, "OLDCLR", y: 0x57);
        RunUntil(cpu, ReturnAddress, 60);
        bus.Memory[descriptor].Should().Be(0);
        bus.Memory[status].Should().Be(0);
        bus.Memory[0x4000 + 40].Should().Be(40);
        bus.Memory[0x4000 + 41].Should().Be(0xFF);
        cpu.Registers.Y.Should().Be(0x57);
    }

    /// <summary>
    ///  Invalidating an empty disk status preserves the stale pointer and Y without touching its old storage.
    /// </summary>
    [TestMethod]
    public void EmptyDiskStatusInvalidationDoesNotTouchTheStalePointer()
    {
        AssemblyResult native = AssembleExtension(Legacy(original: false), revised: 1);
        RecordingBus bus = NativeBus(native);
        int descriptor = checked((int)native.Symbol("DSDESC"));
        int status = checked((int)native.Symbol("SATUS"));
        bus.Memory[descriptor] = 0;
        bus.Memory[descriptor + 1] = 0x34;
        bus.Memory[descriptor + 2] = 0x12;
        bus.Memory[0x1234 + 40] = 0xAA;
        bus.Memory[0x1234 + 41] = 0x55;
        bus.Memory[status] = 0xFF;
        Processor<RecordingBus> cpu = Start(bus, native, "OLDCLR", y: 0x57);
        RunUntil(cpu, ReturnAddress, 60);
        bus.Memory[status].Should().Be(0);
        bus.Memory[descriptor].Should().Be(0);
        bus.Memory[descriptor + 1].Should().Be(0x34);
        bus.Memory[descriptor + 2].Should().Be(0x12);
        bus.Memory[0x1234 + 40].Should().Be(0xAA);
        bus.Memory[0x1234 + 41].Should().Be(0x55);
        cpu.Registers.Y.Should().Be(0x57);
    }

    /// <summary>
    ///  Direct-mode destructive disk commands require Y or YES; running programs do not prompt.
    /// </summary>
    /// <param name="direct">Whether the command came from the direct-mode buffer.</param>
    /// <param name="answer">The supplied confirmation line.</param>
    /// <param name="rejected">Whether the carry reports rejection.</param>
    /// <param name="consumed">The number of characters read.</param>
    [TestMethod]
    [DataRow(false, "", false, 0)]
    [DataRow(true, "Y\r", false, 2)]
    [DataRow(true, "YES\r", false, 4)]
    [DataRow(true, "N\r", true, 2)]
    [DataRow(true, "YESX\r", true, 5)]
    [DataRow(true, "y\r", true, 2)]
    [DataRow(true, "N\0", false, 2)]
    public void ConfirmationDistinguishesDirectModeAndExactAnswers(bool direct, string answer, bool rejected, int consumed)
    {
        AssemblyResult native = AssembleExtension(Legacy(original: false), revised: 1);
        RecordingBus bus = NativeBus(native);
        InstallInput(bus, checked((int)native.Symbol("BASIN")), answer);
        bus.Memory[checked((int)native.Symbol("MSG"))] = 0x60;
        bus.Memory[checked((int)native.Symbol("CLRCH"))] = 0x60;
        bus.Memory[checked((int)native.Symbol("TXTPTR")) + 1] = direct ? (byte)2 : (byte)4;
        Processor<RecordingBus> cpu = Start(bus, native, "RUSURE", status: StatusRegister.Unused | StatusRegister.Carry);
        RunUntil(cpu, ReturnAddress, 150);
        cpu.Registers.Status.HasFlag(StatusRegister.Carry).Should().Be(rejected);
        bus.Memory[InputCounter].Should().Be((byte)consumed);
    }

    /// <summary>
    ///  The secondary-address search skips entries already used by open files.
    /// </summary>
    /// <param name="used">Used secondary addresses, in hexadecimal.</param>
    /// <param name="expected">The first unused address.</param>
    [TestMethod]
    [DataRow("", 0x62)]
    [DataRow("646262", 0x63)]
    [DataRow("626364", 0x65)]
    public void OpenChoosesTheFirstUnusedSecondaryAddress(string used, int expected)
    {
        AssemblyResult native = AssembleExtension(Legacy(original: false), revised: 1);
        RecordingBus bus = NativeBus(native);
        byte[] entries = Convert.FromHexString(used);
        entries.CopyTo(bus.Memory, checked((int)native.Symbol("SAT")));
        bus.Memory[checked((int)native.Symbol("LDTND"))] = (byte)entries.Length;
        Processor<RecordingBus> cpu = Start(bus, native, "ENTRY0");
        RunUntil(cpu, ReturnAddress, 100);
        bus.Memory[checked((int)native.Symbol("SA"))].Should().Be((byte)expected);
        cpu.Registers.Y.Should().Be((byte)expected);
    }

    /// <summary>
    ///  A BRK entry saves the machine state and corrects a PC crossing a page boundary.
    /// </summary>
    [TestMethod]
    public void MonitorBreakSavesRegistersAndCorrectsTheProgramCounter()
    {
        AssemblyResult native = AssembleExtension(Legacy(original: false), revised: 1);
        RecordingBus bus = NativeBus(native);
        bus.Memory[checked((int)native.Symbol("CLRCH"))] = 0x60;
        int vector = checked((int)native.Symbol("CINV"));
        bus.Memory[vector] = 0x34;
        bus.Memory[vector + 1] = 0x12;
        byte[] stack = [0x66, 0x55, 0x44, 0xB5, 0x00, 0x40];
        stack.CopyTo(bus.Memory, 0x01FA);
        Processor<RecordingBus> cpu = new(bus)
        {
            Registers = new()
            {
                ProgramCounter = checked((ushort)native.Symbol("BRKE")),
                StackPointer = 0xF9,
                Status = StatusRegister.Unused | StatusRegister.DecimalMode | StatusRegister.IRQBDisable
            }
        };

        RunUntil(cpu, checked((ushort)native.Symbol("B5")), 60);
        bus.Memory[checked((int)native.Symbol("PCL"))].Should().Be(0xFF);
        bus.Memory[checked((int)native.Symbol("PCH"))].Should().Be(0x3F);
        bus.Memory[checked((int)native.Symbol("FLGS"))].Should().Be(0xB5);
        bus.Memory[checked((int)native.Symbol("ACC"))].Should().Be(0x44);
        bus.Memory[checked((int)native.Symbol("XR"))].Should().Be(0x55);
        bus.Memory[checked((int)native.Symbol("YR"))].Should().Be(0x66);
        bus.Memory[checked((int)native.Symbol("SP"))].Should().Be(0xFF);
        bus.Memory[checked((int)native.Symbol("INVL"))].Should().Be(0x34);
        bus.Memory[checked((int)native.Symbol("INVH"))].Should().Be(0x12);
        cpu.Registers.Status.HasFlag(StatusRegister.DecimalMode).Should().BeFalse();
        cpu.Registers.Status.HasFlag(StatusRegister.IRQBDisable).Should().BeFalse();
    }

    /// <summary>
    ///  The monitor selects the saved status and register bytes for display or editing.
    /// </summary>
    [TestMethod]
    public void MonitorRegisterSelectionReturnsTheSavedStatusBlock()
    {
        AssemblyResult native = AssembleExtension(Legacy(original: false), revised: 1);
        RecordingBus bus = NativeBus(native);
        Processor<RecordingBus> cpu = Start(bus, native, "SETR");
        RunUntil(cpu, ReturnAddress, 30);
        int pointer = checked((int)native.Symbol("TMP0"));
        int selected = bus.Memory[pointer] | (bus.Memory[pointer + 1] << 8);
        selected.Should().Be(checked((int)native.Symbol("FLGS")));
        cpu.Registers.Accumulator.Should().Be(5);
    }

    /// <summary>
    ///  Monitor G restores the saved IRQ vector, stack, registers and status before resuming.
    /// </summary>
    [TestMethod]
    public void MonitorGoRestoresTheSavedMachineState()
    {
        AssemblyResult native = AssembleExtension(Legacy(original: false), revised: 1);
        RecordingBus bus = NativeBus(native);
        int basin = checked((int)native.Symbol("BASIN"));
        byte[] carriageReturn = [0xA9, 0x0D, 0x60];
        carriageReturn.CopyTo(bus.Memory, basin);
        bus.Memory[checked((int)native.Symbol("SP"))] = 0xE8;
        bus.Memory[checked((int)native.Symbol("PCH"))] = 0x42;
        bus.Memory[checked((int)native.Symbol("PCL"))] = 0x11;
        bus.Memory[checked((int)native.Symbol("FLGS"))] = 0xE9;
        bus.Memory[checked((int)native.Symbol("ACC"))] = 0x44;
        bus.Memory[checked((int)native.Symbol("XR"))] = 0x55;
        bus.Memory[checked((int)native.Symbol("YR"))] = 0x66;
        bus.Memory[checked((int)native.Symbol("INVL"))] = 0xBC;
        bus.Memory[checked((int)native.Symbol("INVH"))] = 0x9A;
        Processor<RecordingBus> cpu = Start(bus, native, "MGO");
        RunUntil(cpu, 0x4211, 60);
        cpu.Registers.StackPointer.Should().Be(0xE8);
        cpu.Registers.Accumulator.Should().Be(0x44);
        cpu.Registers.X.Should().Be(0x55);
        cpu.Registers.Y.Should().Be(0x66);
        cpu.Registers.Status.HasFlag(StatusRegister.Carry).Should().BeTrue();
        cpu.Registers.Status.HasFlag(StatusRegister.DecimalMode).Should().BeTrue();
        cpu.Registers.Status.HasFlag(StatusRegister.Overflow).Should().BeTrue();
        cpu.Registers.Status.HasFlag(StatusRegister.Negative).Should().BeTrue();
        cpu.Registers.Status.HasFlag(StatusRegister.IRQBDisable).Should().BeFalse();
        int vector = checked((int)native.Symbol("CINV"));
        bus.Memory[vector].Should().Be(0xBC);
        bus.Memory[vector + 1].Should().Be(0x9A);
    }

    /// <summary>
    ///  Monitor and disk entries retain their physical source positions through macro expansion.
    /// </summary>
    [TestMethod]
    public void MonitorAndDiskEntriesRetainDebuggerSourcePositions()
    {
        AssemblyResult native = AssembleExtension(Legacy(original: false), revised: 1);
        int start = checked((int)native.Symbol("CALLE"));
        DebugTestMemory memory = new();
        memory.Set((ushort)start, native.Sections[0].Bytes.Slice(start, 0xE000 - start).ToArray());
        SourceMapModule module = new(native, area: null);
        (string Name, string File)[] entries =
        [
            ("CALLE", "Commodore.Basic4Monitor.asm"),
            ("DOPEN", "Commodore.Basic4DiskCommands.asm"),
            ("DOSPAR", "Commodore.Basic4DiskParser.asm"),
            ("DSLINK", "Commodore.Basic4RomEnd.asm")
        ];

        foreach ((string name, string file) in entries)
        {
            ushort address = checked((ushort)native.Symbol(name));
            DebugPosition position = module.Position(memory, address)
                ?? throw new AssertFailedException($"{name} has no debugger source position.");

            position.Chain[0].Path.Should().EndWith(file);
            module.Entries(position.Chain[0].Path, position.Chain[0].Line).Should().Contain(address);
            module.Documentation.FindTopic(name).Should().NotBeNull();
        }
    }

    private static AssemblyResult Legacy(bool original) =>
        PetLegacyBasic.Assemble(PetInputs, PetModel.Pet4032, original);

    private static RecordingBus NativeBus(AssemblyResult native)
    {
        RecordingBus bus = new();
        native.Sections[0].Bytes.Span.CopyTo(bus.Memory);
        return bus;
    }

    private static void InstallCharacterReader(RecordingBus bus, AssemblyResult native, AssemblyResult legacy)
    {
        int reader = checked((int)native.Symbol("CHRGET"));
        int length = checked((int)(native.Symbol("RNDX") - reader));
        int template = checked((int)legacy.Symbol("INITAT"));
        legacy.Sections[0].Bytes.Span.Slice(template, length).CopyTo(bus.Memory.AsSpan(reader));
    }

    private static void InstallInput(RecordingBus bus, int entry, string text)
    {
        byte[] stub =
        [
            0xAE, 0x00, 0x07, 0xBD, 0x10, 0x07, 0xE8, 0x8E, 0x00, 0x07, 0x09, 0x00, 0x60
        ];

        stub.CopyTo(bus.Memory, entry);
        Encoding.ASCII.GetBytes(text).CopyTo(bus.Memory, InputBytes);
    }

    private static Processor<RecordingBus> Start(
        RecordingBus bus,
        AssemblyResult native,
        string entry,
        byte accumulator = 0,
        byte y = 0,
        StatusRegister status = StatusRegister.Unused)
    {
        bus.Memory[0x01FE] = (byte)((ReturnAddress - 1) & 0xFF);
        bus.Memory[0x01FF] = (byte)((ReturnAddress - 1) >> 8);
        return new Processor<RecordingBus>(bus)
        {
            Registers = new()
            {
                ProgramCounter = checked((ushort)native.Symbol(entry)),
                StackPointer = 0xFD,
                Accumulator = accumulator,
                Y = y,
                Status = status
            }
        };
    }

    private static void RunUntil(Processor<RecordingBus> cpu, ushort destination, int limit)
    {
        for (int instruction = 0; instruction < limit && cpu.Registers.ProgramCounter != destination; instruction++)
        {
            cpu.StepInstruction();
        }

        cpu.Registers.ProgramCounter.Should().Be(destination);
    }

    private static void AssertEmittedSpan(AssemblyResult result, int start, int end, bool exact)
    {
        IEnumerable<AssemblySourceMapEntry> entries = result.SourceMap.Where(entry =>
            entry.Size > 0 && entry.Operation != ".ORG");

        if (!exact)
        {
            entries = entries.Where(entry => entry.Address < end && entry.Address + entry.Size > start);
        }

        int next = start;
        foreach (AssemblySourceMapEntry entry in entries.OrderBy(entry => entry.Address))
        {
            entry.Section.Should().Be(0);
            int first = exact ? entry.Address : Math.Max(start, entry.Address);
            first.Should().Be(next, $"the emission at ${entry.Address:X4} must not leave a gap or overlap");
            next = exact ? entry.Address + entry.Size : Math.Min(end, entry.Address + entry.Size);
        }

        next.Should().Be(end, "the entire extension must be emitted");
    }

    private static AssemblyResult AssembleExtension(AssemblyResult legacy, int revised)
    {
        AssemblyResult result = BuildExtension(legacy, revised);
        return RequireSuccess(result);
    }

    private static AssemblyResult BuildExtension(AssemblyResult legacy, int revised, int? origin = null)
    {
        Dictionary<string, long> symbols = Dependencies(legacy);
        string source = $"""
            .cpu Mos6502
            .include "Commodore.Equates.asm"
            .include "Commodore.Basic4Extension.asm"
            .org ${(origin ?? legacy.Symbol("CALLE")):X4}
            LASTWR:
                COMMODORE_BASIC4_EXTENSION {revised}
            EXTENSION_END:
            """;

        return new Assembler.Assembler().Assemble(
            new AssemblySource(source, Path.Join(BasicInputs, "Basic4ExtensionTest.asm")),
            new AssemblyOptions(ProcessorVariant.Mos6502, 0, 0x10000)
            {
                SourceResolver = new FileAssemblySourceResolver(),
                PredefinedSymbols = BasicNames.WithCurrentNames(symbols)
            });
    }

    private static Dictionary<string, long> Dependencies(AssemblyResult legacy)
    {
        string[] dependencies =
        [
            "READY", "SNERR", "SYNCHR", "CHKCOM", "CHKOPN", "CHKCLS", "FRMEVL", "GETADR",
            "GETBYT", "GETSPA", "FRESTR", "LINPRT", "ERROR", "ERRFC", "ERRLS", "TOTK"
        ];

        Dictionary<string, long> symbols = dependencies.ToDictionary(
            name => name, name => legacy.Symbol(name), StringComparer.Ordinal);

        symbols.Add("DISK_STATUS_STRING", 1);
        symbols.Add("LINE_WIDTH_STORAGE", 0);
        symbols.Add("EXTENDED_DISK_VECTORS", 1);
        return symbols;
    }

    private static AssemblyResult Assemble(string source, IReadOnlyDictionary<string, long> symbols)
    {
        AssemblyResult result = new Assembler.Assembler().Assemble(
            new AssemblySource(source, Path.Join(BasicInputs, "Basic4ExtensionTest.asm")),
            new AssemblyOptions(ProcessorVariant.Mos6502, 0, 0x10000)
            {
                SourceResolver = new FileAssemblySourceResolver(),
                PredefinedSymbols = BasicNames.WithCurrentNames(symbols)
            });

        return RequireSuccess(result);
    }

    private static AssemblyResult RequireSuccess(AssemblyResult result)
    {
        result.Success.Should().BeTrue(string.Join(Environment.NewLine, result.Diagnostics.Select(diagnostic =>
            $"{diagnostic.Location?.Path}:{diagnostic.Location?.Line + 1}: {diagnostic.Message}")));

        return result;
    }
}
