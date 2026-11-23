// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Assembler;
using Retrocore.Debug;
using Retrocore.Debug.Language;
using Retrocore.Documentation;
using Retrocore.Machines.Commodore;

namespace Retrocore.Tests;

/// <summary>
///  Checks the native PET workspace against the assembled Microsoft BASIC overlays.
/// </summary>
[TestClass]
public sealed class PetNativeEquatesTests
{
    private const string EquatesFile = "Commodore.Equates.asm";
    private const string EndOfMath = "PET_EQUATES_TEST_END";

    private static string PetInputs => Path.Join(BasicNames.Inputs, "Pet");
    private static string BasicInputs => Path.Join(PetInputs, "Basic");
    private static string EquatesPath => Path.Join(BasicInputs, EquatesFile);
    private static string SharedInputs => Path.Join(BasicNames.Inputs, "Microsoft6502Basic");

    // These are selectors introduced by the native module, not names in the Microsoft overlay.
    private static readonly HashSet<string> s_features =
    [
        "TERMINAL_FIRST", "FULL_STACK_TOP", "STACK_RESERVE_19", "LOCAL_TERMINAL_POSITION", "LINE_WIDTH_STORAGE",
        "DISK_STATUS_STRING", "VARIABLE_LIST_IN_LINE_NUMBER", "CLOCK_IN_PAGE2", "STATUS_IN_PAGE2", "RND_TIMER_9044",
        "ERROR_PADDING5", "EXTENDED_DISK_VECTORS"
    ];

    /// <summary>
    ///  Each active native definition agrees with the corresponding assembled legacy symbol, including aliases.
    /// </summary>
    /// <param name="model">The PET model.</param>
    /// <param name="original">Whether BASIC 1 or 4 uses its original chip.</param>
    [TestMethod]
    [DataRow(PetModel.Pet2001, false)]
    [DataRow(PetModel.Pet2001, true)]
    [DataRow(PetModel.Pet2001Basic2, false)]
    [DataRow(PetModel.Pet4032, false)]
    [DataRow(PetModel.Pet4032, true)]
    public void WorkspaceDefinitionsMatchTheLegacyOverlay(PetModel model, bool original)
    {
        AssemblyResult legacy = PetLegacyBasic.Assemble(PetInputs, model, original);
        AssemblyResult native = RequireSuccess(AssembleEquates(Features(model)));
        CheckEquates(native, legacy);
        foreach (string name in (string[])["REALIO", "INTPRC", "ADDPRC", "LNGERR", "TIME", "EXTIO", "DISKO"])
        {
            native.Symbol(name).Should().Be(legacy.Symbol(name), $"{name} must match the Microsoft build");
        }

        bool early = model == PetModel.Pet2001;
        bool disk = model == PetModel.Pet4032;
        native.HasSymbol("NULCNT").Should().Be(early);
        native.HasSymbol("CQPNTR").Should().Be(early);
        native.HasSymbol("LINWID").Should().Be(!disk);
        native.HasSymbol("NCMWID").Should().Be(!disk);
        native.HasSymbol("CNTWFL").Should().Be(!disk);
        native.HasSymbol("DSDESC").Should().Be(disk);
        native.HasSymbol("CQCONC").Should().Be(disk);
        native.HasSymbol("CQRDDS").Should().Be(disk);

        DocumentationSet docs = DocumentationSet.Create(
            [DocumentationParser.Parse(File.ReadAllText(EquatesPath), EquatesPath)], native);

        IEnumerable<string> documented = NativeDefinitions(native).Select(symbol => symbol.Name)
            .Concat(s_features)
            .Concat(["INPUT_BUFFER_PAGE", "INPUT_BUFFER_LENGTH", "NULL_COMMAND"])
            .Distinct(StringComparer.Ordinal);

        foreach (string name in documented)
        {
            DocumentationTopic topic = docs.FindTopic(name)
                ?? throw new AssertFailedException($"{name} has no workspace documentation.");

            topic.Summary.Should().NotBeNullOrWhiteSpace($"{name} needs a useful description");
        }

        List<DocumentationDiagnostic> diagnostics = new DocumentationResolver(docs).Check();
        diagnostics.Should().BeEmpty(string.Join(Environment.NewLine, diagnostics.Select(diagnostic =>
            $"{Path.GetFileName(diagnostic.Path)}:{diagnostic.Line + 1}: {diagnostic.Message}")));
    }

    /// <summary>
    ///  The platform definitions provide a reusable workspace without emitting bytes and belong to the BASIC root.
    /// </summary>
    [TestMethod]
    public void PlatformDefinitionsAreReusableAndDoNotEmitBytes()
    {
        AssemblyResult native = RequireSuccess(Assemble(
            """
            .cpu Mos6502
            .org $4321
            PLATFORM_BEFORE:
            .include "Commodore.Platform.asm"
            PLATFORM_AFTER:
            """,
            Features(PetModel.Pet2001Basic2)));

        native.Symbol("PLATFORM_AFTER").Should().Be(native.Symbol("PLATFORM_BEFORE"));
        native.SourceMap.Where(entry => entry.Size > 0 && entry.Operation != ".ORG").Should().BeEmpty();

        string root = Path.Join(BasicInputs, "Basic4.asm");
        foreach (string file in (string[])
            ["Commodore.DispatchTables.asm", "Commodore.TimeAssignment.asm", "Commodore.StringAssignment.asm"])
        {
            SourceIncludes.RootOf(Path.Join(BasicInputs, file)).Should().Be(root);
        }
    }

    /// <summary>
    ///  The module is independently includable and its defaults select BASIC 2 without emitting or moving anything.
    /// </summary>
    [TestMethod]
    public void DefaultsAreSelfContainedBasic2()
    {
        AssemblyResult native = RequireSuccess(AssembleEquates(new Dictionary<string, long>()));
        AssemblyResult legacy = PetLegacyBasic.Assemble(PetInputs, PetModel.Pet2001Basic2);
        CheckEquates(native, legacy);
    }

    /// <summary>
    ///  Workspace choices are independent rather than one switch for an entire BASIC version.
    /// </summary>
    [TestMethod]
    public void WorkspaceFeaturesCanBeSelectedIndependently()
    {
        Dictionary<string, long> selectors = new()
        {
            ["INPUT_BUFFER_PAGE"] = 0,
            ["INPUT_BUFFER_LENGTH"] = 80,
            ["LOCAL_TERMINAL_POSITION"] = 1,
            ["CLOCK_IN_PAGE2"] = 1,
            ["STATUS_IN_PAGE2"] = 1
        };

        AssemblyResult baseline = RequireSuccess(AssembleEquates(selectors));
        selectors.Add("DISK_STATUS_STRING", 1);
        selectors.Add("VARIABLE_LIST_IN_LINE_NUMBER", 1);
        AssemblyResult selected = RequireSuccess(AssembleEquates(selectors));

        selected.Symbol("DSDESC").Should().Be(baseline.Symbol("CNTWFL"));
        selected.SymbolsWithHistoricalNames.Should().NotContainKey("CNTWFL");
        selected.Symbol("LINWID").Should().Be(baseline.Symbol("LINWID") + 2);
        selected.SymbolsWithHistoricalNames.Should().NotContainKey("CQCONC", "the disk descriptor does not select disk vectors");
        selected.Symbol("VARTXT").Should().Be(selected.Symbol("LINNUM"));
        baseline.Symbol("VARTXT").Should().Be(baseline.Symbol("OPPTR"));
        selected.Symbol("CQTIMR").Should().Be(baseline.Symbol("CQTIMR"));
        selected.Symbol("CQSTAT").Should().Be(baseline.Symbol("CQSTAT"));
        selected.Symbol("CQHTIM").Should().Be(baseline.Symbol("CQHTIM"));
    }

    /// <summary>
    ///  Invalid selectors do not silently produce a workspace.
    /// </summary>
    /// <param name="name">The selector.</param>
    /// <param name="value">Its unsupported value.</param>
    [TestMethod]
    [DataRow("INPUT_BUFFER_PAGE", 1)]
    [DataRow("LOCAL_TERMINAL_POSITION", 2)]
    [DataRow("FULL_STACK_TOP", -1)]
    [DataRow("STACK_LEVELS", 0)]
    [DataRow("STACK_LEVELS", 120)]
    [DataRow("INTEGER_VARIABLES", 0)]
    [DataRow("ADDITIONAL_PRECISION", 0)]
    [DataRow("LONG_ERRORS", 0)]
    [DataRow("TIME", 2)]
    [DataRow("EXTIO", 2)]
    [DataRow("DISKO", 2)]
    public void InvalidSelectorsAreRejected(string name, int value)
    {
        AssemblyResult result = AssembleEquates(new Dictionary<string, long> { [name] = value });
        result.Success.Should().BeFalse();
        result.Diagnostics.Select(diagnostic => diagnostic.Message).Should().Contain(message => message.Contains(name));
    }

    /// <summary>
    ///  An oversized page-zero buffer is rejected before it can collide with the page-one output buffer.
    /// </summary>
    [TestMethod]
    public void PageZeroWorkspaceCannotOverlapTheOutputBuffer()
    {
        AssemblyResult result = AssembleEquates(new Dictionary<string, long>
        {
            ["TERMINAL_FIRST"] = 1,
            ["INPUT_BUFFER_PAGE"] = 0,
            ["INPUT_BUFFER_LENGTH"] = 255
        });

        result.Success.Should().BeFalse();
        result.Diagnostics.Select(diagnostic => diagnostic.Message)
            .Should().Contain(message => message.Contains("workspace must not overlap NumberBufferPrefix"));
    }

    /// <summary>
    ///  The stack check's reserved levels must fit above the numeric output buffer.
    /// </summary>
    [TestMethod]
    public void StackReserveCannotOverlapTheOutputBuffer()
    {
        AssemblyResult result = AssembleEquates(new Dictionary<string, long> { ["STACK_END"] = 0x120 });
        result.Success.Should().BeFalse();
        result.Diagnostics.Select(diagnostic => diagnostic.Message)
            .Should().Contain(message => message.Contains("STACK_LEVELS's stack reserve"));
    }

    /// <summary>
    ///  Page-two input cannot share its buffer with the early kernal's clock or status byte.
    /// </summary>
    /// <param name="selector">The page-two operating-system workspace.</param>
    /// <param name="description">The storage described by the diagnostic.</param>
    [TestMethod]
    [DataRow("CLOCK_IN_PAGE2", "Clock")]
    [DataRow("STATUS_IN_PAGE2", "I/O status")]
    public void PageTwoInputCannotOverlapKernalState(string selector, string description)
    {
        AssemblyResult result = AssembleEquates(new Dictionary<string, long> { [selector] = 1 });
        result.Success.Should().BeFalse();
        result.Diagnostics.Select(diagnostic => diagnostic.Message).Should()
            .Contain(message => message.Contains("input buffer") && message.Contains(description));
    }

    /// <summary>
    ///  The actual shared math package assembles byte-identically using this workspace, without predefined RAM values.
    /// </summary>
    /// <param name="model">The PET model.</param>
    /// <param name="original">Whether BASIC 1 or 4 uses its original chip.</param>
    [TestMethod]
    [DataRow(PetModel.Pet2001, false)]
    [DataRow(PetModel.Pet2001, true)]
    [DataRow(PetModel.Pet2001Basic2, false)]
    [DataRow(PetModel.Pet4032, false)]
    [DataRow(PetModel.Pet4032, true)]
    public void MathUsesNativeWorkspaceAndMatchesTheLegacyBytes(PetModel model, bool original)
    {
        AssemblyResult legacy = PetLegacyBasic.Assemble(PetInputs, model, original);
        int start = checked((int)legacy.Symbol("FADDH"));
        int end = checked((int)legacy.Symbol("INITAT"));
        bool early = model == PetModel.Pet2001;
        bool waitMessage = model == PetModel.Pet2001Basic2;
        bool disk = model == PetModel.Pet4032;

        // Only labels belonging to other ROM regions are supplied. INTXT is the message data used by INPRT;
        // the others are routine entries, including nearby branch destinations. None is a predefined equate.
        List<string> externalLabels = ["ERROR", "FCERR", "STROUT", "ZERRTS", "INTXT"];
        if (waitMessage) { externalLabels.Add("STORDO"); }
        List<string> declarations = [];
        foreach (string name in externalLabels)
        {
            AssemblySymbol label = legacy.Definition(name);
            label.IsConstant.Should().BeFalse($"{name} must be a legacy ROM label, not a supplied constant");
            label.Value.Should().BeGreaterThanOrEqualTo(PetSdkModules.BasicOrigin(model),
                $"{name} must be in the BASIC ROM");

            (label.Value < start || label.Value >= end).Should().BeTrue($"{name} must be outside the math package");
            declarations.Add($".dum ${label.Value:X4}{Environment.NewLine}{name}:{Environment.NewLine}.dend");
        }

        Dictionary<string, long> selectors = Features(model);
        selectors.Add("SHORT_MULTIPLY_ZERO", early ? 1 : 0);
        selectors.Add("EARLY_INPUT_EXPONENT_LIMIT", early ? 1 : 0);
        selectors.Add("PRECISE_OUTPUT_LIMIT", early ? 1 : 0);
        selectors.Add("ZERO_IN_HALF_CONSTANT", early ? 0 : 1);
        selectors.Add("WAIT_EASTER_EGG", waitMessage ? 1 : 0);
        selectors.Add("BASIC4_OUTPUT_PADDING", disk ? 1 : 0);

        // The math package's two sign tokens and two error offsets are defined with their tables in
        // Commodore.DispatchTables.asm, which this region does not include, so the overlay supplies them.
        foreach (string name in (string[])["PLUSTK", "MINUTK", "ERROV", "ERRDV0"])
        {
            selectors.Add(name, legacy.Symbol(name));
        }

        // Commodore's historical names also alias the character reader's template, outside this region.
        Dictionary<string, long> template = new(StringComparer.Ordinal)
        {
            ["CHZGOT"] = legacy.Symbol("CHZGOT"),
            ["CHZRTS"] = legacy.Symbol("CHZRTS")
        };

        string source = $"""
            .cpu Mos6502
            .include "{EquatesFile}"
            {string.Join(Environment.NewLine, declarations)}
            .org ${start:X4}
            .include "Commodore.FloatingPoint.asm"
            {EndOfMath}:
            {BasicNames.ScopedNames(template)}
            .include "Commodore.HistoricalNames.asm"
            """;

        AssemblyResult native = RequireSuccess(Assemble(source, selectors));
        native.Symbol(EndOfMath).Should().Be(end);
        AssertEmittedSpan(native, start, end);

        ReadOnlySpan<byte> expected = legacy.Sections[0].Bytes.Span.Slice(start, end - start);
        ReadOnlySpan<byte> actual = native.Sections[0].Bytes.Span.Slice(start, end - start);
        int firstDifference = actual.CommonPrefixLength(expected);
        firstDifference.Should().Be(expected.Length, $"the first different byte is at ${start + firstDifference:X4}");

        foreach (AssemblySymbol legacyLabel in legacy.SymbolDefinitions.Where(symbol =>
            !symbol.IsConstant && symbol.Value >= start && symbol.Value < end))
        {
            AssemblySymbol definition = native.FindDefinition(legacyLabel.Name)
                ?? throw new AssertFailedException($"The math package does not define {legacyLabel.Name}.");

            definition.Value.Should().Be(legacyLabel.Value, $"{legacyLabel.Name} must retain its legacy address");
            AssemblyLocation location = definition.Location
                ?? throw new AssertFailedException($"{legacyLabel.Name} must have a physical definition.");

            location.Path.Should().NotBe("<predefined>");
            Path.GetFileName(location.Path).Should().NotBe("NativeEquatesTest.asm",
                $"{legacyLabel.Name} must be defined by the math package, not its caller");
        }
    }

    /// <summary>
    ///  The shared interpreter and math sections assemble together against the native PET workspace.
    /// </summary>
    /// <param name="model">The PET model.</param>
    /// <param name="original">Whether BASIC 1 or 4 uses its original chip.</param>
    [TestMethod]
    [DataRow(PetModel.Pet2001, false)]
    [DataRow(PetModel.Pet2001, true)]
    [DataRow(PetModel.Pet2001Basic2, false)]
    [DataRow(PetModel.Pet4032, false)]
    [DataRow(PetModel.Pet4032, true)]
    public void SharedSectionsComposeWithTheNativeWorkspace(PetModel model, bool original)
    {
        AssemblyResult legacy = PetLegacyBasic.Assemble(PetInputs, model, original);
        bool early = model == PetModel.Pet2001;
        bool waitMessage = model == PetModel.Pet2001Basic2;
        bool disk = model == PetModel.Pet4032;
        Dictionary<string, long> symbols = Features(model);
        symbols.Add("SHORT_MULTIPLY_ZERO", early ? 1 : 0);
        symbols.Add("EARLY_INPUT_EXPONENT_LIMIT", early ? 1 : 0);
        symbols.Add("PRECISE_OUTPUT_LIMIT", early ? 1 : 0);
        symbols.Add("ZERO_IN_HALF_CONSTANT", early ? 0 : 1);
        symbols.Add("WAIT_EASTER_EGG", waitMessage ? 1 : 0);
        symbols.Add("BASIC4_OUTPUT_PADDING", disk ? 1 : 0);

        if (early || disk) { symbols.Add("ROMLOC", legacy.Symbol("ROMLOC")); }
        if (disk)
        {
            symbols.Add("SIGNON", legacy.Symbol("SIGNON"));
        }

        string source = $"""
            .cpu Mos6502
            .include "Commodore.Platform.asm"
            .include "MsBasic.Next.asm"
            .include "MsBasic.ExpressionCore.asm"
            .include "MsBasic.OperandEvaluation.asm"
            .include "MsBasic.CharacterReader.asm"
            .include "MsBasic.Assignment.asm"
            .include "MsBasic.UserFunctions.asm"
            .include "MsBasic.SimpleFunctions.asm"
            .include "MsBasic.MemoryManagement.asm"
            .include "MsBasic.MemoryAccess.asm"
            .include "MsBasic.IntegerConversion.asm"
            .include "MsBasic.Lister.asm"
            .include "MsBasic.ProgramTransfers.asm"
            .include "MsBasic.ProgramReset.asm"
            .include "MsBasic.Print.asm"
            .include "MsBasic.Relational.asm"
            .include "MsBasic.StatementFlow.asm"
            .include "MsBasic.StringFunctions.asm"
            .include "MsBasic.StringConversion.asm"
            .include "MsBasic.StringConcatenation.asm"
            .include "MsBasic.StringGarbageCollection.asm"
            .include "MsBasic.StringStorage.asm"
            .include "Commodore.StringGarbageCollection.asm"
            .include "MsBasic.VariableInput.asm"
            .include "MsBasic.VariableLookup.asm"
            .include "MsBasic.Arrays.asm"
            .org ${legacy.Symbol("STMDSP"):X4}
                COMMODORE_DISPATCH_TABLES {(early ? 0 : 1)}, {(disk ? 1 : 0)}, {(early ? 1 : 0)}, {(disk ? 1 : 0)}
            COMPOSED_TABLE_END:
            .org ${legacy.Symbol("FNDFOR"):X4}
                MemoryManagement {(early ? "$36" : "$3E")}
            COMPOSED_MEMORY_MANAGEMENT_END:
                COMMODORE_ERROR_READY {(disk ? 0 : 1)}
                COMMODORE_COMMAND_LOOP {(early ? 0 : 1)}, {(early ? 0 : 1)}, {(early ? 0 : 1)}, {(disk ? 1 : 0)}
                COMMODORE_TERMINAL_INPUT {(early ? 1 : 0)}, {(disk ? 1 : 0)}
                COMMODORE_TOKENIZE {(disk ? 1 : 0)}, {(early ? 1 : 0)}
            COMPOSED_COMMAND_INPUT_END:
            .include "MsBasic.LineSearch.asm"
            COMPOSED_LINE_SEARCH_END:
                ProgramReset 0, 0, {(early ? 0 : 1)}, {(early ? 0 : 1)}
                {(early ? "" : "ClearStatement STKRTS")}
                ClearStorage 1, {(disk ? 1 : 0)}
                ExecutionReset {(early && original ? 1 : 0)}, {(early && !original ? 1 : 0)}, {(early ? (original ? "$FC" : "$FE") : "$FA")}
            COMPOSED_PROGRAM_RESET_END:
                ListRange 0, FLNRTS
                ListLines 1, {(early ? 0 : 1)}, 0, LINPRT, 0, READY
                ListTokens {(disk ? 1 : 0)}, 1, 1, 0
            COMPOSED_LIST_END:
            .include "MsBasic.For.asm"
            COMPOSED_FOR_END:
                COMMODORE_STATEMENT_FETCH INPUT_BUFFER_PAGE, {(waitMessage ? 1 : 0)}, {(early ? 1 : 0)}, {(early ? 1 : 0)}, {(disk && !original ? "GONEGT" : "CHRGET")}
                COMMODORE_STATEMENT_DISPATCH {(early ? 1 : 0)}, {(disk ? 1 : 0)}
            COMPOSED_STATEMENT_DISPATCH_END:
                RestoreStatement
                StopAndContinue {(early ? 0 : 1)}, {(disk ? 0 : 1)}
            COMPOSED_STOP_END:
                {(early ? "NullStatement 10" : "")}
                {(early ? "ClearStatement CONTRT" : "")}
                {(early ? "jmp CLEARC" : "")}
            COMPOSED_EARLY_CLEAR_END:
                RunStatement
                GosubAndGoto NEWSTT
                ReturnStatement {(early ? 1 : 0)}, 0
            COMPOSED_PROGRAM_TRANSFER_END:
                StatementScan {(early ? 1 : 0)}, 0
                ConditionalStatements
                OnStatement
            COMPOSED_STATEMENT_FLOW_END:
            .org ${legacy.Symbol("LINGET"):X4}
            .include "MsBasic.LineNumber.asm"
            COMPOSED_LINE_NUMBER_END:
            .org ${legacy.Symbol("LET"):X4}
                ASSIGNMENT_START
                TIME_STRING_ASSIGNMENT {(early ? 1 : 0)}
                STRING_ASSIGNMENT {(disk ? 1 : 0)}, {(disk ? 1 : 0)}
                {(disk ? $"STRING_LINK_ADJUST {(original ? 0 : 1)}" : "")}
            COMPOSED_ASSIGNMENT_END:
                COMMODORE_PRINT_CHANNELS
            COMPOSED_CHANNEL_PRINT_END:
                PrintItems TABER, {(early ? 0 : 1)}, 0, 1
            COMPOSED_PRINT_END:
                COMMODORE_LINE_END INPUT_BUFFER_PAGE, {(early ? 1 : 0)}, {(disk ? 1 : 0)}, {(early ? 1 : 0)}
            COMPOSED_LINE_END:
                COMMODORE_PRINT_SPACING {(early ? 1 : 0)}
            COMPOSED_PRINT_SPACING_END:
            .include "MsBasic.StringOutput.asm"
            COMPOSED_STRING_OUTPUT_END:
                COMMODORE_CHARACTER_OUTPUT {(early ? 1 : 0)}, {(early ? 1 : 0)}, {(disk ? 0 : 1)}, {(disk ? 0 : 1)}
            COMPOSED_CHARACTER_OUTPUT_END:
                COMMODORE_INPUT_ERROR {(early ? 1 : 0)}
            COMPOSED_INPUT_ERROR_END:
                COMMODORE_CHANNEL_INPUT INPUT_BUFFER_PAGE
            COMPOSED_CHANNEL_INPUT_END:
                COMMODORE_INPUT_STATEMENT {(disk ? 0 : 1)}, {(disk ? 3 : 2)}, {(disk && !original ? 1 : 0)}, {(early ? 1 : 0)}, {(disk ? 1 : 0)}
            COMPOSED_INPUT_END:
                VARIABLE_INPUT INPUT_BUFFER_PAGE, 0, {(early ? 1 : 0)}, {(early ? 1 : 0)}, 1, 0
                VARIABLE_INPUT_MESSAGES 0, {(disk ? 0 : 1)}
            COMPOSED_VARIABLE_INPUT_END:
                NextEntries {(early ? 1 : 0)}, NEWSTT
                EXPRESSION_CORE {(disk ? 1 : 0)}
            COMPOSED_EXPRESSION_END:
                OPERAND_EVALUATION 1, 1, ISFUN
            COMPOSED_OPERAND_END:
                {(disk ? $"COMMODORE_BASIC4_OPERAND_SPLIT {(original ? 0 : 1)}" : "")}
            COMPOSED_OPERAND_SPLIT_END:
                COMMODORE_VARIABLE_VALUE {(disk ? 1 : 0)}, {(early ? 1 : 0)}, {(disk ? 1 : 0)}
            COMPOSED_VARIABLE_VALUE_END:
                FUNCTION_DISPATCH
                LOGICAL_OPERATORS 1
            COMPOSED_FUNCTION_DISPATCH_END:
                RelationalOperators $FF
            COMPOSED_RELATIONAL_END:
            .include "MsBasic.Dim.asm"
            COMPOSED_DIM_END:
                VARIABLE_NAME 0, 0, 1, 0, {(disk ? 1 : 0)}, {(disk ? 1 : 0)}
            COMPOSED_VARIABLE_NAME_END:
                LetterTest
            COMPOSED_LETTER_TEST_END:
                SIMPLE_VARIABLE_LOOKUP 0, {(early ? 1 : 0)}, 0, 1, 1, {(disk ? 1 : 0)}, {(disk ? 1 : 0)}, 0
            COMPOSED_SCALAR_LOOKUP_END:
                IntegerConversionBoundary
                IntegerConversion {(early ? "FRMNUM" : "FRMEVL")}, {(early ? 0 : 1)}
            COMPOSED_INTEGER_CONVERSION_END:
                ARRAY_LOOKUP 0, {(disk ? 1 : 0)}, {(early ? 0 : 1)}
            COMPOSED_ARRAY_END:
            .include "MsBasic.ArrayMultiplication.asm"
            COMPOSED_MULTIPLY_END:
                SimpleFunctions 0
            COMPOSED_SIMPLE_FUNCTIONS_END:
                UserFunctions {(early ? 1 : 0)}
            COMPOSED_USER_FUNCTIONS_END:
                STRING_FROM_NUMBER
            COMPOSED_STRING_CONVERSION_END:
                STRING_STORAGE INPUT_BUFFER_PAGE, {(early ? 0 : 1)}
                STRING_ALLOCATION {(disk ? 1 : 0)}
            COMPOSED_STRING_STORAGE_END:
                {(disk ? "LINKED_STRING_GARBAGE_COLLECTION" : $"STRING_GARBAGE_COLLECTION {(early ? 0 : 1)}, {(early ? 1 : 0)}, {(early ? 1 : 0)}")}
            COMPOSED_COLLECTOR_END:
                STRING_CONCATENATION {(disk ? 1 : 0)}
            COMPOSED_CONCATENATION_END:
                STRING_FUNCTIONS {(early ? 1 : 0)}, {(early ? 1 : 0)}, {(early ? 1 : 0)}, {(disk ? 1 : 0)}
            COMPOSED_STRING_FUNCTIONS_END:
            .org ${legacy.Symbol("GETNUM"):X4}
                AddressConversion 1
                PeekFunction {(early ? 0 : 1)}, 1, {(early ? 1 : 0)}, {(waitMessage ? 1 : 0)}
                PokeStatement
                WaitStatement {(waitMessage ? "WaitHiddenMessage" : "STORDO")}
            COMPOSED_MEMORY_ACCESS_END:
            .org ${legacy.Symbol("FADDH"):X4}
            .include "Commodore.FloatingPoint.asm"
                CharacterReader {(early ? "$59" : "$58")}
            COMPOSED_READER_END:
                COMMODORE_INITIALIZE {(early ? 1 : 0)}, {(waitMessage ? 1 : 0)}, {(early ? 1 : 0)}, {(early ? 1 : 0)}, INPUT_BUFFER_PAGE, {(disk ? 1 : 0)}, {(early ? 1 : 0)}
                COMMODORE_MEMORY_PROBE {(early ? 1 : 0)}, {(early ? 1 : 0)}, {(early ? 0 : 1)}, {(disk ? 1 : 0)}, {(early ? 1 : 0)}, {(early ? "$92" : "$55")}
                COMMODORE_START_PROGRAM {(disk ? 0 : 1)}, {(early ? 1 : 0)}, {(disk ? 0 : 1)}, {(early ? 1 : 0)}, {(early ? "0" : disk ? "SIGNON" : "FREMES")}
            COMPOSED_INITIALIZATION_END:
                COMMODORE_START_MESSAGES {(early ? 1 : 0)}
            COMPOSED_MESSAGES_END:
                {(early ? "COMMODORE_BASIC1_EDITOR_PATCHES" : "")}
                {(early ? "" : BasicNames.Label("LASTWR"))}
            COMPOSED_BASIC1_PATCH_END:
            {(early ? ".org $E7F3" : "")}
                {(early ? "COMMODORE_BASIC1_ARRAY_PATCH" : "")}
            COMPOSED_BASIC1_ARRAY_END:
            .include "Commodore.HistoricalNames.asm"
            """;

        AssemblyResult native = RequireSuccess(Assemble(source, symbols));
        native.Symbol("COMPOSED_TABLE_END").Should().Be(legacy.Symbol("FNDFOR"));
        native.Symbol("COMPOSED_MEMORY_MANAGEMENT_END").Should().Be(legacy.Symbol("OMERR"));
        native.Symbol("COMPOSED_COMMAND_INPUT_END").Should().Be(legacy.Symbol("FNDLIN"));
        native.Symbol("COMPOSED_LINE_SEARCH_END").Should().Be(legacy.Symbol("SCRATH"));
        native.Symbol("COMPOSED_PROGRAM_RESET_END").Should().Be(legacy.Symbol("LIST"));
        native.Symbol("COMPOSED_LIST_END").Should().Be(legacy.Symbol("FOR"));
        native.Symbol("COMPOSED_FOR_END").Should().Be(legacy.Symbol("NEWSTT"));
        native.Symbol("COMPOSED_STATEMENT_DISPATCH_END").Should().Be(legacy.Symbol("RESTOR"));
        native.Symbol("COMPOSED_STOP_END").Should().Be(legacy.Symbol(early ? "NULL" : "RUN"));
        native.Symbol("COMPOSED_EARLY_CLEAR_END").Should().Be(legacy.Symbol("RUN"));
        native.Symbol("COMPOSED_PROGRAM_TRANSFER_END").Should().Be(legacy.Symbol("DATA"));
        native.Symbol("COMPOSED_STATEMENT_FLOW_END").Should().Be(legacy.Symbol("LINGET"));
        native.Symbol("COMPOSED_LINE_NUMBER_END").Should().Be(legacy.Symbol("LET"));
        native.Symbol("COMPOSED_ASSIGNMENT_END").Should().Be(legacy.Symbol("PRINTN"));
        native.Symbol("COMPOSED_CHANNEL_PRINT_END").Should().Be(legacy.Symbol("STRDON"));
        native.Symbol("COMPOSED_PRINT_END").Should().Be(legacy.Symbol("FININL"));
        native.Symbol("COMPOSED_LINE_END").Should().Be(legacy.Symbol("COMPRT"));
        native.Symbol("COMPOSED_PRINT_SPACING_END").Should().Be(legacy.Symbol("STROUT"));
        native.Symbol("COMPOSED_STRING_OUTPUT_END").Should().Be(legacy.Symbol("OUTSPC"));
        native.Symbol("COMPOSED_CHARACTER_OUTPUT_END").Should().Be(legacy.Symbol("TRMNOK"));
        native.Symbol("COMPOSED_INPUT_ERROR_END").Should().Be(legacy.Symbol("GET"));
        native.Symbol("COMPOSED_CHANNEL_INPUT_END").Should().Be(legacy.Symbol("INPUT"));
        native.Symbol("COMPOSED_INPUT_END").Should().Be(legacy.Symbol("READ"));
        native.Symbol("COMPOSED_VARIABLE_INPUT_END").Should().Be(legacy.Symbol("NEXT"));
        native.Symbol("COMPOSED_EXPRESSION_END").Should().Be(legacy.Symbol("EVAL"));
        native.Symbol("COMPOSED_OPERAND_END").Should().Be(legacy.Symbol("ISVAR") - (disk ? 1 : 0));
        native.Symbol("COMPOSED_OPERAND_SPLIT_END").Should().Be(legacy.Symbol(disk ? "ISVAR1" : "ISVAR"));
        native.Symbol("COMPOSED_VARIABLE_VALUE_END").Should().Be(legacy.Symbol("ISFUN"));
        native.Symbol("COMPOSED_FUNCTION_DISPATCH_END").Should().Be(legacy.Symbol("DOREL"));
        native.Symbol("COMPOSED_INTEGER_CONVERSION_END").Should().Be(legacy.Symbol("ISARY"));
        native.Symbol("COMPOSED_ARRAY_END").Should().Be(legacy.Symbol("UMULT"));
        native.Symbol("COMPOSED_RELATIONAL_END").Should().Be(legacy.Symbol("DIM3"));
        native.Symbol("COMPOSED_DIM_END").Should().Be(legacy.Symbol("PTRGET"));
        native.Symbol("COMPOSED_VARIABLE_NAME_END").Should().Be(legacy.Symbol("ISLETC"));
        native.Symbol("COMPOSED_LETTER_TEST_END").Should().Be(legacy.Symbol("NOTFNS"));
        native.Symbol("COMPOSED_SCALAR_LOOKUP_END").Should().Be(legacy.Symbol("N32768"));
        native.Symbol("COMPOSED_MULTIPLY_END").Should().Be(legacy.Symbol("FRE"));
        native.Symbol("COMPOSED_SIMPLE_FUNCTIONS_END").Should().Be(legacy.Symbol("ERRDIR"));
        native.Symbol("COMPOSED_USER_FUNCTIONS_END").Should().Be(legacy.Symbol("STR"));
        native.Symbol("COMPOSED_STRING_CONVERSION_END").Should().Be(legacy.Symbol("STRINI"));
        native.Symbol("COMPOSED_STRING_STORAGE_END").Should().Be(legacy.Symbol("GARBA2"));
        native.Symbol("COMPOSED_COLLECTOR_END").Should().Be(legacy.Symbol("CAT"));
        native.Symbol("COMPOSED_CONCATENATION_END").Should().Be(legacy.Symbol("CHR"));
        native.Symbol("COMPOSED_STRING_FUNCTIONS_END").Should().Be(legacy.Symbol("GETNUM"));
        native.Symbol("COMPOSED_MEMORY_ACCESS_END").Should().Be(legacy.Symbol("FADDH"));
        native.Symbol("COMPOSED_READER_END").Should().Be(legacy.Symbol("INIT"));
        native.Symbol("COMPOSED_INITIALIZATION_END").Should().Be(legacy.Symbol("WORDS"));
        native.Symbol("COMPOSED_MESSAGES_END").Should().Be(legacy.Symbol(early ? "INPSTP" : "LASTWR"));
        native.Symbol("COMPOSED_BASIC1_PATCH_END").Should().Be(legacy.Symbol("LASTWR"));
        if (early)
        {
            native.Symbol("COMPOSED_BASIC1_ARRAY_END").Should().Be(0xE7F9);
            int arrayPatch = checked((int)legacy.Symbol("ARYINC"));
            native.Symbol("ARYINC").Should().Be(arrayPatch);
            native.Sections[0].Bytes.Slice(arrayPatch, 6).ToArray()
                .Should().Equal(legacy.Sections[0].Bytes.Slice(arrayPatch, 6).ToArray());
        }

        List<(string first, string after)> regions = [("STMDSP", "LASTWR")];

        foreach ((string first, string after) in regions)
        {
            int start = checked((int)legacy.Symbol(first));
            int end = checked((int)legacy.Symbol(after));
            int next = start;
            foreach (AssemblySourceMapEntry entry in native.SourceMap
                .Where(entry => entry.Size > 0 && entry.Operation != ".ORG" && entry.Address >= start && entry.Address < end)
                .OrderBy(entry => entry.Address))
            {
                entry.Address.Should().Be(next, $"{first} must not contain a gap or overlap");
                next = entry.Address + entry.Size;
            }

            next.Should().Be(end, $"{first} must be emitted completely");
            native.Sections[0].Bytes.Slice(start, end - start).ToArray()
                .Should().Equal(legacy.Sections[0].Bytes.Slice(start, end - start).ToArray(), first);

            foreach (AssemblySymbol label in legacy.SymbolDefinitions.Where(
                symbol => !symbol.IsConstant && symbol.Value >= start && symbol.Value < end))
            {
                native.SymbolsWithHistoricalNames.Should().ContainKey(label.Name);
                native.Symbol(label.Name).Should().Be(label.Value, $"{label.Name} must retain its ROM address");
            }
        }

        foreach (string name in (string[])
            [
                "ENDTK", "FORTK", "DATATK", "GOTOTK", "GOSUTK", "REMTK", "PRINTK", "SCRATK",
                "TABTK", "TOTK", "FNTK", "SPCTK", "THENTK", "NOTTK", "STEPTK", "PLUSTK",
                "MINUTK", "GREATK", "EQULTK", "LESSTK", "ONEFUN", "LASNUM", "FORSIZ",
                "ERRNF", "ERRSN", "ERRRG", "ERROD", "ERRFC", "ERROV", "ERROM", "ERRUS",
                "ERRBS", "ERRDD", "ERRDV0", "ERRID", "ERRTM", "ERRLS", "ERRBD", "ERRST", "ERRCN", "ERRUF"
            ])
        {
            native.Symbol(name).Should().Be(legacy.Symbol(name), $"{name} must retain its token or error offset");
        }

        native.HasSymbol("GOTK").Should().Be(!early);
        if (!early) { native.Symbol("GOTK").Should().Be(legacy.Symbol("GOTK")); }

        // The workspace's files give the old names these files' documentation still uses.
        string[] documentedFiles =
        [
            Path.Join(BasicInputs, "Commodore.Equates.asm"),
            Path.Join(SharedInputs, "MsBasic.Layouts.asm"),
            Path.Join(BasicInputs, "Commodore.DispatchTables.asm"),
            Path.Join(BasicInputs, "Commodore.CommandInput.asm"),
            Path.Join(BasicInputs, "Commodore.ChannelInput.asm"),
            Path.Join(BasicInputs, "Commodore.Basic1Patches.asm"),
            Path.Join(BasicInputs, "Commodore.Basic4Patches.asm"),
            Path.Join(BasicInputs, "Commodore.VariableEvaluation.asm"),
            Path.Join(BasicInputs, "Commodore.Initialization.asm"),
            Path.Join(BasicInputs, "Commodore.StatementDispatch.asm"),
            Path.Join(BasicInputs, "Commodore.StringGarbageCollection.asm"),
            Path.Join(SharedInputs, "MsBasic.OperandEvaluation.asm"),
            Path.Join(SharedInputs, "MsBasic.CommandCore.asm"),
            Path.Join(SharedInputs, "MsBasic.StringConcatenation.asm"),
            Path.Join(SharedInputs, "MsBasic.StringConversion.asm"),
            Path.Join(SharedInputs, "MsBasic.StringGarbageCollection.asm"),
            Path.Join(SharedInputs, "MsBasic.VariableInput.asm"),
            Path.Join(SharedInputs, "MsBasic.VariableLookup.asm"),
            Path.Join(SharedInputs, "MsBasic.Arrays.asm")
        ];

        DocumentationSet docs = DocumentationSet.Create(
            documentedFiles.Select(path => DocumentationParser.Parse(File.ReadAllText(path), path)), native);

        foreach (string name in (string[])["GET", "INPUT", "TRMNOK", "ISFUN", "OROP", disk ? "ISVAR1" : "ISVAR"])
        {
            docs.FindTopic(name).Should().NotBeNull($"{name} must remain documented");
        }

        List<DocumentationDiagnostic> diagnostics = new DocumentationResolver(docs).Check();
        diagnostics.Should().BeEmpty(string.Join(Environment.NewLine, diagnostics.Select(diagnostic =>
            $"{Path.GetFileName(diagnostic.Path)}:{diagnostic.Line + 1}: {diagnostic.Message}")));
    }

    /// <summary>
    ///  GET initializes the right buffer sentinel and releases an active input channel.
    /// </summary>
    /// <param name="model">The PET BASIC version.</param>
    /// <param name="channel">The selected logical channel.</param>
    [TestMethod]
    [DataRow(PetModel.Pet2001, 0)]
    [DataRow(PetModel.Pet2001, 1)]
    [DataRow(PetModel.Pet2001Basic2, 1)]
    [DataRow(PetModel.Pet4032, 1)]
    public void GetInitializesTheVariantBufferAndReleasesAChannel(PetModel model, int channel)
    {
        AssemblyResult legacy = PetLegacyBasic.Assemble(PetInputs, model);
        bool early = model == PetModel.Pet2001;
        string source = $"""
            .cpu Mos6502
            .include "Commodore.ChannelInput.asm"
            .org ${legacy.Symbol("GET"):X4}
                COMMODORE_CHANNEL_INPUT {(early ? 0 : 2)}
            """;

        string[] dependencies =
        [
            "ERRDIR", "CHRGET", "GETBYT", "SYNCHR", "CQOIN", "CHANNL", "BUF",
            "INPCO1", "NOTQTI", "CQCCHN"
        ];

        Dictionary<string, long> symbols = dependencies.ToDictionary(
            name => name, name => legacy.Symbol(name), StringComparer.Ordinal);

        AssemblyResult native = RequireSuccess(Assemble(source, symbols));
        RecordingBus bus = new();
        native.Sections[0].Bytes.Span.CopyTo(bus.Memory);
        int buffer = checked((int)native.Symbol("BUF"));
        int channelAddress = checked((int)native.Symbol("CHANNL"));
        ushort input = checked((ushort)native.Symbol("INPCO1"));
        ushort release = checked((ushort)native.Symbol("CQCCHN"));
        bus.Memory[buffer + 1] = 0xAA;
        bus.Memory[channelAddress] = (byte)channel;
        bus.Memory[input] = 0x60;
        bus.Memory[release] = 0x60;
        const ushort ReturnAddress = 0x3000;
        bus.Memory[0x01FE] = (byte)((ReturnAddress - 1) & 0xFF);
        bus.Memory[0x01FF] = (byte)((ReturnAddress - 1) >> 8);
        Processor<RecordingBus> cpu = new(bus)
        {
            Registers = new()
            {
                ProgramCounter = checked((ushort)native.Symbol("GETTTY")),
                StackPointer = 0xFD,
                Status = StatusRegister.Unused
            }
        };

        int inputCalls = 0;
        int releaseCalls = 0;
        for (int instruction = 0; instruction < 50 && cpu.Registers.ProgramCounter != ReturnAddress; instruction++)
        {
            if (cpu.Registers.ProgramCounter == input)
            {
                inputCalls++;
                cpu.Registers.Accumulator.Should().Be(0x40);
                cpu.Registers.X.Should().Be((byte)((buffer + 1) & 0xFF));
                cpu.Registers.Y.Should().Be((byte)((buffer + 1) >> 8));
                bus.Memory[buffer + 1].Should().Be(0);
            }

            if (cpu.Registers.ProgramCounter == release) { releaseCalls++; }
            cpu.StepInstruction();
        }

        cpu.Registers.ProgramCounter.Should().Be(ReturnAddress);
        inputCalls.Should().Be(1);
        releaseCalls.Should().Be(channel == 0 ? 0 : 1);
        bus.Memory[channelAddress].Should().Be(0);
    }

    /// <summary>
    ///  Both probes stop at screen memory, retaining the versions' different RAM test patterns.
    /// </summary>
    /// <param name="model">The PET BASIC version.</param>
    /// <param name="lastTestByte">The second byte written when the last RAM address is probed.</param>
    [TestMethod]
    [DataRow(PetModel.Pet2001, 0x24)]
    [DataRow(PetModel.Pet2001Basic2, 0xAA)]
    public void MemoryProbeStopsBeforeTheScreen(PetModel model, int lastTestByte)
    {
        bool early = model == PetModel.Pet2001;
        string source = $"""
            .cpu Mos6502
            .include "Commodore.Platform.asm"
            .org $3000
                COMMODORE_MEMORY_PROBE {(early ? 1 : 0)}, {(early ? 1 : 0)}, {(early ? 0 : 1)}, 0, {(early ? 1 : 0)}, {(early ? "$92" : "$55")}
            PROBE_END:
            """;

        AssemblyResult native = RequireSuccess(Assemble(source, Features(model)));
        RecordingBus bus = new();
        native.Sections[0].Bytes.Span.CopyTo(bus.Memory);
        int pointer = checked((int)native.Symbol("LINNUM"));
        bus.Memory[pointer] = 0xFE;
        bus.Memory[pointer + 1] = 0x7F;
        bus.Memory[0x8000] = 0x7E;
        Processor<RecordingBus> cpu = new(bus)
        {
            Registers = new()
            {
                ProgramCounter = checked((ushort)native.Symbol("LOOPMM")),
                Y = 0,
                Status = StatusRegister.Unused
            }
        };

        ushort end = checked((ushort)native.Symbol("PROBE_END"));
        for (int instruction = 0; instruction < 50 && cpu.Registers.ProgramCounter != end; instruction++)
        {
            cpu.StepInstruction();
        }

        cpu.Registers.ProgramCounter.Should().Be(end);
        bus.Memory[0x7FFF].Should().Be((byte)lastTestByte);
        bus.Memory[0x8000].Should().Be(0x7E, "the screen must not be probed");
        foreach (string name in (string[])["MEMSIZ", "FRETOP"])
        {
            int address = checked((int)native.Symbol(name));
            bus.Memory[address].Should().Be(0);
            bus.Memory[address + 1].Should().Be(0x80);
        }
    }

    /// <summary>
    ///  The direct-buffer page must not replace the saved program position used by INPUT retry.
    /// </summary>
    /// <param name="model">The PET BASIC version.</param>
    /// <param name="direct">Whether the statement is in the direct input buffer.</param>
    [TestMethod]
    [DataRow(PetModel.Pet2001, true)]
    [DataRow(PetModel.Pet2001, false)]
    [DataRow(PetModel.Pet2001Basic2, true)]
    [DataRow(PetModel.Pet2001Basic2, false)]
    [DataRow(PetModel.Pet4032, true)]
    [DataRow(PetModel.Pet4032, false)]
    public void StatementFetchPreservesTheSavedPositionInDirectMode(PetModel model, bool direct)
    {
        AssemblyResult legacy = PetLegacyBasic.Assemble(PetInputs, model);
        bool early = model == PetModel.Pet2001;
        bool basic2 = model == PetModel.Pet2001Basic2;
        string source = $"""
            .cpu Mos6502
            .include "Commodore.StatementDispatch.asm"
            .org ${legacy.Symbol("NEWSTT"):X4}
                COMMODORE_STATEMENT_FETCH {(early ? 0 : 2)}, {(basic2 ? 1 : 0)}, {(early ? 1 : 0)}, {(early ? 1 : 0)}, CHRGET
            """;

        List<string> dependencies = ["ISCNTC", "TXTPTR", "OLDTXT", "ENDCON", "CURLIN", "SNERR", "CHRGET", "GONE3"];
        if (!early) { dependencies.Add("MORSTS"); }
        Dictionary<string, long> symbols = dependencies.ToDictionary(
            name => name, name => legacy.Symbol(name), StringComparer.Ordinal);

        AssemblyResult native = RequireSuccess(Assemble(source, symbols));
        RecordingBus bus = new();
        native.Sections[0].Bytes.Span.CopyTo(bus.Memory);
        int text = direct ? (early ? 0x0040 : 0x0240) : 0x4000;
        int pointer = checked((int)native.Symbol("TXTPTR"));
        int saved = checked((int)native.Symbol("OLDTXT"));
        bus.Memory[pointer] = (byte)(text & 0xFF);
        bus.Memory[pointer + 1] = (byte)(text >> 8);
        bus.Memory[saved] = 0x34;
        bus.Memory[saved + 1] = 0x12;
        bus.Memory[text] = (byte)':';
        bus.Memory[checked((int)native.Symbol("ISCNTC"))] = 0x60;
        ushort destination = checked((ushort)native.Symbol(early ? "GONE" : "MORSTS"));
        Processor<RecordingBus> cpu = new(bus)
        {
            Registers = new()
            {
                ProgramCounter = checked((ushort)native.Symbol("NEWSTT")),
                StackPointer = 0xFF,
                Status = StatusRegister.Unused
            }
        };

        for (int instruction = 0; instruction < 30 && cpu.Registers.ProgramCounter != destination; instruction++)
        {
            cpu.StepInstruction();
        }

        cpu.Registers.ProgramCounter.Should().Be(destination);
        bus.Memory[saved].Should().Be(direct ? (byte)0x34 : (byte)(text & 0xFF));
        bus.Memory[saved + 1].Should().Be(direct ? (byte)0x12 : (byte)(text >> 8));
    }

    /// <summary>
    ///  The revised BASIC 4 statement reader rejects PI while passing other tokens through.
    /// </summary>
    /// <param name="token">The fetched token.</param>
    /// <param name="destination">The entry reached after the check.</param>
    [TestMethod]
    [DataRow(0xFF, "SNERR")]
    [DataRow(0x80, "CHRGOT")]
    [DataRow(0x00, "CHRGOT")]
    public void RevisedBasic4RejectsPiAsAStatement(int token, string destination)
    {
        AssemblyResult native = AssembleRevisedBasic4Patches();
        RecordingBus bus = new();
        native.Sections[0].Bytes.Span.CopyTo(bus.Memory);
        int reader = checked((int)native.Symbol("CHRGET"));
        bus.Memory[reader] = 0xA9;
        bus.Memory[reader + 1] = (byte)token;
        bus.Memory[reader + 2] = 0x60;
        ushort finish = checked((ushort)native.Symbol(destination));
        Processor<RecordingBus> cpu = new(bus)
        {
            Registers = new()
            {
                ProgramCounter = checked((ushort)native.Symbol("GONEGT")),
                StackPointer = 0xFF,
                Status = StatusRegister.Unused
            }
        };

        for (int instruction = 0; instruction < 20 && cpu.Registers.ProgramCounter != finish; instruction++)
        {
            cpu.StepInstruction();
        }

        cpu.Registers.ProgramCounter.Should().Be(finish);
        cpu.Registers.Accumulator.Should().Be((byte)token);
    }

    /// <summary>
    ///  A revised BASIC 4 blank input line stops at the terminal, retries a channel, or accepts file EOF.
    /// </summary>
    /// <param name="channel">The selected channel.</param>
    /// <param name="status">The kernal I/O status byte.</param>
    /// <param name="destination">The entry reached after the check.</param>
    [TestMethod]
    [DataRow(0, 0x40, "INPSTP")]
    [DataRow(1, 0x00, "GETAGN")]
    [DataRow(1, 0x40, "INPCON")]
    public void RevisedBasic4BlankInputHonorsTheChannelAndEof(int channel, int status, string destination)
    {
        AssemblyResult native = AssembleRevisedBasic4Patches();
        RecordingBus bus = new();
        native.Sections[0].Bytes.Span.CopyTo(bus.Memory);
        bus.Memory[checked((int)native.Symbol("CHANNL"))] = (byte)channel;
        bus.Memory[checked((int)native.Symbol("CQSTAT"))] = (byte)status;
        ushort finish = checked((ushort)native.Symbol(destination));
        Processor<RecordingBus> cpu = new(bus)
        {
            Registers = new()
            {
                ProgramCounter = checked((ushort)native.Symbol("INPNUL")),
                Status = StatusRegister.Unused
            }
        };

        for (int instruction = 0; instruction < 20 && cpu.Registers.ProgramCounter != finish; instruction++)
        {
            cpu.StepInstruction();
        }

        cpu.Registers.ProgramCounter.Should().Be(finish);
    }

    /// <summary>
    ///  BASIC 1 retains its missing high-offset store; later versions preserve the computed byte.
    /// </summary>
    /// <param name="model">The PET BASIC version.</param>
    /// <param name="expectedHigh">The high offset passed to the element-size multiplication.</param>
    [TestMethod]
    [DataRow(PetModel.Pet2001, 0)]
    [DataRow(PetModel.Pet2001Basic2, 2)]
    [DataRow(PetModel.Pet4032, 2)]
    public void ArrayIndexRetainsEachVersionsHighOffsetBehavior(PetModel model, int expectedHigh)
    {
        AssemblyResult legacy = PetLegacyBasic.Assemble(PetInputs, model);
        bool early = model == PetModel.Pet2001;
        bool disk = model == PetModel.Pet4032;
        string source = $"""
            .cpu Mos6502
            .include "MsBasic.Arrays.asm"
            .org ${legacy.Symbol("ISARY"):X4}
                ARRAY_LOOKUP 0, {(disk ? 1 : 0)}, {(early ? 0 : 1)}
            """;

        string[] dependencies =
        [
            "DIMFLG", "INTFLG", "VALTYP", "VARNAM", "INTIDX", "INDICE", "CHRGOT", "COUNT", "CHKCLS",
            "ARYTAB", "LOWTR", "STREND", "ERRBS", "ERRFC", "ERROR", "ERRDD", "FMAPTR", "REASON",
            "CURTOL", "UMULT", "INDEX", "ARYPNT", "OMERR", "ADDEND", "UMULTD", "VARPNT"
        ];

        Dictionary<string, long> symbols = dependencies.ToDictionary(
            name => name, name => legacy.Symbol(name), StringComparer.Ordinal);

        AssemblyResult native = RequireSuccess(Assemble(source, symbols));
        RecordingBus bus = new();
        native.Sections[0].Bytes.Span.CopyTo(bus.Memory);
        bus.Memory[checked((int)native.Symbol("COUNT"))] = 1;
        bus.Memory[checked((int)native.Symbol("INDICE")) + 1] = 1;
        bus.Memory[checked((int)native.Symbol("VARNAM"))] = (byte)'A';
        Processor<RecordingBus> cpu = new(bus)
        {
            Registers = new()
            {
                ProgramCounter = checked((ushort)native.Symbol("ADDIND")),
                Accumulator = 1,
                X = 0x34,
                Status = StatusRegister.Unused
            }
        };

        ushort destination = checked((ushort)native.Symbol("UMULTD"));
        for (int instruction = 0; instruction < 30 && cpu.Registers.ProgramCounter != destination; instruction++)
        {
            cpu.StepInstruction();
        }

        cpu.Registers.ProgramCounter.Should().Be(destination);
        int offset = checked((int)native.Symbol("CURTOL"));
        bus.Memory[offset].Should().Be(0x34);
        bus.Memory[offset + 1].Should().Be((byte)expectedHigh);
    }

    private static AssemblyResult AssembleRevisedBasic4Patches()
    {
        AssemblyResult legacy = PetLegacyBasic.Assemble(PetInputs, PetModel.Pet4032);
        string[] dependencies =
        [
            "ISVAR1", "DSDESC", "ADJDS1", "ADJ02", "CHRGET", "PI", "SNERR", "CHRGOT",
            "CHANNL", "CQSTAT", "INPSTP", "GETAGN", "INPCON"
        ];

        Dictionary<string, long> symbols = dependencies.ToDictionary(
            name => name, name => legacy.Symbol(name), StringComparer.Ordinal);

        string source = $"""
            .cpu Mos6502
            .include "Commodore.Basic4Patches.asm"
            .org ${legacy.Symbol("ISVAR") - 1:X4}
                COMMODORE_BASIC4_OPERAND_SPLIT 1
            """;

        return RequireSuccess(Assemble(source, symbols));
    }

    private static Dictionary<string, long> Features(PetModel model)
    {
        bool early = model == PetModel.Pet2001;
        bool disk = model == PetModel.Pet4032;
        return new()
        {
            ["INPUT_BUFFER_PAGE"] = early ? 0 : 2,
            ["INPUT_BUFFER_LENGTH"] = early ? 80 : 81,
            ["NULL_COMMAND"] = early ? 1 : 0,
            ["TERMINAL_FIRST"] = early ? 1 : 0,
            ["FULL_STACK_TOP"] = early ? 1 : 0,
            ["STACK_RESERVE_19"] = early ? 1 : 0,
            ["LOCAL_TERMINAL_POSITION"] = early ? 1 : 0,
            ["LINE_WIDTH_STORAGE"] = disk ? 0 : 1,
            ["DISK_STATUS_STRING"] = disk ? 1 : 0,
            ["VARIABLE_LIST_IN_LINE_NUMBER"] = early ? 1 : 0,
            ["CLOCK_IN_PAGE2"] = early ? 1 : 0,
            ["STATUS_IN_PAGE2"] = early ? 1 : 0,
            ["RND_TIMER_9044"] = early ? 1 : 0,
            ["ERROR_PADDING5"] = early ? 1 : 0,
            ["EXTENDED_DISK_VECTORS"] = disk ? 1 : 0
        };
    }

    private static AssemblyResult AssembleEquates(IReadOnlyDictionary<string, long> selectors) => Assemble(
        $"""
        .cpu Mos6502
        .org $4321
        EQUATES_BEFORE:
        .include "{EquatesFile}"
        EQUATES_AFTER:
        """,
        selectors);

    private static AssemblyResult Assemble(string source, IReadOnlyDictionary<string, long> selectors) =>
        new Retrocore.Assembler.Assembler().Assemble(
            new AssemblySource(source, Path.Join(BasicInputs, "NativeEquatesTest.asm")),
            new AssemblyOptions(ProcessorVariant.Mos6502, 0, 0x10000)
            {
                SourceResolver = new FileAssemblySourceResolver(),
                IncludePaths = [SharedInputs],
                PredefinedSymbols = BasicNames.WithCurrentNames(selectors)
            });

    private static AssemblyResult RequireSuccess(AssemblyResult result)
    {
        result.Success.Should().BeTrue(string.Join(Environment.NewLine, result.Diagnostics.Select(diagnostic =>
            $"{diagnostic.Location?.Path}:{diagnostic.Location?.Line + 1}: {diagnostic.Message}")));

        return result;
    }

    private static IEnumerable<AssemblySymbol> NativeDefinitions(AssemblyResult result) =>
        result.SymbolDefinitions.Where(symbol =>
            symbol.Location is { } location
                && Path.GetFileName(location.Path).Equals(EquatesFile, StringComparison.OrdinalIgnoreCase));

    private static void CheckEquates(AssemblyResult native, AssemblyResult legacy)
    {
        native.Symbol("EQUATES_AFTER").Should().Be(native.Symbol("EQUATES_BEFORE"),
            "including the workspace must not change the caller's origin");

        native.SourceMap.Where(entry => entry.Size > 0 && entry.Operation != ".ORG").Should().BeEmpty(
            "equates must not allocate or initialize RAM");

        AssemblySymbol[] definitions = [.. NativeDefinitions(native).Where(symbol => !s_features.Contains(symbol.Name))];
        definitions.Should().NotBeEmpty("the included workspace must supply definitions");
        foreach (AssemblySymbol definition in definitions)
        {
            legacy.TryGetCounterpart(native, definition.Name, out long expected).Should().BeTrue(
                $"{definition.Name} must have a corresponding assembled legacy symbol");

            definition.Value.Should().Be(expected, $"{definition.Name} must match the overlay");
        }

        // These Microsoft switches can be supplied before the include, so also compare them when predefined.
        foreach ((string name, string legacyName) in ((string, string)[])
            [("INPUT_BUFFER_PAGE", "BUFPAG"), ("INPUT_BUFFER_LENGTH", "BUFLEN"), ("NULL_COMMAND", "NULCMD")])
        {
            native.Symbol(name).Should().Be(legacy.Symbol(legacyName), $"{name} must match the overlay's {legacyName}");
        }

        // $Z is the simulator's entry, not a PET workspace label; MACRO-10 gives it a native alias.
        legacy.SymbolAliases.TryGetValue("$Z", out string? simulatorEntry);

        // Every legacy page-zero/page-one workspace label is required, not just whichever ones were implemented.
        AssemblySymbol[] workspaceLabels = [.. legacy.SymbolDefinitions.Where(symbol =>
            !symbol.IsConstant
                && symbol.Value >= 0
                && symbol.Value <= 0x100
                && symbol.Name != (simulatorEntry ?? "$Z"))];

        workspaceLabels.Should().NotBeEmpty("the legacy overlay must expose its RAM workspace");
        foreach (AssemblySymbol label in workspaceLabels)
        {
            native.TryGetSymbol(label.Name, out long value).Should().BeTrue(
                $"legacy workspace label {label.Name} must be available to native roots");

            value.Should().Be(label.Value, $"{label.Name} must retain its RAM address");
        }
    }

    private static void AssertEmittedSpan(AssemblyResult result, int start, int end)
    {
        int next = start;
        foreach (AssemblySourceMapEntry entry in result.SourceMap
            .Where(entry => entry.Size > 0 && entry.Operation != ".ORG")
            .OrderBy(entry => entry.Address))
        {
            entry.Section.Should().Be(0);
            entry.Address.Should().Be(next, "the native math package must not have gaps or overlaps");
            next = entry.Address + entry.Size;
        }

        next.Should().Be(end, "only the complete math package should emit bytes");
    }
}
