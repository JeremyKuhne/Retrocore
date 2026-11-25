// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Assembler;
using Retrocore.Debug;
using Retrocore.Documentation;
using Retrocore.Machines.Commodore;

namespace Retrocore.Tests;

/// <summary>
///  Checks Commodore's own files as converted to the style guide (Basic.md, F): in each PET build, every old name they
///  give that Microsoft's MACRO-10 build defines reaches that build's value, every definition they make reaches the
///  overlay by its name or an old name, and each old name cites Commodore's documents, Microsoft's source or UNKN, all
///  in the bibliography.
/// </summary>
[TestClass]
public sealed partial class BasicCommodoreConversionTests
{
    // The files part F converted: the PET roots, BASIC 4's disk, monitor, record, extension and ROM-end files and its
    // system equates, BASIC 1's and BASIC 4's patches, and the string, clock and platform files.
    private static readonly string[] s_files =
    [
        "Basic1.asm", "Basic2.asm", "Basic4.asm", "Commodore.Basic1Patches.asm", "Commodore.Basic4Patches.asm",
        "Commodore.Basic4Extension.asm", "Commodore.Basic4SystemEquates.asm", "Commodore.Basic4Monitor.asm",
        "Commodore.Basic4Record.asm", "Commodore.Basic4DiskCommands.asm", "Commodore.Basic4DiskParser.asm",
        "Commodore.Basic4RomEnd.asm", "Commodore.StringAssignment.asm", "Commodore.StringGarbageCollection.asm",
        "Commodore.TimeAssignment.asm", "Commodore.Platform.asm", "Commodore.InterpreterMacros.asm"
    ];

    // The documents a Commodore file may cite: Commodore's, Microsoft's source and UNKN (no document gives the name).
    private static readonly string[] s_keys =
        ["M6502", "UNKN", "CBM4S79", "K4S79", "HV1", "HV1R", "HV2", "HV4", "HV4R", "HVK4"];

    private const int MinimumOverlayNames = 5;
    private const int MinimumOldNames = 400;

    /// <summary>
    ///  In each PET build, the converted files' old names reach the overlay's values, and their definitions reach the
    ///  overlay by a name, apart from the SDK's own (<see cref="SdkNames"/>).
    /// </summary>
    /// <param name="model">The PET model.</param>
    /// <param name="original">Whether BASIC 1 or 4 uses its original chip.</param>
    [TestMethod]
    [DataRow(PetModel.Pet2001, false)]
    [DataRow(PetModel.Pet2001, true)]
    [DataRow(PetModel.Pet2001Basic2, false)]
    [DataRow(PetModel.Pet4032, false)]
    [DataRow(PetModel.Pet4032, true)]
    public void PetOldNamesMatchTheOverlay(PetModel model, bool original)
    {
        AssemblyResult native = PetSdkModules.AssembleBasic(PetFolder, model, original);
        AssemblyResult legacy = PetLegacyBasic.Assemble(PetFolder, model, original);
        BasicWorkspaceConversionTests.CheckAgainstOverlay(
            native, legacy, Files, minimum: MinimumOverlayNames, SdkNames(native), scoped: true);
    }

    /// <summary>
    ///  Every old name in the converted files cites at least one key, each Commodore's document, Microsoft's source or
    ///  UNKN, and each in the bibliography.
    /// </summary>
    [TestMethod]
    public void OldNamesCiteCommodoresDocuments()
    {
        int count = 0;
        foreach (string path in Files)
        {
            string name = Path.GetFileName(path);
            foreach (DocumentationAlso also in DocumentationParser.Parse(File.ReadAllText(path), path).Comments
                .SelectMany(comment => DocumentationAlso.Of(comment.Sections)))
            {
                count++;
                also.Sources.Should().NotBeEmpty($"{also.Name} in {name} must cite its documents");
                also.Sources.Should().BeSubsetOf(s_keys, $"{also.Name} in {name} is Commodore's name");
                foreach (string key in also.Sources)
                {
                    BasicAttribution.Bibliography.Find(key).Should().NotBeNull(
                        $"{also.Name} in {name} cites {key}, which must be in docs/Bibliography.md");
                }
            }
        }

        count.Should().BeGreaterThan(MinimumOldNames, "the converted files keep every old name they renamed");
    }

    /// <summary>
    ///  Every converted file is checked by the strict lint.
    /// </summary>
    [TestMethod]
    public void ConvertedFilesAreStrict()
    {
        foreach (string path in Files)
        {
            DocumentationParser.IsStrict(File.ReadAllText(path)).Should().BeTrue($"{Path.GetFileName(path)} is converted");
        }
    }

    /// <summary>
    ///  None of the part's leftover old names (Basic.md I9) is used as a name in code any more: each is only an old name,
    ///  in its definition's <c>Also:</c>.
    /// </summary>
    /// <param name="model">The PET model.</param>
    /// <param name="original">Whether BASIC 1 or 4 uses its original chip.</param>
    [TestMethod]
    [DataRow(PetModel.Pet2001, false)]
    [DataRow(PetModel.Pet4032, false)]
    [DataRow(PetModel.Pet4032, true)]
    public void LeftoverNamesAreOldNames(PetModel model, bool original)
    {
        AssemblyResult native = PetSdkModules.AssembleBasic(PetFolder, model, original);
        string[] names = model == PetModel.Pet2001
            ?
            [
                "GETDTL", "INPSTP", "TISTR", "TINUM", "INCTRM", "GETSTR", "GETST1", "ARYINC", "TABER", "FREMES",
                "ROMLOC", "LASTWR"
            ]
            : ["INPSTP", "ISVAR", "TABER", "SIGNON", "ROMLOC", "LASTWR", .. original ? Array.Empty<string>() : ["INPNUL"]];

        foreach (string name in names)
        {
            native.SymbolDefinitions.Should().NotContain(symbol => symbol.Name == name, $"{name} is an old name now");
            native.HistoricalNames.Should().ContainKey(name, $"{name} stays reachable through Also:");
        }
    }

    /// <summary>
    ///  The converted files' code names every definition by its current name: no old name is left in an instruction,
    ///  a directive or a macro's argument, apart from the roots' checks that an old switch name is not predefined.
    /// </summary>
    /// <param name="model">The PET model.</param>
    /// <param name="original">Whether BASIC 1 or 4 uses its original chip.</param>
    [TestMethod]
    [DataRow(PetModel.Pet2001, false)]
    [DataRow(PetModel.Pet2001, true)]
    [DataRow(PetModel.Pet2001Basic2, false)]
    [DataRow(PetModel.Pet4032, false)]
    [DataRow(PetModel.Pet4032, true)]
    public void CodeUsesNoOldNames(PetModel model, bool original)
    {
        AssemblyResult native = PetSdkModules.AssembleBasic(PetFolder, model, original);
        HashSet<string> current = [.. native.SymbolDefinitions.Select(symbol => symbol.Name)];
        List<string> found = [];
        foreach (string path in Files)
        {
            string[] lines = File.ReadAllLines(path);
            for (int index = 0; index < lines.Length; index++)
            {
                string code = Code(lines[index]);
                if (code.Contains(".defined(", StringComparison.Ordinal)) { continue; }
                foreach (System.Text.RegularExpressions.Match word in Word().Matches(code))
                {
                    if (native.HistoricalNames.ContainsKey(word.Value) && !current.Contains(word.Value))
                    {
                        found.Add($"{Path.GetFileName(path)}:{index + 1}: {word.Value}");
                    }
                }
            }
        }

        found.Should().BeEmpty("code names definitions by their current names");
    }

    // A line's code, without its comment and its strings and character literals.
    private static string Code(string line)
    {
        char[] code = new char[line.Length];
        int length = 0;
        char quote = '\0';
        foreach (char character in line)
        {
            if (quote != '\0')
            {
                if (character == quote) { quote = '\0'; }
                continue;
            }

            if (character == ';') { break; }
            if (character is '"' or '\'') { quote = character; continue; }
            code[length++] = character;
        }

        return new string(code, 0, length);
    }

    // A name in code: not a scope's member, a hexadecimal or binary number's digits, or part of a character literal.
    [System.Text.RegularExpressions.GeneratedRegex(@"(?<![\w:.$%'])[A-Za-z_][A-Za-z0-9_]*")]
    private static partial System.Text.RegularExpressions.Regex Word();

    // The definitions that give no overlay name of their own, in the builds that have them: the SDK's switches and new
    // constants, the scoped aliases routines give workspace bytes, and the labels the old *+n branches became. Every
    // other definition must reach the overlay.
    private static HashSet<string> SdkNames(AssemblyResult native) =>
    [
        .. native.SymbolDefinitions
            .Where(symbol => BasicWorkspaceConversionTests.InFiles(symbol, Files))
            .Where(symbol => IsSdkName(symbol.Name))
            .Select(symbol => symbol.Name)
    ];

    private static bool IsSdkName(string name) =>
        s_sdkNames.Contains(name)
            || name.StartsWith("PARSED_", StringComparison.Ordinal)
            || name.StartsWith("TEMPLATE_", StringComparison.Ordinal)
            || s_scopedAliases.Contains(name);

    // The SDK's own constants and switches, which no document or overlay names.
    private static readonly HashSet<string> s_sdkNames =
    [
        // The roots' switches (KEEP rows) and BASIC 1's renamed ones.
        "REVISD", "TERMINAL_FIRST", "FULL_STACK_TOP", "STACK_RESERVE_19", "LOCAL_TERMINAL_POSITION",
        "VARIABLE_LIST_IN_LINE_NUMBER", "CLOCK_IN_PAGE2", "STATUS_IN_PAGE2", "RND_TIMER_9044", "ERROR_PADDING5",
        "GO_TOKEN", "BAD_DATA_ERROR", "COMMAND_TEST_CHARACTER", "COMMAND_RESET_BEFORE_INSERT", "LINK_RETURNS",
        "EARLY_LINE_EDIT", "TOKENIZE_SKIP_SPACES", "NEW_CLEAR_CARRY", "RUN_SET_ZERO", "RESET_STACK_EARLY",
        "RESET_STACK_PADDING", "LIST_GUARD_OFFSET", "STATEMENT_FETCH_NOP", "EARLY_SEPARATOR_CHECK", "SHORT_END_BRANCH",
        "EARLY_STATEMENT_DISPATCH", "STOP_BY_LINE_NUMBER", "NULL_INCREMENT_LIMIT", "RETURN_LOW_FOR_POINTER",
        "QUOTE_BRANCH_FIRST", "TIME_LONG_ERROR", "PRINT_CLEAR_SPC_CARRY", "PRINT_NULL_PADDING", "PRINT_TOKEN_SPACING",
        "ALWAYS_SKIP_CHARACTER", "INPUT_ERROR_EDITOR_PATCH", "INPUT_STOP_EDITOR_PATCH", "GET_POINTER_Y_FIRST",
        "GET_STRING_EDITOR_PATCH", "NEXT_COUNTED_STACK", "CLOCK_EDITOR_PATCH", "SUBSCRIPT_CHECKS_NUMERIC",
        "POSITIVE_INTEGER_CHECKS_TYPE", "ARRAY_SAVE_OFFSET_HIGH", "USER_FN_LOW_CHECK", "STRING_CLEARS_FAC_EXTENSION",
        "COLLECTOR_FULL_POINTER", "COLLECTOR_PATCH_ARRAY_STEP", "COLLECTOR_SUBTRACT_OFFSET", "REJECT_ZERO_SLICES",
        "STRING_PREAMBLE_INDIRECT_RETURN", "ASC_SHARED_LEN_JUMP", "PEEK_PRESERVE_ADDRESS", "PEEK_GUARD_ROM",
        "PEEK_PAD_GUARD", "SHORT_MULTIPLY_ZERO", "EARLY_INPUT_EXPONENT_LIMIT", "PRECISE_OUTPUT_LIMIT",
        "ZERO_IN_HALF_CONSTANT", "WAIT_EASTER_EGG", "RANDOM_SEED_TAIL", "INIT_MARK_DIRECT", "INIT_LINE_WIDTH",
        "INIT_DELAY_SIZE", "INIT_EARLY_BUFFER_SETUP", "PROBE_LOAD_ZERO", "PROBE_ZERO_INDEX", "PROBE_SAVE_START",
        "PROBE_STOP_AT_SCREEN", "PROBE_TEST_BYTE", "START_CARRY_PROGRAM_START", "START_BANNER_AFTER_FREE",
        "BASIC4_OUTPUT_PADDING", "RESET_STACK_POINTER", "DISK_STATUS_STRING", "LINE_WIDTH_STORAGE",
        "EXTENDED_DISK_VECTORS",

        // The new constants.
        "CLOCK_STRING_LENGTH", "GARBAGE_MARK", "LINK_SIZE", "STATUS_END_OF_FILE", "PATCH_AREA_END", "PATCH_FILL",
        "EXTENSION_ROM_END", "REPLACE_PREFIX", "FILENAME_LIMIT", "DEFAULT_DISK_UNIT", "FIRST_DISK_UNIT", "UNIT_LIMIT",
        "DRIVE_COUNT", "DISK_ID_LENGTH", "DIRECTORY_CHANNEL", "COMMAND_CHANNEL", "FILE_CHANNELS_BEFORE", "CATALOG_FILE",
        "SCREEN_DEVICE", "STATUS_LENGTH", "POSITION_COMMAND_LENGTH", "Monitor::SAVED_REGISTER_COUNT",
        "Monitor::HEADING_LENGTH", "Monitor::BYTES_PER_ROW", "Monitor::LOAD_COMMAND", "Monitor::SAVE_COMMAND",
        "Monitor::DEVICE_CASSETTE", "Monitor::DEVICE_SCREEN", "Monitor::FILENAME_LIMIT",

        // The label the clock assignment's *+5 branch became, and its routine, which has no old name of its own:
        // INPCOM is AssignString's, at the same address.
        "AssignClockString", "AssignClockString::Convert",

        // BASIC 4's descriptor copy by the shared modules' name, an equate of StoreLinkedDescriptor, which gives COPYZC.
        "StoreDescriptor"
    ];

    // The scoped aliases routines give the workspace's bytes for their own purposes, checked through the byte they
    // name.
    private static readonly HashSet<string> s_scopedAliases =
    [
        "Strings::CollectGarbage::GapOpen", "Strings::CollectGarbage::Source", "Strings::CollectGarbage::Destination",
        "Statements::Catalog::PairCount", "Statements::Catalog::BlockCount", "Disk::ParseParameters::NameLength",
        "Disk::PositionRecord::RecordNumber"
    ];

    private static string PetFolder => Path.Join(BasicNames.Inputs, "Pet");
    private static string CommodoreFolder => Path.Join(PetFolder, "Basic");
    private static string[] Files => [.. s_files.Select(file => Path.Join(CommodoreFolder, file))];
}
