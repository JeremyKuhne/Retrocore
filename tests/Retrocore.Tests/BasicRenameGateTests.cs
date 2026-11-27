// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Assembler;
using Retrocore.Debug;
using Retrocore.Machines.Apple2;
using Retrocore.Machines.Commodore;
using System.Collections.Concurrent;
using System.Reflection;
using System.Text.RegularExpressions;

namespace Retrocore.Tests;

/// <summary>
///  Checks that the BASIC tests survive a rename: a definition renamed in the native sources, keeping its old name in
///  a <c>;; Also:</c> section, leaves them green.
/// </summary>
/// <remarks>
///  <para>
///   The gate before the BASIC conversion renames Microsoft's names to full words. Every lookup goes through
///   <see cref="BasicNames"/>, which finds a name as a symbol or as a historical name.
///  </para>
/// </remarks>
[TestClass]
public sealed partial class BasicRenameGateTests
{
    // The shared modules and the vendors' interpreter files are converted, so the first rename is of a current name
    // each vendor defines as a label in its own file (the PET's in a macro's body): the reserved-word list.
    private const string OldName = "ReservedWords";
    private const string NewName = "ReservedNames";

    // A second rename, of a label a shared macro's body defines at top level (AssignmentStart's string entry), whose
    // Also: reaches it because each build expands the macro once.
    private const string MacroOldName = "AssignString";
    private const string MacroNewName = "AssignStringResult";

    // Each rename, with the files that define the name.
    private static readonly (string Old, string New, string[] Files, Regex Word)[] s_renames =
    [
        (OldName, NewName, ["AppleSoft.DispatchTables.asm", "Commodore.DispatchTables.asm"], OldNameWord()),
        (MacroOldName, MacroNewName, ["MsBasic.Assignment.asm"], MacroOldNameWord())
    ];

    // The classes that assemble the native BASIC sources and look its names up, run against the renamed copy.
    private static readonly Type[] s_renamed =
    [
        typeof(AppleSoftTests), typeof(Basic1IndependentSwitchTests), typeof(BasicNativeRootSwitchTests),
        typeof(BasicSharedAliasConsistencyTests), typeof(BasicSharedArrayMultiplicationTests),
        typeof(BasicMathConversionTests), typeof(BasicMathRoutineTests), typeof(BasicSharedAssignmentTests),
        typeof(BasicStatementsConversionTests), typeof(BasicStatementRoutineTests),
        typeof(BasicExpressionsConversionTests), typeof(BasicExpressionRoutineTests),
        typeof(BasicInterpreterConversionTests), typeof(BasicInterpreterRoutineTests), typeof(BuildLinkTests),
        typeof(BasicAppleConversionTests), typeof(BasicAppleRoutineTests),
        typeof(BasicSharedFloatAliasesTests),
        typeof(BasicSharedInterpreterAliasesTests),
        typeof(BasicSharedCharacterReaderTests), typeof(BasicSharedCommandInputTests), typeof(BasicSharedExpressionTests),
        typeof(BasicSharedForTests), typeof(BasicSharedGarbageCollectionTests), typeof(BasicSharedIntegerConversionTests),
        typeof(BasicSharedLineNumberTests), typeof(BasicSharedLineSearchTests), typeof(BasicSharedListerTests),
        typeof(BasicSharedMemoryAccessTests), typeof(BasicSharedMemoryManagementTests), typeof(BasicSharedNextTests),
        typeof(BasicSharedOperatorTableTests), typeof(BasicSharedPrintTests), typeof(BasicSharedProgramResetTests),
        typeof(BasicSharedProgramTransfersTests), typeof(BasicSharedSimpleFunctionsTests),
        typeof(BasicSharedStatementFlowTests), typeof(BasicSharedStringConcatenationTests),
        typeof(BasicSharedStringFunctionTests), typeof(BasicSharedStringStorageTests), typeof(BasicSharedUserFunctionsTests),
        typeof(BasicSharedVariableInputTests), typeof(BasicSharedVariableLookupTests), typeof(BasicTokenizerTests),
        typeof(BasicVariableTests), typeof(BasicWorkspaceConversionTests), typeof(BasicMonitorRoutineTests),
        typeof(BasicDiskRoutineTests), typeof(BasicCommodoreConversionTests), typeof(BasicCommodoreRoutineTests),
        typeof(PetBasic4ExtensionTests),
        typeof(PetBasic4RevisionTests), typeof(PetBasicConformanceTests), typeof(PetNativeEquatesTests),
        typeof(PetRomSourceTests), typeof(PetSharedFloatAssemblyTests), typeof(BasicNamesBuildTests),
        typeof(Vic20RomSourceTests)
    ];

    // Test sources that assemble BASIC but are not run against the renamed copy, each for its reason.
    private static readonly Dictionary<string, string> s_notRenamed = new(StringComparer.Ordinal)
    {
        // Compares the repository's copy with the SDK the host ships, which the renamed copy does not replace.
        ["BasicSharedSourceTests.cs"] = "compares with the shipped SDK",

        // Lints the sources from its own copy of the inputs, not through BasicNames.
        ["SdkDocumentationTests.cs"] = "lints the sources",

        // Assemble only byte images, Microsoft's base or resolver paths, and look no BASIC name up.
        ["Apple2SourceTests.cs"] = "looks no name up",
        ["LanguageAnalysisTests.cs"] = "looks no name up",
        ["OverlayBaseResolverTests.cs"] = "looks no name up",
        ["SystemMasterBasicTests.cs"] = "looks no name up",

        // Hands BASIC's symbols to the debug target, as a launch does, and looks no name up itself.
        ["PetSysProgramTests.cs"] = "looks no name up",

        // The lookups themselves and this gate.
        ["BasicNames.cs"] = "the lookups",
        ["BasicRenameGateTests.cs"] = "this gate"
    };

    // Helpers the renamed classes use, whose lookups are checked with theirs.
    private static readonly string[] s_helpers =
        ["BasicAttribution.cs", "BasicMachines.cs", "BasicMathMachine.cs", "PetLegacyBasic.cs", "PetRoutineMachine.cs"];

    /// <summary>
    ///  Renaming <c>ReservedWords</c> to <c>ReservedNames</c>, and <c>AssignString</c> in a macro's body to <c>AssignStringResult</c>, in a copy
    ///  of the native sources, each with its old name in <c>;; Also:</c>, keeps every ROM's bytes and leaves every
    ///  BASIC test green without changing it.
    /// </summary>
    [TestMethod]
    public void RenamingALabelLeavesTheTestsGreen()
    {
        string scratch = Directory.CreateTempSubdirectory("retrocore-rename").FullName;
        try
        {
            Dictionary<string, int> renamed = CopyRenamed(BasicNames.Inputs, scratch);
            foreach ((string oldName, _, _, _) in s_renames)
            {
                renamed[oldName].Should().BeGreaterThan(3, $"{oldName} is used across the native BASIC sources");
            }

            CheckRename(BasicNames.Inputs, scratch);

            ConcurrentBag<string> failures = [];
            ConcurrentBag<string> inconclusive = [];
            int run = 0;
            BasicNames.WithInputs(scratch, () => Parallel.ForEach(
                s_renamed.SelectMany(Cases),
                testCase =>
                {
                    // Each case must read the renamed copy, or the gate would pass on the unrenamed sources.
                    BasicNames.Inputs.Should().Be(scratch);
                    Interlocked.Increment(ref run);
                    switch (Run(testCase))
                    {
                        case (false, string message): failures.Add($"{Name(testCase)}: {message}"); break;
                        case (true, string message): inconclusive.Add($"{Name(testCase)}: {message}"); break;
                    }
                }));

            failures.Should().BeEmpty(
                $"renaming {OldName} and {MacroOldName} must not break a test; {run} ran, {inconclusive.Count} inconclusive:{Environment.NewLine}{string.Join(Environment.NewLine, failures)}");

            run.Should().BeGreaterThan(500);
            inconclusive.Should().OnlyContain(
                message => message.Contains("Assert.Inconclusive. Set RETROCORE_", StringComparison.Ordinal),
                "only a test that needs chip dumps the repository does not have may be inconclusive");
        }
        finally
        {
            Directory.Delete(scratch, recursive: true);
        }
    }

    /// <summary>
    ///  The gate has teeth: in the renamed copy, a lookup by the old name alone fails, the shared lookup by either
    ///  name succeeds, and a name that is neither still fails.
    /// </summary>
    [TestMethod]
    public void OldNameOnlyLookupsFailAfterTheRename()
    {
        string scratch = Directory.CreateTempSubdirectory("retrocore-rename").FullName;
        try
        {
            CopyRenamed(BasicNames.Inputs, scratch);
            AssemblyResult native = SdkModules.AssembleAppleSoft(SdkModules.AppleSoftPath(scratch), Apple2Model.IIeEnhanced);
            native.Success.Should().BeTrue();

            foreach ((string oldName, string newName, _, _) in s_renames)
            {
                Action oldNameOnly = () => _ = native.Symbols[oldName];
                oldNameOnly.Should().Throw<KeyNotFoundException>($"the renamed sources no longer define {oldName}");
                native.Symbol(oldName).Should().Be(native.Symbol(newName));
                native.DefinitionName(oldName).Should().Be(newName);
            }

            native.HasSymbol("ReservedWords_NOT_A_NAME").Should().BeFalse();
            Action neither = () => native.Symbol("ReservedWords_NOT_A_NAME");
            neither.Should().Throw<KeyNotFoundException>();

            // A standalone build of the module, as the comparisons assemble it, finds the dependency by either name.
            Dictionary<string, long> predefined = BasicNames.WithCurrentNames(new Dictionary<string, long>
            {
                [OldName] = native.Symbol(OldName),
                [MacroOldName] = native.Symbol(MacroOldName)
            });

            Dictionary<string, long> renamed = [];
            BasicNames.WithInputs(scratch, () => renamed = BasicNames.WithCurrentNames(predefined));
            foreach ((string oldName, string newName, _, _) in s_renames)
            {
                renamed.Should().ContainKeys(oldName, newName);
                renamed[newName].Should().Be(renamed[oldName]);
            }
        }
        finally
        {
            Directory.Delete(scratch, recursive: true);
        }
    }

    /// <summary>
    ///  The BASIC tests look names up only through <see cref="BasicNames"/>, and every test source that assembles
    ///  BASIC is either run against the renamed copy or listed with its reason.
    /// </summary>
    [TestMethod]
    public void BasicTestsLookNamesUpThroughTheSharedHelper()
    {
        string tests = Path.Join(RepositoryRoot(), "tests", "Retrocore.Tests");
        HashSet<string> renamed = [.. s_renamed.Select(type => $"{type.Name}.cs")];
        foreach (string file in renamed)
        {
            File.Exists(Path.Join(tests, file)).Should().BeTrue($"{file} must hold its class");

            // A class that found its sources itself would run against the unrenamed ones.
            File.ReadAllText(Path.Join(tests, file)).Should().NotContain(
                "AppContext.BaseDirectory", $"{file} must read its sources from BasicNames.Inputs");
        }

        // A source that assembles BASIC must be in one of the lists, so a new one is not silently left out.
        foreach (string path in Directory.GetFiles(tests, "*.cs"))
        {
            string file = Path.GetFileName(path);
            if (!AssemblesBasic().IsMatch(File.ReadAllText(path))) { continue; }
            (renamed.Contains(file) || s_notRenamed.ContainsKey(file) || s_helpers.Contains(file)).Should().BeTrue(
                $"{file} assembles BASIC, so it must run against the renamed copy or say why not");
        }

        List<string> raw = [];
        IEnumerable<string> checkedFiles = renamed
            .Concat(s_helpers)
            .Concat(s_notRenamed.Where(pair => pair.Value is "compares with the shipped SDK").Select(pair => pair.Key));

        foreach (string file in checkedFiles)
        {
            string text = File.ReadAllText(Path.Join(tests, file));
            raw.AddRange(SplitLookup().Matches(text).Select(match =>
                $"{file}:{text[..match.Index].Count(character => character == '\n') + 1}: {match.Value.Trim()}"));

            // Predefining symbols as given, without their current names, is for the test of the roots' guard alone.
            if (file != "BasicNativeRootSwitchTests.cs" && text.Contains("BasicNames.AsGiven(", StringComparison.Ordinal))
            {
                raw.Add($"{file}: BasicNames.AsGiven");
            }

            string[] lines = text.Split('\n');
            for (int line = 0; line < lines.Length; line++)
            {
                if (RawLookup().IsMatch(lines[line]))
                {
                    raw.Add($"{file}:{line + 1}: {lines[line].Trim()}");
                }
            }
        }

        raw.Should().BeEmpty(
            $"a lookup by name must find a renamed definition by its old name too (BasicNames):{Environment.NewLine}{string.Join(Environment.NewLine, raw)}");
    }

    // Copies the inputs, renaming the labels in the native BASIC sources and giving each its old name in an Also:
    // section; Microsoft's MACRO-10 sources keep the names. Returns how many native files each rename changed.
    private static Dictionary<string, int> CopyRenamed(string inputs, string scratch)
    {
        foreach (string directory in Directory.GetDirectories(inputs, "*", SearchOption.AllDirectories))
        {
            Directory.CreateDirectory(Path.Join(scratch, Path.GetRelativePath(inputs, directory)));
        }

        Dictionary<string, int> changed = s_renames.ToDictionary(rename => rename.Old, _ => 0, StringComparer.Ordinal);
        foreach (string path in Directory.GetFiles(inputs, "*", SearchOption.AllDirectories))
        {
            string relative = Path.GetRelativePath(inputs, path);
            string target = Path.Join(scratch, relative);
            if (!IsNativeBasic(relative))
            {
                File.Copy(path, target);
                continue;
            }

            string text = File.ReadAllText(path);
            string replaced = text;
            foreach ((string oldName, string newName, string[] files, Regex word) in s_renames)
            {
                string before = replaced;
                replaced = word.Replace(replaced, newName);
                if (!string.Equals(replaced, before, StringComparison.Ordinal)) { changed[oldName]++; }
                string file = Path.GetFileName(path);
                if (!files.Contains(file)) { continue; }

                // The definition's documentation ends on the line before it.
                int at = replaced.IndexOf($"\n{newName}:", StringComparison.Ordinal);
                at.Should().BeGreaterThan(0, $"{file} defines {oldName}");
                string newLine = replaced.Contains("\r\n", StringComparison.Ordinal) ? "\r\n" : "\n";
                replaced = replaced.Insert(at + 1, $";; Also: {oldName} (M6502){newLine}");
            }

            File.WriteAllText(target, replaced);
        }

        return changed;
    }

    // The native sources of the shared modules, AppleSoft and PET BASIC; not Microsoft's m6502.asm or the overlays.
    private static bool IsNativeBasic(string relative)
    {
        string first = relative.Split(Path.DirectorySeparatorChar, Path.AltDirectorySeparatorChar)[0];
        return first is "Microsoft6502Basic" or "AppleSoft" or "Pet"
            && Path.GetExtension(relative).Equals(".asm", StringComparison.OrdinalIgnoreCase)
            && !Path.GetFileName(relative).Equals("m6502.asm", StringComparison.OrdinalIgnoreCase);
    }

    // The renamed copy defines the new names, reaches each by its old one, and builds every ROM byte for byte.
    private static void CheckRename(string inputs, string scratch)
    {
        Apple2Model[] models = [Apple2Model.IIPlus, Apple2Model.IIe, Apple2Model.IIeEnhanced];
        foreach (Apple2Model model in models)
        {
            AssemblyResult before = SdkModules.AssembleAppleSoft(SdkModules.AppleSoftPath(inputs), model);
            AssemblyResult after = SdkModules.AssembleAppleSoft(SdkModules.AppleSoftPath(scratch), model);
            CheckRename(before, after, $"AppleSoft {model}");
            SdkModules.AppleSoftImage(after).ToArray().Should().Equal(SdkModules.AppleSoftImage(before).ToArray());
        }

        (PetModel Model, bool Original)[] pets =
        [
            (PetModel.Pet2001, false), (PetModel.Pet2001, true), (PetModel.Pet2001Basic2, false),
            (PetModel.Pet4032, false), (PetModel.Pet4032, true)
        ];

        foreach ((PetModel model, bool original) in pets)
        {
            AssemblyResult before = PetSdkModules.AssembleBasic(Path.Join(inputs, "Pet"), model, original);
            AssemblyResult after = PetSdkModules.AssembleBasic(Path.Join(scratch, "Pet"), model, original);
            CheckRename(before, after, $"PET {model}{(original ? " original" : "")}");
            PetSdkModules.BasicImage(after, model).ToArray().Should().Equal(PetSdkModules.BasicImage(before, model).ToArray());
        }
    }

    private static void CheckRename(AssemblyResult before, AssemblyResult after, string build)
    {
        after.Success.Should().BeTrue($"{build} must assemble after the rename");
        foreach ((string oldName, string newName, _, _) in s_renames)
        {
            before.Symbols.Should().ContainKey(oldName);
            after.Symbols.Should().NotContainKey(oldName, $"{build} must no longer define {oldName}");
            after.Symbols[newName].Should().Be(before.Symbols[oldName], $"{build} must keep {newName} where {oldName} was");
            after.HistoricalNames[oldName].Name.Should().Be(newName, $"{build} must resolve {oldName} through its Also:");
        }

        after.Sections.Select(section => section.Bytes.ToArray()).Should().BeEquivalentTo(
            before.Sections.Select(section => section.Bytes.ToArray()),
            options => options.WithStrictOrdering(),
            $"{build} must stay byte-identical");
    }

    // Each test method of a class, with each of its data rows.
    private static IEnumerable<(Type Type, MethodInfo Method, object?[] Data)> Cases(Type type)
    {
        foreach (MethodInfo method in type.GetMethods(BindingFlags.Public | BindingFlags.Instance))
        {
            if (method.GetCustomAttribute<TestMethodAttribute>() is null) { continue; }
            DataRowAttribute[] rows = [.. method.GetCustomAttributes<DataRowAttribute>()];
            if (rows.Length == 0)
            {
                yield return (type, method, []);
                continue;
            }

            foreach (DataRowAttribute row in rows) { yield return (type, method, row.Data); }
        }
    }

    // Runs one case as MSTest would, on a new instance: null when it passes, else whether it was inconclusive and why.
    private static (bool Inconclusive, string Message)? Run((Type Type, MethodInfo Method, object?[] Data) testCase)
    {
        try
        {
            object instance = Activator.CreateInstance(testCase.Type)
                ?? throw new InvalidOperationException($"{testCase.Type.Name} has no instance.");

            object? result = testCase.Method.Invoke(instance, Arguments(testCase.Method, testCase.Data));
            if (result is Task task) { task.GetAwaiter().GetResult(); }
            return null;
        }
        catch (Exception exception)
        {
            Exception inner = (exception as TargetInvocationException)?.InnerException ?? exception;
            return (inner is AssertInconclusiveException, inner.Message);
        }
    }

    private static string Name((Type Type, MethodInfo Method, object?[] Data) testCase) =>
        $"{testCase.Type.Name}.{testCase.Method.Name}({string.Join(", ", testCase.Data)})";

    private static object?[] Arguments(MethodInfo method, object?[] data)
    {
        ParameterInfo[] parameters = method.GetParameters();
        object?[] arguments = new object?[parameters.Length];
        for (int index = 0; index < parameters.Length; index++)
        {
            Type type = parameters[index].ParameterType;
            object? value = index < data.Length ? data[index] : parameters[index].DefaultValue;
            arguments[index] = value is null || type.IsInstanceOfType(value)
                ? value
                : type.IsEnum ? Enum.ToObject(type, value) : Convert.ChangeType(value, type, System.Globalization.CultureInfo.InvariantCulture);
        }

        return arguments;
    }

    private static string RepositoryRoot()
    {
        string? root = AppContext.BaseDirectory;
        while (root is not null && !File.Exists(Path.Join(root, "Retrocore.slnx")))
        {
            root = Path.GetDirectoryName(root);
        }

        return root ?? throw new InvalidOperationException("The repository root was not found.");
    }

    // A source that assembles the native or MACRO-10 BASIC, or one of its shared modules.
    [GeneratedRegex(@"AssembleAppleSoft|AppleSoftPath|PetSdkModules\.AssembleBasic|Vic20SdkModules\.AssembleBasic|PetLegacyBasic\.Assemble|Microsoft6502Basic|BasicMachines\.AppleSoft")]
    private static partial Regex AssemblesBasic();

    // The renamed label, as a whole word.
    [GeneratedRegex($@"\b{OldName}\b")]
    private static partial Regex OldNameWord();

    // The renamed macro label, as a whole word.
    [GeneratedRegex($@"\b{MacroOldName}\b")]
    private static partial Regex MacroOldNameWord();

    // A lookup by name that does not reach a renamed definition by its old name.
    // A documentation lookup is one unless it is on a program's variables, on a language analysis, which finds an
    // Also: name itself, or on the bibliography, which looks up a document's key. So are an assembly's symbol table
    // handed on whole, a label a test's source defines by one of Microsoft's names, and a definition's name compared
    // with a literal one.
    [GeneratedRegex(@"\.Symbols(\[|\.(TryGetValue|ContainsKey|Should|GetValueOrDefault)\(|;)|SymbolDefinitions\.(Single|First|SingleOrDefault|FirstOrDefault|ToDictionary)\(|(?<!\b(variables|initial|Bibliography))\.Find(Routine)?\(|PredefinedSymbols = (?!BasicNames\.(WithCurrentNames|AsGiven)\()|^\s*[A-Z][A-Z0-9]{1,5}:\s*$|""[A-Z][A-Z0-9]{1,5}:""|Name\.Should\(\)\.Be\(""|EntryLabels\.Should\(\)\.Contain\(""")]
    private static partial Regex RawLookup();

    // The same lookups with the symbol table on one line and the lookup on the next.
    [GeneratedRegex(@"\.Symbols\s*\n\s*\.(TryGetValue|ContainsKey|Should|GetValueOrDefault)\(")]
    private static partial Regex SplitLookup();

}
