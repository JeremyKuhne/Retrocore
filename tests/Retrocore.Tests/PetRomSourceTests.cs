// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Assembler;
using Retrocore.Debug;
using Retrocore.Machines.Commodore;
using System.Security.Cryptography;

namespace Retrocore.Tests;

/// <summary>
///  Verifies the SDK's sources for the Commodore PET's ROMs: BASIC 1 and 4 (original and revised) and BASIC 2, their
///  screen editors (BASIC 4's for both keyboards) and kernals, and the 901447-08 and 901447-10 character ROMs.
/// </summary>
/// <remarks>
///  <para>
///   Digests pin each build, so no ROM is needed. With the dumps (see <see cref="PetMachineTests"/>), a build that
///   differs names its first different byte.
///  </para>
/// </remarks>
[TestClass]
public sealed class PetRomSourceTests
{
    // The math labels whose old names only the Commodore builds give, by the shared definitions' names.
    private static readonly Dictionary<string, string> s_commodoreOnly = new(StringComparer.Ordinal)
    {
        ["MULLN2"] = "Functions::Log::MultiplyByLogOfTwo",
        ["GFDIV"] = "Functions::Tan::ToDividePacked"
    };

    private static string PetSources => Path.Join(BasicNames.Inputs, "Pet");

    /// <summary>
    ///  BASIC builds byte-identically to each version's chips, <c>$C000-$DFFF</c>, or BASIC 4's <c>$B000-$DFFF</c>.
    /// </summary>
    /// <param name="model">The model.</param>
    /// <param name="original">For BASIC 1 and 4, the original chip rather than the revised one.</param>
    /// <param name="expectedHash">The SHA-256 of the 8K or 12K.</param>
    [TestMethod]
    [DataRow(PetModel.Pet2001, false, "629B630F695D004B788AA23BCFA4ACB84D405D4B22D136C7CF93571DD89EE4A1")]
    [DataRow(PetModel.Pet2001, true, "4CBF2F93B493076D7468A4C165FA3B93537E8A3BD9170C8B674073B50C3454A9")]
    [DataRow(PetModel.Pet2001Basic2, false, "5B426B5C50350E5D50C4308A81288BB34F310D7384BCC43C66A0E18716A4CDBE")]
    [DataRow(PetModel.Pet4032, false, "71BB94523F666FC10A2DA1B15790620D07EF0ED9696A37922CBEA28D8F468025")]
    [DataRow(PetModel.Pet4032, true, "6F9702DCCCB86AE7F7A1A5FD4C89DF19799E1A05ADE462443948E48D2968CE44")]
    public void BasicMatchesTheChips(PetModel model, bool original, string expectedHash)
    {
        ReadOnlySpan<byte> image = PetSdkModules.BasicImage(PetSdkModules.AssembleBasic(PetSources, model, original), model).Span;
        Check(image, expectedHash, model, original, PetSdkModules.BasicOrigin(model));
    }

    /// <summary>
    ///  Each native root retains the overlay's ROM, editor spill and debugger entry points.
    /// </summary>
    /// <param name="model">The PET model.</param>
    /// <param name="original">Whether BASIC 1 or 4 uses its original first chip.</param>
    [TestMethod]
    [DataRow(PetModel.Pet2001, false)]
    [DataRow(PetModel.Pet2001, true)]
    [DataRow(PetModel.Pet2001Basic2, false)]
    [DataRow(PetModel.Pet4032, false)]
    [DataRow(PetModel.Pet4032, true)]
    public void NativeBasicMatchesTheOverlay(PetModel model, bool original)
    {
        AssemblyResult native = PetSdkModules.AssembleBasic(PetSources, model, original, BasicSourceKind.Native);
        AssemblyResult legacy = PetLegacyBasic.Assemble(PetSources, model, original);
        AssemblyResult editor = PetSdkModules.AssembleEditor(PetSources, model);

        PetSdkModules.BasicImage(native, model).ToArray().Should().Equal(PetSdkModules.BasicImage(legacy, model).ToArray());
        PetSdkModules.EditorImage(native, editor, model).Should().Equal(PetSdkModules.EditorImage(legacy, editor, model));

        int end = model.BasicVersion() == 4 ? 0xE000 : checked((int)legacy.Symbol("LASTWR"));
        foreach (AssemblySymbol label in legacy.SymbolDefinitions.Where(symbol =>
            !symbol.IsConstant && (symbol.Value >= PetSdkModules.BasicOrigin(model) && symbol.Value < end
                || model == PetModel.Pet2001 && symbol.Value is >= 0xE7F3 and < 0xE7F9)))
        {
            native.SymbolsWithHistoricalNames.Should().ContainKey(label.Name);
            native.Symbol(label.Name).Should().Be(label.Value, $"{label.Name} must retain its ROM address");
        }

        native.SourceMap.Select(entry => entry.Location?.Path).OfType<string>()
            .Select(Path.GetFileName).Should().Contain("MsBasic.CommandCore.asm");

        SourceMapModule module = new(native, area: null, collapseSingleStatementMacros: true);
        DebugTestMemory memory = new();
        memory.Set(0, native.Sections[0].Bytes.ToArray());
        foreach ((string name, string file) in ((string, string)[])
            [("PRINT", "MsBasic.Print.asm"), ("INIT", "Commodore.Initialization.asm")])
        {
            DebugPosition position = module.Position(memory, checked((ushort)native.Symbol(name)))
                ?? throw new AssertFailedException($"{name} has no native debugger position.");

            Path.GetFileName(position.Chain[0].Path).Should().Be(file);
        }
    }

    /// <summary>
    ///  Shared floating-point constants can be emitted at each PET BASIC version's addresses without changing their
    ///  bytes or their entry-point offsets.
    /// </summary>
    /// <param name="model">The PET model.</param>
    /// <param name="original">Whether BASIC 1 or 4 uses its original chip.</param>
    [TestMethod]
    [DataRow(PetModel.Pet2001, false)]
    [DataRow(PetModel.Pet2001, true)]
    [DataRow(PetModel.Pet2001Basic2, false)]
    [DataRow(PetModel.Pet4032, false)]
    [DataRow(PetModel.Pet4032, true)]
    public void SharedFloatConstantsMatchThePetRom(PetModel model, bool original)
    {
        AssemblyResult basic = PetLegacyBasic.Assemble(PetSources, model, original);
        string folder = Path.Join(BasicNames.Inputs, "Microsoft6502Basic");
        AssemblyOptions options = new(ProcessorVariant.Mos6502, 0, 0x10000)
        {
            SourceResolver = new FileAssemblySourceResolver()
        };

        foreach ((string macro, string end, string[] names) in ((string, string, string[])[])
            [
                ("LogarithmConstants", "LOG", ["FONE", "LOGCN2", "SQRHLF", "SQRTWO", "NEGHLF", "LOG2"]),
                ("OutputConstants", "NZMIL", ["NZ0999", "NZ9999", "NZMIL"]),
                ("OutputTables", "SQR", ["FHALF", "FOUTBL", "FDCEND", "TIMEND"]),
                ("ExponentialConstants", "EXP", ["LOGEB2", "EXPCON"]),
                ("SineConstants", "SINCON", ["PI2", "TWOPI", "FR4", "SINCON"]),
                ("ArctangentConstants", "INITAT", ["ATNCON"])
            ])
        {
            int origin = checked((int)basic.Symbol(names[0]));
            int expectedEnd = checked((int)basic.Symbol(end));
            if (macro == "SineConstants")
            {
                // Bytes after the sine coefficients differ between variants.
                expectedEnd += 1 + (basic.Sections[0].Bytes.Span[expectedEnd] + 1) * 5;
            }
            else if (macro == "OutputConstants")
            {
                // BASIC 4 places its checksum and padding after the scaling constants.
                expectedEnd += 5;
            }

            string invocation = macro switch
            {
                "OutputConstants" => $"{macro} {(model == PetModel.Pet2001 ? 1 : 0)}",
                "OutputTables" => $"{macro} {(model == PetModel.Pet2001 ? 0 : 1)}, 1",
                _ => macro
            };

            string source = $"""
                .cpu Mos6502
                .include "MsBasic.FloatConstants.asm"
                .org ${origin:X4}
                    {invocation}
                END_OF_CONSTANTS:
                """;

            AssemblyResult constants = new Assembler.Assembler().Assemble(
                new AssemblySource(source, Path.Join(folder, "FloatConstantsTest.asm")), options);

            constants.Success.Should().BeTrue(string.Join('\n', constants.Diagnostics.Select(diagnostic => diagnostic.Message)));
            foreach (string name in names)
            {
                constants.Symbol(name).Should().Be(basic.Symbol(name), $"{name} must land at the PET BASIC address");
            }

            if (macro == "OutputTables")
            {
                if (model == PetModel.Pet2001)
                {
                    constants.SymbolsWithHistoricalNames.Should().NotContainKey("ZERO");
                }
                else
                {
                    constants.Symbol("ZERO").Should().Be(basic.Symbol("ZERO"));
                }
            }

            constants.Symbol("END_OF_CONSTANTS").Should().Be(expectedEnd, $"{macro} must emit the whole table");
            int length = expectedEnd - origin;
            constants.Sections[0].Bytes.Slice(origin, length).ToArray()
                .Should().Equal(basic.Sections[0].Bytes.Slice(origin, length).ToArray(), $"{macro} must match {model}");
        }
    }

    /// <summary>
    ///  The shared math routines use each PET version's own addresses without changing the ROM's instructions.
    /// </summary>
    /// <param name="model">The PET model.</param>
    /// <param name="original">Whether BASIC 1 or 4 uses its original chip.</param>
    [TestMethod]
    [DataRow(PetModel.Pet2001, false)]
    [DataRow(PetModel.Pet2001, true)]
    [DataRow(PetModel.Pet2001Basic2, false)]
    [DataRow(PetModel.Pet4032, false)]
    [DataRow(PetModel.Pet4032, true)]
    public void SharedMathRoutinesMatchThePetRom(PetModel model, bool original)
    {
        AssemblyResult basic = PetLegacyBasic.Assemble(PetSources, model, original);
        string folder = Path.Join(BasicNames.Inputs, "Microsoft6502Basic");
        foreach ((string file, string macro, string first, string end, string[] entries, string[] dependencies) in
            ((string, string, string, string, string[], string[])[])
            [
                ("MsBasic.AdditionCore.asm", "AddEntries", "FADDH", "FSUBT",
                    ["FADDH", "FSUB", "FSUBT"],
                    ["FHALF", "FADD", "CONUPK", "FACSGN", "ARGSGN", "ARISGN", "FACEXP", "FADDT"]),
                ("MsBasic.AdditionCore.asm", "AddAndNormalize", "FADD5", "FONE",
                    ["FADD5", "FADD", "FADDT", "FADDC", "FADDA", "FADD1", "FADD4", "FADD3", "SUBIT", "FADFLT",
                     "NORMAL", "NORM3", "ZEROFC", "ZEROF1", "ZEROML", "FADD2", "NORM2", "NORM1", "SQUEEZ",
                     "RNDSHF", "RNDRTS", "NEGFAC", "NEGFCH", "INCFAC", "INCFRT", "OVERR", "MULSHF", "SHFTR2",
                     "SHIFTR", "SHFTR3", "SHFTR4", "ROLSHF", "SHFTR7", "SHFTRT"],
                    ["CONUPK", "MOVFA", "FACOV", "OLDOV", "ARGEXP", "FACEXP", "ZERRTS", "ARGSGN", "FACSGN",
                     "FAC", "ARISGN", "FACLO", "FACMO", "FACMOH", "FACHO", "ARGLO", "ARGMO", "ARGMOH",
                     "ARGHO", "ERROV", "ERROR", "RESHO", "BITS"]),
                ("MsBasic.Logarithm.asm", "LogarithmRoutine", "LOG", "FMULT",
                    ["LOG", "LOGERR", "LOG1", "MULLN2"],
                    ["SIGN", "FCERR", "FACEXP", "SQRHLF", "FADD", "SQRTWO", "FDIV", "FONE", "FSUB",
                     "LOGCN2", "POLYX", "NEGHLF", "FINLOG", "LOG2", "FMULT"]),
                ("MsBasic.ArithmeticCore.asm", "FloatArithmetic", "FMULT", "MOVFR",
                    ["FMULT", "FMULTT", "MLTPLY", "MLTPL1", "MLTPL2", "MLTPL3", "MULTRT", "CONUPK",
                     "MULDIV", "MLDEXP", "TRYOFF", "MLDVEX", "ZEREMV", "GOOVER", "MUL10", "FINML6",
                     "MUL10R", "TENZC", "DIV10", "FDIVF", "FDIV", "FDIVT", "DIVIDE", "SAVQUO", "QSHFT",
                     "SHFARG", "DIVSUB", "LD100", "DIVNRM", "DV0ERR"],
                    ["RESHO", "RESMOH", "RESMO", "RESLO", "FACOV", "FACLO", "FACMO", "FACMOH", "FACHO",
                     "MOVFR", "MULSHF", "ARGLO", "ARGMO", "ARGMOH", "ARGHO", "INDEX1", "ARGSGN", "FACSGN",
                     "ARISGN", "ARGEXP", "FACEXP", "ZEROML", "ZEROFC", "OVERR", "MOVAF", "FADDC", "MOVFM",
                     "ROUND", "ERRDV0", "ERROR"]),
                ("MsBasic.MovementCore.asm", "FloatMovement", "MOVFR", "SIGN",
                    ["MOVFR", "MOVFM", "MOV2F", "MOV1F", "MOVML", "MOVVF", "MOVMF", "MOVFA", "MOVFA1",
                     "MOVFAL", "MOVAF", "MOVEF", "MOVAFL", "MOVRTS", "ROUND", "INCRND"],
                    ["RESHO", "FACHO", "RESMOH", "FACMOH", "RESMO", "FACMO", "RESLO", "FACLO", "NORMAL",
                     "INDEX1", "FACSGN", "FACEXP", "FACOV", "TEMPF2", "TEMPF1", "FORPNT", "ARGSGN", "ARGEXP",
                     "INCFAC", "RNDSHF"]),
                ("MsBasic.ConversionCore.asm", "SignAndIntegerRoutines", "SIGN", "FIN",
                    ["SIGN", "FCSIGN", "FCOMPS", "SIGNRT", "SGN", "FLOAT", "FLOATS", "FLOATC", "FLOATB", "ABS",
                     "FCOMP", "FCOMPN", "FOUTCP", "FCOMPC", "FCOMPD", "QINT", "QISHFT", "QINTRT", "QINT1",
                     "INT", "CLRFAC", "INTRTS"],
                    ["FACEXP", "FACSGN", "FACHO", "FACMOH", "FACLO", "FACMO", "FACOV", "FADFLT", "INDEX2",
                     "BITS", "NEGFCH", "FAC", "SHIFTR", "ROLSHF", "INTEGR"]),
                ("MsBasic.DecimalInputCore.asm", "DecimalInput", "FIN", "NZ0999",
                    ["FIN", "FINZLP", "QPLUS", "FINC", "FINDGQ", "FIN1", "FINEC1", "FINEC", "FNEDG1",
                     "FINEC2", "FINDP", "FINE", "FINE1", "FINDIV", "FINMUL", "FINQNG", "NEGXQS", "FINDIG",
                     "FINDG1", "FINLOG", "FINEDG", "MLEX10", "MLEXMI"],
                    ["DECCNT", "SGNFLG", "CHRGET", "MINUTK", "PLUSTK", "EXPSGN", "TENEXP", "DPTFLG", "DIV10",
                     "MUL10", "NEGOP", "MOVAF", "FLOAT", "ARGSGN", "FACSGN", "ARISGN", "FACEXP", "FADDT",
                     "OVERR", "TXTPTR"]),
                ("MsBasic.OutputCore.asm", "DecimalOutput", "INPRT", "FHALF",
                    ["INPRT", "LINPRT", "STROU2", "FOUT", "FOUTC", "FOUT1", "FOUT37", "FOUT7", "FOUT4",
                     "FOUT3", "FOUT38", "FOUT9", "FOUT5", "BIGGES", "FOUTPI", "FOUT6", "FOUT39", "FOUT16",
                     "FOUT8", "FOUTIM", "FOUT2", "FOUT41", "FOUT40", "FOUTYP", "STXBUF", "FOUTCM", "FOULDY",
                     "FOUT11", "FOUT12", "FOUT14", "FOUT15", "FOUT19", "FOUT17", "FOUT20", "FPWRRT"],
                    ["INTXT", "CURLIN", "FACHO", "FACMOH", "FLOATC", "STROUT", "FACSGN", "FBUFFR", "FBUFPT",
                     "FACEXP", "NZMIL", "FMULT", "DECCNT", "NZ9999", "FCOMP", "NZ0999", "MUL10", "DIV10",
                     "FADDH", "QINT", "TENEXP", "FACLO", "FOUTBL", "FACMO", "FDECPT", "FDCEND", "TIMEND"]),
                ("MsBasic.TranscendentalCore.asm", "PowerRoutines", "SQR", "LOGEB2",
                    ["SQR", "FPWRT", "FPWRT1", "FPWR1", "NEGOP", "NEGRTS"],
                    ["MOVAF", "FHALF", "MOVFM", "EXP", "ARGEXP", "ZEROF1", "TEMPF3", "MOVMF", "ARGSGN",
                     "INT", "FCOMP", "INTEGR", "MOVFA1", "LOG", "FMULT", "FACEXP", "FACSGN"]),
                ("MsBasic.TranscendentalCore.asm", "ExponentialRoutine", "EXP", "POLYX",
                    ["EXP", "STOLD", "GOMLDV", "EXP1", "SWAPLP"],
                    ["LOGEB2", "FMULT", "FACOV", "INCRND", "OLDOV", "MOVEF", "FACEXP", "MLDVEX",
                     "INT", "INTEGR", "ARGEXP", "FSUBT", "NEGOP", "EXPCON", "POLY", "ARISGN", "MLDEXP"]),
                ("MsBasic.TranscendentalCore.asm", "PolynomialRoutines", "POLYX", "RMULZC",
                    ["POLYX", "POLY", "POLY1", "POLY3", "POLY2", "POLY4", "RANDRT"],
                    ["POLYPT", "MOV1F", "TEMPF1", "FMULT", "MOV2F", "DEGREE", "FADD", "TEMPF2"]),
                ("MsBasic.RandomCore.asm", "RandomRoutine", "RMULZC", "COS",
                    ["RMULZC", "RADDZC", "RND", "QSETNR", "RND1", "STRNEX", "GMOVMF"],
                    ["SIGN", "RNDX", "MOVFM", "FMULT", "FADD", "FACLO", "FACHO", "FACMOH", "FACMO",
                     "FACSGN", "FACEXP", "FACOV", "NORMAL", "MOVMF", "CQHTIM"]),
                ("MsBasic.TranscendentalCore.asm", "TrigonometricRoutines", "COS", "PI2",
                    ["COS", "SIN", "SIN1", "SIN2", "SIN3", "GPOLYX", "TAN", "GFDIV", "COSC"],
                    ["PI2", "FADD", "MOVAF", "TWOPI", "ARGSGN", "FDIVF", "INT", "ARISGN", "FSUBT",
                     "FR4", "FSUB", "FACSGN", "FADDH", "TANSGN", "NEGOP", "SINCON", "POLYX",
                     "MOV1F", "TEMPF3", "GMOVMF", "TEMPF1", "MOVFM", "FDIV"]),
                ("MsBasic.TranscendentalCore.asm", "ArctangentRoutine", "ATN", "ATNCON",
                    ["ATN", "ATN1", "ATN2", "ATN3", "ATN4"],
                    ["FACSGN", "NEGOP", "FACEXP", "FONE", "FDIV", "ATNCON", "POLYX", "PI2", "FSUB"])
            ])
        {
            int origin = checked((int)basic.Symbol(first));
            int expectedEnd = checked((int)basic.Symbol(end));
            if (macro == "AddEntries")
            {
                // BASIC 2 inserts its hidden-message routine immediately after FSUBT's 15 bytes.
                expectedEnd += 15;
            }

            Dictionary<string, long> symbols = [];
            foreach (string name in dependencies)
            {
                symbols.Add(name, basic.Symbol(name));
            }

            string invocation = macro switch
            {
                "FloatArithmetic" or "DecimalInput" => $"{macro} {(model == PetModel.Pet2001 ? 1 : 0)}",
                "DecimalOutput" => $"{macro} 0, 1",
                "RandomRoutine" => $"{macro} 1",
                _ => macro
            };

            string Source(Dictionary<string, long> predefined) => $"""
                .cpu Mos6502
                {BasicNames.ScopedNames(predefined)}
                .include "{file}"
                .org ${origin:X4}
                    {invocation}
                END_OF_ROUTINE:
                """;

            string source = Source(symbols);

            AssemblyOptions options = new(ProcessorVariant.Mos6502, 0, 0x10000)
            {
                SourceResolver = new FileAssemblySourceResolver(),
                PredefinedSymbols = BasicNames.WithCurrentNames(symbols)
            };

            AssemblyResult routine = new Assembler.Assembler().Assemble(
                new AssemblySource(source, Path.Join(folder, "MathRoutineTest.asm")), options);

            routine.Success.Should().BeTrue(string.Join('\n', routine.Diagnostics.Select(diagnostic => diagnostic.Message)));
            foreach (string name in entries)
            {
                // A name only the Commodore builds give is in Commodore's historical-names file, not this build.
                string current = s_commodoreOnly.GetValueOrDefault(name, name);
                routine.Symbol(current).Should().Be(basic.Symbol(name), $"{name} must land at the PET BASIC address");
            }

            routine.Symbol("END_OF_ROUTINE").Should().Be(expectedEnd, $"{macro} must emit the whole routine");
            int length = expectedEnd - origin;
            routine.Sections[0].Bytes.Slice(origin, length).ToArray()
                .Should().Equal(basic.Sections[0].Bytes.Slice(origin, length).ToArray(), $"{macro} must match {model}");

            if (model == PetModel.Pet2001 && !original && macro == "LogarithmRoutine")
            {
                symbols["FMULT"]++;

                AssemblyOptions misplacedOptions = new(ProcessorVariant.Mos6502, 0, 0x10000)
                {
                    SourceResolver = options.SourceResolver,
                    PredefinedSymbols = BasicNames.WithCurrentNames(symbols)
                };

                AssemblyResult misplaced = new Assembler.Assembler().Assemble(
                    new AssemblySource(Source(symbols), Path.Join(folder, "MathRoutineTest.asm")),
                    misplacedOptions);

                misplaced.Success.Should().BeFalse("LOG must not fall through to an unrelated address");
                misplaced.Diagnostics.Should().Contain(diagnostic => diagnostic.Message.Contains("LOG must fall through to FMULT."));
            }

            if (model == PetModel.Pet2001 && !original && (macro is "FloatArithmetic" or "DecimalInput"))
            {
                string invalidSource = source.Replace($"{macro} 1", $"{macro} 2", StringComparison.Ordinal);
                string parameter = macro == "FloatArithmetic" ? "shortZeroBranch" : "earlyExponentLimit";
                AssemblyResult invalid = new Assembler.Assembler().Assemble(
                    new AssemblySource(invalidSource, Path.Join(folder, "MathRoutineTest.asm")),
                    options);

                invalid.Success.Should().BeFalse("the variant selector must be 0 or 1");
                invalid.Diagnostics.Should().Contain(diagnostic => diagnostic.Message.Contains($"{parameter} is 0 or 1."));
            }
        }
    }

    /// <summary>
    ///  The two decimal-input variants preserve their different negative-exponent overflow behavior.
    /// </summary>
    /// <param name="model">The PET model selecting the variant.</param>
    /// <param name="exponent">The exponent accumulated before this digit.</param>
    /// <param name="digit">The next decimal digit.</param>
    /// <param name="expected">The resulting exponent byte.</param>
    [TestMethod]
    [DataRow(PetModel.Pet2001, 12, 0, 112)]
    [DataRow(PetModel.Pet2001, 13, 7, 121)]
    [DataRow(PetModel.Pet2001, 100, 9, 41)]
    [DataRow(PetModel.Pet2001Basic2, 9, 9, 99)]
    [DataRow(PetModel.Pet2001Basic2, 10, 9, 100)]
    public void DecimalInputPreservesNegativeExponentBehavior(PetModel model, int exponent, int digit, int expected)
    {
        AssemblyResult basic = PetLegacyBasic.Assemble(PetSources, model);
        int origin = checked((int)basic.Symbol("FIN"));
        int end = checked((int)basic.Symbol("NZ0999"));
        Dictionary<string, long> symbols = basic.Symbols
            .Where(symbol => symbol.Value < origin || symbol.Value >= end)
            .ToDictionary(symbol => symbol.Key, symbol => symbol.Value);

        string folder = Path.Join(BasicNames.Inputs, "Microsoft6502Basic");
        string source = $"""
            .cpu Mos6502
            {BasicNames.ScopedNames(symbols)}
            .include "MsBasic.DecimalInputCore.asm"
            .org ${origin:X4}
                DecimalInput {(model == PetModel.Pet2001 ? 1 : 0)}
            """;

        AssemblyResult input = new Assembler.Assembler().Assemble(
            new AssemblySource(source, Path.Join(folder, "DecimalInputTest.asm")),
            new AssemblyOptions(ProcessorVariant.Mos6502, 0, 0x10000)
            {
                SourceResolver = new FileAssemblySourceResolver(),
                PredefinedSymbols = BasicNames.WithCurrentNames(symbols)
            });

        input.Success.Should().BeTrue(string.Join('\n', input.Diagnostics.Select(diagnostic => diagnostic.Message)));
        RecordingBus bus = new();
        input.Sections[0].Bytes.Span.CopyTo(bus.Memory);
        int textPointer = checked((int)input.Symbol("TXTPTR"));
        int exponentAddress = checked((int)input.Symbol("TENEXP"));
        bus.Memory[textPointer] = 0;
        bus.Memory[textPointer + 1] = 2;
        bus.Memory[0x0200] = (byte)('0' + digit);
        bus.Memory[exponentAddress] = (byte)exponent;
        bus.Memory[checked((int)input.Symbol("EXPSGN"))] = 0x80;

        Processor<RecordingBus> cpu = new(bus);
        cpu.Registers = new()
        {
            ProgramCounter = checked((ushort)input.Symbol("FINEDG")),
            Status = StatusRegister.Unused
        };

        ushort exit = checked((ushort)input.Symbol("FINEC"));
        for (int instruction = 0; instruction < 32 && cpu.Registers.ProgramCounter != exit; instruction++)
        {
            cpu.StepInstruction();
        }

        cpu.Registers.ProgramCounter.Should().Be(exit, "the exponent digit must return to the input loop");
        bus.Memory[exponentAddress].Should().Be((byte)expected);
    }

    /// <summary>
    ///  The screen editor's chip, <c>$E000-$E7FF</c>, builds byte-identically for each version from BASIC's end and
    ///  the editor's source.
    /// </summary>
    /// <param name="model">The model.</param>
    /// <param name="expectedHash">The SHA-256 of the 2K.</param>
    [TestMethod]
    [DataRow(PetModel.Pet2001, "86DC50795651DE9F99C886EA61BD412F5372FA4940EEC7B550A9FA2D2DFFFC13")]
    [DataRow(PetModel.Pet2001Basic2, "5338B1DFFEBD695F6110C9995E16F7536BB63A909C2A0062B4789DE46904ADE9")]
    [DataRow(PetModel.Pet4032, "44C79CCE9BE64BE26000821957EF17CA2D86AB5CD66C1E6C4342B91FD5F04B67")]
    [DataRow(PetModel.Pet4032Business, "D3B7B8FD3405055DF62B265E01141464532FD0500B907BB9B9164740B2210BAC")]
    public void EditorMatchesTheChip(PetModel model, string expectedHash) =>
        Check(
            PetSdkModules.EditorImage(PetSdkModules.AssembleBasic(PetSources, model), PetSdkModules.AssembleEditor(PetSources, model), model),
            expectedHash,
            model,
            original: false,
            PetSdkModules.EditorOrigin);

    /// <summary>
    ///  The kernal builds byte-identically to each version's chips, <c>$F000-$FFFF</c>.
    /// </summary>
    /// <param name="model">The model.</param>
    /// <param name="expectedHash">The SHA-256 of the 4K.</param>
    [TestMethod]
    [DataRow(PetModel.Pet2001, "397B8CA539372D6E731EBD426077976C00E714CD140DC00E66B6AF7E0FC0B3DE")]
    [DataRow(PetModel.Pet2001Basic2, "056D5E84A6E4F2B5B40A4109F49515C2496A4BF99139A9F59ABE486DED5CD03D")]
    [DataRow(PetModel.Pet4032, "7CF8678B748BDA1FFEDEE69EA54888FEB3F5EC66DCA8143375CBDF8C3DE4D573")]
    public void KernalMatchesTheChips(PetModel model, string expectedHash) =>
        Check(PetSdkModules.AssembleKernal(PetSources, model).Sections[0].Bytes.Span, expectedHash, model, original: false, PetSdkModules.KernalOrigin);

    /// <summary>
    ///  The character ROM builds byte-identically to the 2001's 901447-08 and the 2001-N's 901447-10.
    /// </summary>
    /// <param name="model">The model.</param>
    /// <param name="expectedHash">The SHA-256 of the 2K.</param>
    [TestMethod]
    [DataRow(PetModel.Pet2001, "697390D9CD7DA9E77D71935B0BF71D1181F624E0BE802CBFB472803861443340")]
    [DataRow(PetModel.Pet2001Basic2, "DA3374C21D6EA440CEF5F338CE3F524E0A1E40DCB1EF64446C695F92C636F1FA")]
    public void CharactersMatchTheChip(PetModel model, string expectedHash) =>
        Check(PetSdkModules.AssembleCharacters(PetSources, model).Sections[0].Bytes.Span, expectedHash, model, original: false, origin: null);

    /// <summary>
    ///  With no dumps at all, each model boots from the SDK's builds to <c>READY.</c>.
    /// </summary>
    /// <param name="model">The model.</param>
    /// <param name="banner">BASIC's banner.</param>
    [TestMethod]
    [DataRow(PetModel.Pet2001, "*** COMMODORE BASIC ***")]
    [DataRow(PetModel.Pet2001Basic2, "### COMMODORE BASIC ###")]
    [DataRow(PetModel.Pet4032, "*** COMMODORE BASIC 4.0 ***")]
    [DataRow(PetModel.Pet4032Business, "*** COMMODORE BASIC 4.0 ***")]
    public void MachineBootsFromTheSdkBuilds(PetModel model, string banner)
    {
        PetMachine machine = new(PetSdkModules.BuildRoms(model, PetSources), model);
        string[] screen = PetMachineTests.RunToReady(machine);
        screen.Should().Contain(line => line.Trim() == banner, string.Join('\n', screen));
        screen.Should().Contain(line => line.StartsWith("READY.", StringComparison.Ordinal));
    }

    // Checks a build against its digest; when it differs and the dumps are present, names the first different byte.
    private static void Check(ReadOnlySpan<byte> actual, string expectedHash, PetModel model, bool original, int? origin)
    {
        string hash = Convert.ToHexString(SHA256.HashData(actual));
        if (hash == expectedHash) { return; }

        string directory = PetMachineTests.RomDirectory(model);
        string because = "the dumps are missing";
        if (File.Exists(Path.Join(directory, PetMachineTests.KernalChip(model))))
        {
            PetRoms roms = PetRoms.LoadFromDirectory(directory, model, original);
            ReadOnlySpan<byte> expected = origin is { } start
                ? roms.Image.Slice(start - PetRoms.Base, actual.Length)
                : roms.Characters;

            int first = actual.CommonPrefixLength(expected);
            because = origin is { } at ? $"the first difference is at ${at + first:X4}" : $"the first difference is at ${first:X3}";
        }

        hash.Should().Be(expectedHash, because);
    }
}