// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Assembler;
using Retrocore.Basic;
using Retrocore.Debug;
using Retrocore.Machines.Apple2;
using Retrocore.Machines.Coco;
using Retrocore.Machines.Trs80;

namespace Retrocore.Tests;

/// <summary>
///  Types BASIC lines on machines running the SDK's ROMs, which are byte-identical to the real ones, and checks the
///  library stores each line exactly as the ROM did and lists it back to the same bytes.
/// </summary>
[TestClass]
public sealed class BasicConformanceTests
{
    // Each quirk the tokenizers reproduce, typed as a person would.
    private static readonly string[] s_appleSoft =
    [
        "10 HOME",
        "20 PRINT \"HELLO, WORLD!\": REM greet",
        "30 IF SCORE > 5 THEN 100",
        "40 FOR I = A TO B STEP 2: NEXT I",
        "50 X = ATN(1) + SIN (2)",
        "60 DRAW 1 AT 5,6",
        "70 DATA 1, 2 ,\"A:B\", hello : PRINT",
        "80 ? \"Q\";TAB(5);SPC( 2)",
        "90 G O T O 10",
        "100 HGR 2: HCOLOR= 3: HPLOT 0,0 TO 279,191",
        "110 print a$; left$(b$,2)",
        "120 IF X AND Y OR NOT Z THEN PRINT",
        "130 ONERR GOTO 200: POKE 216,0",
        "140 A = 1E10 * .5: B% = -3",
        "150 & \"cmd\"",
        "170 REM  Mixed Case  text",
        "180 a=1:b=2",
        "190 PRINT \"unclosed",
        "200 LIST 10-20: PR# 6: IN# 0"
    ];

    private static readonly string[] s_level2 =
    [
        "10 CLS",
        "20 PRINT \"HELLO, WORLD!\" : REM greet",
        "30 IF SCORE > 5 THEN 100 ELSE 20",
        "40 FOR I = A TO B STEP 2 : NEXT I",
        "50 A=1 'note: here",
        "60 GO TO 10",
        "70 DATA 1, 2 ,\"A:B\", hello : PRINT",
        "80 ? \"Q\";TAB(5)",
        "90 print a$; left$(b$,2)",
        "100 IF X AND Y OR NOT Z THEN PRINT ELSE PRINT",
        "110 A# = 1D10 : B% = -3 : C! = 2",
        "120  PRINT \"two spaces\"",
        "130 PRINT\"a\";\"b\"",
        "140 ON ERROR GOTO 200 : RESUME NEXT",
        "150 X=PEEK(16396)+USR(0)"
    ];

    /// <summary>
    ///  AppleSoft on each IIe model stores typed lines as the library tokenizes them.
    /// </summary>
    /// <param name="model">The IIe model.</param>
    [TestMethod]
    [DataRow(Apple2Model.IIeEnhanced)]
    [DataRow(Apple2Model.IIe)]
    public void AppleSoftStoresWhatTheLibraryTokenizes(Apple2Model model)
    {
        Apple2Machine machine = BasicMachines.BootIIe(model);
        foreach (string line in s_appleSoft) { BasicMachines.TypeLine(machine, line); }

        BasicDialect dialect = model == Apple2Model.IIeEnhanced ? BasicDialect.AppleSoft : BasicDialect.AppleSoftOriginal;
        DelegateBasicMemory memory = new(address => machine.Bus.Peek((ushort)address), (_, _) => { });
        Verify(dialect, BasicProgram.Read(dialect, memory), s_appleSoft);
    }

    /// <summary>
    ///  Level II, both revisions, stores typed lines as the library tokenizes them.
    /// </summary>
    /// <param name="revision">The Level II revision.</param>
    [TestMethod]
    [DataRow(12)]
    [DataRow(13)]
    public void Level2StoresWhatTheLibraryTokenizes(int revision)
    {
        Trs80Machine machine = BasicMachines.BootLevel2(BasicMachines.Level2(revision));
        foreach (string line in s_level2) { BasicMachines.Type(machine, line + "\r"); }

        DelegateBasicMemory memory = new(address => machine.Bus.Peek((ushort)address), (_, _) => { });
        Verify(BasicDialect.Level2, BasicProgram.Read(BasicDialect.Level2, memory), s_level2);
    }

    /// <summary>
    ///  Color, Extended and Disk Extended Color BASIC, built from the SDK's sources, store typed lines as the library
    ///  tokenizes them: GO TO and GO SUB, functions after $FF, ELSE and the apostrophe after a colon, and the names
    ///  that swallow the words typed against them.
    /// </summary>
    [TestMethod]
    public void ColorBasicStoresWhatTheLibraryTokenizes()
    {
        CocoMachine machine = BootCoco(disk: 11);
        foreach (string line in s_colorBasic) { CocoMachineTests.Type(machine, line + "\r"); }

        BasicDialect dialect = BasicDialect.ColorBasicWith(extended: true, disk: 11);
        Verify(dialect, BasicProgram.Read(dialect, CocoMemory(machine)), s_colorBasic);
    }

    /// <summary>
    ///  Without the disk controller, Disk BASIC's words stay as their letters, as Extended BASIC leaves them.
    /// </summary>
    [TestMethod]
    public void ColorBasicCrunchesOnlyTheFittedRomsWords()
    {
        string[] typed = ["10 DIR 0:A=FREE(0):PRINT HEX$(10)"];
        CocoMachine machine = BootCoco(disk: 0);
        CocoMachineTests.Type(machine, typed[0] + "\r");

        BasicDialect dialect = BasicDialect.ColorBasicWith(extended: true, disk: 0);
        BasicProgram stored = BasicProgram.Read(dialect, CocoMemory(machine));
        Verify(dialect, stored, typed);
        stored.Lines[0].Tokens.Span.IndexOf("DIR"u8).Should().Be(0, "DIR is not Extended BASIC's");
    }

    private static readonly string[] s_colorBasic =
    [
        "10 CLS",
        "20 PRINT \"HELLO, WORLD!\" : REM GREET",
        "30 IF SCORE > 5 THEN 100 ELSE 20",
        "40 FOR I = A TO B STEP 2 : NEXT I",
        "50 A=1 'NOTE: HERE",
        "60 GOTO 10 : GOSUB 70",
        "70 DATA 1, 2 ,\"A:B\", HELLO : PRINT",
        "80 ? \"Q\";TAB(5)",
        "90 PRINT A$; LEFT$(B$,2); MID$(B$,1,1)",
        "100 IF X AND Y OR NOT Z THEN PRINT ELSE PRINT",
        "110 X=PEEK(1024)+USR(0)+JOYSTK(0)",
        "120 IFA=BTHEN10",
        "130 PRINT HEX$(255);STRING$(3,\"*\")",
        "140 PMODE 4,1:PCLS:LINE(0,0)-(10,10),PSET",
        "150 DIR 0:A=FREE(0):DOS",
        "160 PRINT USING \"##.##\";3.14",
        "170   PRINT \"SPACES\"",
        "180 X=10:Y=X*2/4-1>=A<B"
    ];

    // A CoCo 2 on Color BASIC 1.2 and Extended BASIC 1.1 from the SDK's sources, with Disk BASIC when asked.
    private static CocoMachine BootCoco(int disk)
    {
        string roms = Path.Join(AppContext.BaseDirectory, "Inputs", "Coco");
        AssemblyResult color = CocoSdkModules.AssembleColorBasic(Path.Join(roms, "ColorBasic.asm"), 12);
        AssemblyResult extended = CocoSdkModules.AssembleExtendedBasic(Path.Join(roms, "ExtendedBasic.asm"), 11);
        CocoDiskController? controller = disk == 0
            ? null
            : new(CocoSdkModules.AssembleDiskBasic(Path.Join(roms, "DiskBasic.asm"), disk).Sections[0].Bytes.Span);

        CocoMachine machine = new(
            new() { Model = CocoModel.Coco2, RamKilobytes = 64 },
            CocoRoms.ForCoco12(color.Sections[0].Bytes.Span, extended.Sections[0].Bytes.Span),
            controller);

        machine.Run(3 * (ulong)CocoTiming.ClockHertz);
        return machine;
    }

    private static DelegateBasicMemory CocoMemory(CocoMachine machine) =>
        new(address => machine.Bus.Peek((ushort)address), (_, _) => { }, bigEndian: true);

    private static void Verify(BasicDialect dialect, BasicProgram stored, string[] typed)
    {
        stored.Lines.Should().HaveCount(typed.Length, "every typed line was stored");
        for (int index = 0; index < typed.Length; index++)
        {
            BasicLine line = stored.Lines[index];
            string text = dialect.SplitLineNumber(typed[index], out int number);
            line.Number.Should().Be(number);
            Convert.ToHexString(dialect.Tokenize(text)).Should().Be(Convert.ToHexString(line.Tokens.Span), typed[index]);
            byte[] listed = dialect.Tokenize(dialect.Detokenize(line.Tokens.Span));
            listed.Should().Equal(line.Tokens.ToArray(), "the listing of {0}", typed[index]);
        }
    }
}
