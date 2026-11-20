// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Debug;
using Retrocore.Machines.Apple2;
using Retrocore.Media;
using Retrocore.Pascal;

namespace Retrocore.Tests;

/// <summary>
///  An Apple Pascal Compiler decompiled and built again with itself, on the machine it runs on, to the same segments.
/// </summary>
/// <remarks>
///  <para>
///   Apple Pascal 1.3's disks are in <c>RETROCORE_APPLE2_PASCAL_DISKS</c>, as the Internet Archive's
///   <c>UCSD Pascal 1.3_1.DSK</c> to <c>1.3_3.DSK</c> or as WOZ images, <c>UCSD Pascal 1.3_APPLE1.woz</c> to
///   <c>APPLE3.woz</c>. Its Compiler, decompiled, compiles with <c>(*$S++*)</c> on a 128K IIe booted from APPLE1
///   with APPLE3's 128K system in place of the 64K one: the Apple II's 64K runs out in COMPINIT. Its two assembled
///   procedures, in PASCALCO, are assembled from their decompiled source and linked in. It takes about three minutes.
///  </para>
///  <para>
///   Apple Pascal 1.0's Compiler, from <c>UCSD Pascal 1.0_2.DSK</c>, compiles with itself on Apple III Pascal 1.1,
///   whose system disk, <c>Apple3Pascal1.1Disk1.dsk</c>, is in <c>RETROCORE_APPLE3_DISKS</c>. Apple Pascal 1.2's,
///   from <c>UCSD Pascal 1.2_2.DSK</c>, compiles with itself to Apple's p-code but for one jump table's word.
///  </para>
/// </remarks>
[TestClass]
public class PascalCompilerRoundTripTests
{
    private static readonly string s_inputs = Path.Join(AppContext.BaseDirectory, "Inputs");

    /// <summary>
    ///  Apple Pascal 1.3's Compiler, decompiled, compiled with itself, its assembled procedures assembled and linked,
    ///  has the same segments as Apple's.
    /// </summary>
    [TestMethod]
    public void ApplePascal13CompilerRebuildsItself()
    {
        string apple1 = PascalMediaTests.Apple2Pascal13Disk(1);
        string apple2 = PascalMediaTests.Apple2Pascal13Disk(2);
        string apple3 = PascalMediaTests.Apple2Pascal13Disk(3);
        if (!File.Exists(apple1) || !File.Exists(apple2) || !File.Exists(apple3))
        {
            Assert.Inconclusive("Set RETROCORE_APPLE2_PASCAL_DISKS to a folder with Apple Pascal 1.3's disks.");
        }

        byte[] original = PascalVolume.Read(Sectors(apple2), proDosOrder: false).ReadFile("SYSTEM.COMPILER");
        PascalDecompilation decompiled = PascalDecompiler.Decompile(PascalCodeFile.Read(original));
        string assembly = decompiled.Assembly ?? throw new AssertFailedException("PASCALCO has two assembled procedures.");

        string boot = Path.Join(Path.GetTempPath(), $"Retrocore-{Guid.NewGuid():N}-APPLE1-128K.dsk");
        try
        {
            File.WriteAllBytes(boot, Boot128K(apple1, apple3));
            string source = $"(*$S++*)\n{decompiled.Source}";
            (byte[]? compiled, string screen, _) = EmulatedPascalCompiler.CompileWithListing(source, boot, apple2, listing: null, s_inputs, files: null, Apple2Model.IIeEnhanced);
            if (compiled is null) { Assert.Fail($"The Compiler stopped:\n{screen}"); }

            (byte[]? assembled, string assembling) = EmulatedPascalTools.Assemble(assembly, apple1, apple2, s_inputs, Apple2Model.IIeEnhanced);
            if (assembled is null) { Assert.Fail($"The Assembler stopped:\n{assembling}"); }

            (byte[]? linked, string linking) = EmulatedPascalTools.Link(compiled, [assembled], apple1, apple2, s_inputs, Apple2Model.IIeEnhanced);
            if (linked is null) { Assert.Fail($"The Linker stopped:\n{linking}"); }

            PascalCodeComparison.Compare(PascalCodeFile.Read(original), PascalCodeFile.Read(linked)).Should().BeEmpty();
        }
        finally
        {
            File.Delete(boot);
        }
    }

    /// <summary>
    ///  Apple Pascal 1.3's Compiler's identifier record, T2, keeps the pointers its variants hold at its eighth word: a
    ///  pointer at a record's address the code shows more words of does not size the record, as a scalar there does.
    /// </summary>
    /// <remarks>
    ///  <para>
    ///   When a pointer lent its words, the record took five and lost both views, and the types after it were
    ///   numbered anew, so hints written for the Compiler's types no longer named them.
    ///  </para>
    /// </remarks>
    [TestMethod]
    public void ApplePascal13CompilersIdentifiersKeepTheirPointerViews()
    {
        string apple2 = PascalMediaTests.Apple2Pascal13Disk(2);
        if (!File.Exists(apple2))
        {
            Assert.Inconclusive("Set RETROCORE_APPLE2_PASCAL_DISKS to a folder with Apple Pascal 1.3's disks.");
        }

        byte[] original = PascalVolume.Read(Sectors(apple2), proDosOrder: false).ReadFile("SYSTEM.COMPILER");
        string source = PascalDecompiler.Decompile(PascalCodeFile.Read(original)).Source;
        string identifier = source.Split('\n').Single(line => line.StartsWith("  T2 = RECORD", StringComparison.Ordinal));

        identifier.Should().Contain("T2F7V1: T").And.Contain("T2F7V2: T");
    }

    /// <summary>
    ///  Apple Pascal 1.0's Compiler, decompiled and compiled with itself on Apple III Pascal 1.1, has the same segments
    ///  as Apple's.
    /// </summary>
    /// <remarks>
    ///  <para>
    ///   On a 64K Apple II the decompiled source runs out of memory in COMPINIT, and 1.0 has no 128K system: the Apple
    ///   III has the room. The Compiler goes on a tools volume of its own, /PASCAL2, its segments marked version 4, as
    ///   Apple III Pascal runs only its own code; the code it writes is its own, version 1. It takes about two
    ///   minutes.
    ///  </para>
    /// </remarks>
    [TestMethod]
    public void ApplePascal10CompilerRebuildsItself()
    {
        string apple2 = Path.Join(PascalMediaTests.Apple2Disks, "UCSD Pascal 1.0_2.DSK");
        string system = Path.Join(SosVolumeTests.Disks, "Apple3Pascal1.1Disk1.dsk");
        if (!File.Exists(apple2) || !File.Exists(system))
        {
            Assert.Inconclusive("Set RETROCORE_APPLE2_PASCAL_DISKS and RETROCORE_APPLE3_DISKS to folders with Apple Pascal 1.0's and Apple III Pascal 1.1's disks.");
        }

        byte[] original = PascalVolume.Read(File.ReadAllBytes(apple2), proDosOrder: false).ReadFile("SYSTEM.COMPILER");
        PascalDecompilation decompiled = PascalDecompiler.Decompile(PascalCodeFile.Read(original));
        decompiled.Warnings.Should().BeEmpty();

        string tools = Path.Join(Path.GetTempPath(), $"Retrocore-{Guid.NewGuid():N}-PASCAL2.dsk");
        try
        {
            SosVolumeBuilder builder = new("PASCAL2");
            builder.Add("SYSTEM.COMPILER", fileType: 0x02, auxType: 0, AsVersion4(original));
            File.WriteAllBytes(tools, builder.Build(proDosOrder: false));

            string source = $"(*$S++*)\n{decompiled.Source}";
            (byte[]? compiled, string screen, _) = EmulatedPascalCompiler.CompileWithListing(source, system, tools, listing: null, s_inputs);
            if (compiled is null) { Assert.Fail($"The Compiler stopped:\n{screen}"); }

            PascalCodeComparison.Compare(PascalCodeFile.Read(original), PascalCodeFile.Read(compiled)).Should().BeEmpty();
        }
        finally
        {
            File.Delete(tools);
        }
    }

    /// <summary>
    ///  Apple Pascal 1.2's Compiler, decompiled and compiled with itself, has Apple's p-code in every procedure, but for
    ///  one entry of a jump table, which only the Compiler Apple built it with could have written.
    /// </summary>
    /// <remarks>
    ///  <para>
    ///   It compiles with <c>(*$S++*)</c> on a 128K IIe booted from APPLE1 (<c>UCSD Pascal 1.2_1.DSK</c>) with APPLE3's
    ///   128K system (<c>1.2_3.DSK</c>) in place of the 64K one, which runs out of room in COMPINIT. It takes about five
    ///   minutes.
    ///  </para>
    ///  <para>
    ///   A jump farther than a byte reaches goes through its procedure's jump table, words at the procedure's end each
    ///   holding the distance back to a target. In Apple's PASCALCO.6, INSYMBOL, the big CASE's out-of-range jump goes
    ///   through one word for the CASE's end and its arms' 21 jumps to the end through another: a label of its own for
    ///   the out-of-range jump, as 1.3's Compiler and the Apple III's give it, which have OTHERWISE. 1.2's Compiler
    ///   gives both the CASE's one end label, one word, so its PASCALCO is a word, 2 bytes, shorter: the same jumps to
    ///   the same places. No Compiler on the disks at hand builds Apple's: 1.3's rejects IDSEARCH and TREESEARCH, the
    ///   Apple III's lay files out larger.
    ///  </para>
    /// </remarks>
    [TestMethod]
    public void ApplePascal12CompilerRebuildsItselfButForOneJumpTableEntry()
    {
        string apple1 = Path.Join(PascalMediaTests.Apple2Disks, "UCSD Pascal 1.2_1.DSK");
        string apple2 = Path.Join(PascalMediaTests.Apple2Disks, "UCSD Pascal 1.2_2.DSK");
        string apple3 = Path.Join(PascalMediaTests.Apple2Disks, "UCSD Pascal 1.2_3.DSK");
        if (!File.Exists(apple1) || !File.Exists(apple2) || !File.Exists(apple3))
        {
            Assert.Inconclusive("Set RETROCORE_APPLE2_PASCAL_DISKS to a folder with Apple Pascal 1.2's disks.");
        }

        byte[] original = PascalVolume.Read(Sectors(apple2), proDosOrder: false).ReadFile("SYSTEM.COMPILER");
        PascalDecompilation decompiled = PascalDecompiler.Decompile(PascalCodeFile.Read(original));
        decompiled.Warnings.Should().BeEmpty();

        string boot = Path.Join(Path.GetTempPath(), $"Retrocore-{Guid.NewGuid():N}-APPLE1-128K.dsk");
        byte[]? compiled;
        try
        {
            File.WriteAllBytes(boot, Boot128K(apple1, apple3));
            string source = $"(*$S++*)\n{decompiled.Source}";
            (compiled, string screen, _) = EmulatedPascalCompiler.CompileWithListing(source, boot, apple2, listing: null, s_inputs, files: null, Apple2Model.IIeEnhanced);
            if (compiled is null) { Assert.Fail($"The Compiler stopped:\n{screen}"); }
        }
        finally
        {
            File.Delete(boot);
        }

        PascalCodeFile apples = PascalCodeFile.Read(original);
        PascalCodeFile rebuilt = PascalCodeFile.Read(compiled);

        // The one difference: PASCALCO a word shorter, from the jump through the CASE's end's second word.
        IReadOnlyList<string> differences = PascalCodeComparison.Compare(apples, rebuilt);
        differences.Should().Equal(
            "PASCALCO: its length is 4614, not 4616.",
            "PASCALCO: the code differs from $051D in PASCALCO.6:",
            "  expected $051C: UJP $0760",
            "  actual   $051C: UJP $0760");

        // Every procedure's p-code is Apple's: each instruction, its operands, and where it jumps, from its procedure's
        // entry; a jump's operand, which of the table's words it goes through, apart.
        foreach (PascalSegment segment in apples.Segments.Where(segment => segment.Procedures.Count > 0))
        {
            PascalSegment other = rebuilt.Segments.Single(found => found.Name == segment.Name && found.Procedures.Count > 0);
            foreach (PascalProcedure procedure in segment.Procedures.Where(procedure => !procedure.IsNative))
            {
                PascalProcedure same = other.Procedures.Single(found => found.Index == procedure.Index);
                Shapes(other, same).Should().Equal(Shapes(segment, procedure), $"{segment.Name.Trim()}.{procedure.Index}");
            }
        }

        // The words of PASCALCO.6's jump table that go to the CASE's end: two in Apple's, one in the rebuilt.
        CaseEndWords(apples).Should().Be(2, Describe(apples));
        CaseEndWords(rebuilt).Should().Be(1, Describe(rebuilt));
    }

    // A procedure's p-code, each instruction's opcode, operands and data, and its jumps' targets from its entry; a
    // jump's own operand, which word of the jump table it takes, is not its shape.
    private static List<string> Shapes(PascalSegment segment, PascalProcedure procedure) =>
        [.. PcodeDisassembler.Disassemble(segment, procedure).Select(instruction => Shape(instruction, procedure.Entry))];

    private static string Shape(PcodeInstruction instruction, int entry)
    {
        string operands = instruction.Targets.Count > 0 ? "" : string.Join(",", instruction.Operands);
        string targets = string.Join(",", instruction.Targets.Select(target => target < 0 ? target : target - entry));
        return $"{instruction.Opcode.Code} {operands} {Convert.ToHexString(instruction.Data)} {targets}";
    }

    // How many words of PASCALCO.6's jump table, below its attributes' five words, go to the CASE's end: where its
    // biggest XJP goes out of its range.
    private static int CaseEndWords(PascalCodeFile file)
    {
        PascalSegment segment = file.Segments.Single(found => found.Name.Trim() == "PASCALCO" && found.Procedures.Count > 0);
        PascalProcedure procedure = segment.Procedures.Single(found => found.Index == 6);
        List<PcodeInstruction> tables = [.. PcodeDisassembler.Disassemble(segment, procedure).Where(instruction => instruction.Opcode.Code == Pcode.Xjp)];
        tables.Should().NotBeEmpty("PASCALCO.6 has its CASE");
        int end = tables.OrderByDescending(instruction => instruction.Targets.Count).First().Targets[0];
        byte[] code = segment.Code;
        int words = 0;
        for (int at = procedure.Attributes - 10; at > procedure.Exit; at -= 2)
        {
            if (at - (code[at] | (code[at + 1] << 8)) == end) { words++; }
        }

        return words;
    }

    private static string Describe(PascalCodeFile file)
    {
        PascalSegment segment = file.Segments.Single(found => found.Name.Trim() == "PASCALCO" && found.Procedures.Count > 0);
        PascalProcedure procedure = segment.Procedures.Single(found => found.Index == 6);
        return $"PASCALCO.6: entry ${procedure.Entry:X4}, exit ${procedure.Exit:X4}, attributes ${procedure.Attributes:X4}";
    }

    // A code file with each segment's version, bits 13 to 15 of its information word, 4, Apple III Pascal's.
    private static byte[] AsVersion4(byte[] code)
    {
        byte[] marked = (byte[])code.Clone();
        for (int slot = 0; slot < 16; slot++)
        {
            int at = 256 + (slot * 2);
            int information = marked[at] | (marked[at + 1] << 8);
            if (information == 0) { continue; }

            information = (information & 0x1FFF) | (4 << 13);
            marked[at] = (byte)information;
            marked[at + 1] = (byte)(information >> 8);
        }

        return marked;
    }

    // APPLE1 with APPLE3's 128K system as its own, and without the Editor, which a compile does not need.
    private static byte[] Boot128K(string apple1, string apple3)
    {
        byte[] boot = Sectors(apple1);
        PascalVolume extras = PascalVolume.Read(Sectors(apple3), proDosOrder: false);
        foreach ((string from, string to, PascalFileKind kind) in (ReadOnlySpan<(string, string, PascalFileKind)>)
            [("128K.APPLE", "SYSTEM.APPLE", PascalFileKind.Data), ("128K.PASCAL", "SYSTEM.PASCAL", PascalFileKind.Code)])
        {
            PascalVolume.DeleteFile(boot, proDosOrder: false, to);
            PascalVolume.WriteFile(boot, proDosOrder: false, to, kind, extras.ReadFile(from));
        }

        PascalVolume.DeleteFile(boot, proDosOrder: false, "SYSTEM.EDITOR");
        return boot;
    }

    // An image's sectors, a WOZ image's read back from its tracks.
    private static byte[] Sectors(string path) => path.EndsWith(".woz", StringComparison.OrdinalIgnoreCase)
        ? SectorDiskReader.Read(WozDisk.Load(File.ReadAllBytes(path)), proDosOrder: false)
        : File.ReadAllBytes(path);
}
