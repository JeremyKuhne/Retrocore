// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Basic;
using Retrocore.Machines.Apple2;
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
