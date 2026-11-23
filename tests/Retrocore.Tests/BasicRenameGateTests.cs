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
    private const string OldName = "FNDLIN";
    private const string NewName = "FindLine";

    // The classes that assemble the native BASIC sources and look its names up, run against the renamed copy.
    private static readonly Type[] s_renamed =
    [
        typeof(AppleSoftTests), typeof(Basic1IndependentSwitchTests), typeof(BasicNativeRootSwitchTests),
        typeof(BasicSharedArrayMultiplicationTests), typeof(BasicSharedAssignmentTests),
        typeof(BasicSharedCharacterReaderTests), typeof(BasicSharedCommandInputTests), typeof(BasicSharedExpressionTests),
        typeof(BasicSharedForTests), typeof(BasicSharedGarbageCollectionTests), typeof(BasicSharedIntegerConversionTests),
        typeof(BasicSharedLineNumberTests), typeof(BasicSharedLineSearchTests), typeof(BasicSharedListerTests),
        typeof(BasicSharedMemoryAccessTests), typeof(BasicSharedMemoryManagementTests), typeof(BasicSharedNextTests),
        typeof(BasicSharedOperatorTableTests), typeof(BasicSharedPrintTests), typeof(BasicSharedProgramResetTests),
        typeof(BasicSharedProgramTransfersTests), typeof(BasicSharedSimpleFunctionsTests),
        typeof(BasicSharedStatementFlowTests), typeof(BasicSharedStringConcatenationTests),
        typeof(BasicSharedStringFunctionTests), typeof(BasicSharedStringStorageTests), typeof(BasicSharedUserFunctionsTests),
        typeof(BasicSharedVariableInputTests), typeof(BasicSharedVariableLookupTests), typeof(BasicTokenizerTests),
        typeof(BasicVariableTests), typeof(PetBasic4ExtensionTests), typeof(PetBasic4RevisionTests),
        typeof(PetBasicConformanceTests), typeof(PetNativeEquatesTests), typeof(PetRomSourceTests),
        typeof(PetSharedFloatAssemblyTests)
    ];

    // Test sources that assemble BASIC but are not run against the renamed copy, each for its reason. Their lookups
    // are checked as the others' are, except the files session B2 owns.
    private static readonly Dictionary<string, string> s_notRenamed = new(StringComparer.Ordinal)
    {
        // Compares the repository's copy with the SDK the host ships, which the renamed copy does not replace.
        ["BasicSharedSourceTests.cs"] = "compares with the shipped SDK",

        // Lint the sources, whose test-only Also: key is no bibliography entry.
        ["SdkDocumentationTests.cs"] = "lints the sources",

        // Assemble only byte images, Microsoft's base or resolver paths, and look no BASIC name up.
        ["Apple2SourceTests.cs"] = "looks no name up",
        ["LanguageAnalysisTests.cs"] = "looks no name up",
        ["OverlayBaseResolverTests.cs"] = "looks no name up",
        ["SystemMasterBasicTests.cs"] = "looks no name up",

        // Session B2's alias tests and attribution, which it converts with the sources' Also: sections.
        ["BasicSharedAliasConsistencyTests.cs"] = "owned by B2",
        ["BasicSharedFloatAliasesTests.cs"] = "owned by B2",
        ["BasicSharedInterpreterAliasesTests.cs"] = "owned by B2",
        ["BasicAttribution.cs"] = "owned by B2",

        // The lookups themselves and this gate.
        ["BasicNames.cs"] = "the lookups",
        ["BasicRenameGateTests.cs"] = "this gate"
    };

    // Helpers the renamed classes use, whose lookups are checked with theirs.
    private static readonly string[] s_helpers = ["BasicMachines.cs", "PetLegacyBasic.cs"];

    /// <summary>
    ///  Renaming <c>FNDLIN</c> to <c>FindLine</c> in a copy of the native sources, with <c>;; Also: FNDLIN</c>, keeps
    ///  every ROM's bytes and leaves every BASIC test green without changing it.
    /// </summary>
    [TestMethod]
    public void RenamingALabelLeavesTheTestsGreen()
    {
        string scratch = Directory.CreateTempSubdirectory("retrocore-rename").FullName;
        try
        {
            int renamed = CopyRenamed(BasicNames.Inputs, scratch);
            renamed.Should().BeGreaterThan(3, $"{OldName} is used across the shared, AppleSoft and PET sources");
            CheckRename(BasicNames.Inputs, scratch);

            ConcurrentBag<string> failures = [];
            ConcurrentBag<string> inconclusive = [];
            int run = 0;
            BasicNames.WithInputs(scratch, () => Parallel.ForEach(
                s_renamed.SelectMany(Cases),
                testCase =>
                {
                    Interlocked.Increment(ref run);
                    switch (Run(testCase))
                    {
                        case (false, string message): failures.Add($"{Name(testCase)}: {message}"); break;
                        case (true, string message): inconclusive.Add($"{Name(testCase)}: {message}"); break;
                    }
                }));

            failures.Should().BeEmpty(
                $"renaming {OldName} must not break a test; {run} ran, {inconclusive.Count} inconclusive:{Environment.NewLine}{string.Join(Environment.NewLine, failures)}");

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

            Action oldNameOnly = () => _ = native.Symbols[OldName];
            oldNameOnly.Should().Throw<KeyNotFoundException>("the renamed sources no longer define the old name");
            native.Symbol(OldName).Should().Be(native.Symbol(NewName));
            native.DefinitionName(OldName).Should().Be(NewName);
            native.HasSymbol("FNDLIN_NOT_A_NAME").Should().BeFalse();
            Action neither = () => native.Symbol("FNDLIN_NOT_A_NAME");
            neither.Should().Throw<KeyNotFoundException>();

            // A standalone build of the module, as the comparisons assemble it, finds the dependency by either name.
            Dictionary<string, long> predefined = BasicNames.WithCurrentNames(new Dictionary<string, long>
            {
                [OldName] = native.Symbol(OldName)
            });

            Dictionary<string, long> renamed = [];
            BasicNames.WithInputs(scratch, () => renamed = BasicNames.WithCurrentNames(predefined));
            renamed.Should().ContainKeys(OldName, NewName);
            renamed[NewName].Should().Be(renamed[OldName]);
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

    // Copies the inputs, renaming the label in the native BASIC sources and giving it its old name in an Also:
    // section; Microsoft's MACRO-10 sources keep the name. Returns how many native files changed.
    private static int CopyRenamed(string inputs, string scratch)
    {
        foreach (string directory in Directory.GetDirectories(inputs, "*", SearchOption.AllDirectories))
        {
            Directory.CreateDirectory(Path.Join(scratch, Path.GetRelativePath(inputs, directory)));
        }

        int changed = 0;
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
            string replaced = OldNameWord().Replace(text, NewName);
            if (Path.GetFileName(path) == "MsBasic.LineSearch.asm")
            {
                // The definition's documentation ends on the line before it.
                int at = replaced.IndexOf($"\n{NewName}:", StringComparison.Ordinal);
                at.Should().BeGreaterThan(0, $"MsBasic.LineSearch.asm defines {OldName}");
                string newLine = replaced.Contains("\r\n", StringComparison.Ordinal) ? "\r\n" : "\n";
                replaced = replaced.Insert(at + 1, $";; Also: {OldName} (TEST){newLine}");
            }

            if (!string.Equals(replaced, text, StringComparison.Ordinal)) { changed++; }
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

    // The renamed copy defines the new name, reaches it by the old one, and builds every ROM byte for byte.
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
        before.Symbols.Should().ContainKey(OldName);
        after.Symbols.Should().NotContainKey(OldName, $"{build} must no longer define {OldName}");
        after.Symbols[NewName].Should().Be(before.Symbols[OldName], $"{build} must keep {NewName} where {OldName} was");
        after.HistoricalNames[OldName].Name.Should().Be(NewName);
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
    [GeneratedRegex(@"AssembleAppleSoft|AppleSoftPath|PetSdkModules\.AssembleBasic|PetLegacyBasic\.Assemble|Microsoft6502Basic|BasicMachines\.AppleSoft")]
    private static partial Regex AssemblesBasic();

    // The renamed label, as a whole word.
    [GeneratedRegex($@"\b{OldName}\b")]
    private static partial Regex OldNameWord();

    // A lookup by name that does not reach a renamed definition by its old name.
    // A documentation lookup is one unless it is on a program's variables or on a language analysis, which finds an
    // Also: name itself. So are an assembly's symbol table handed on whole, a label a test's source defines by one of
    // Microsoft's names, and a definition's name compared with a literal one.
    [GeneratedRegex(@"\.Symbols(\[|\.(TryGetValue|ContainsKey|Should|GetValueOrDefault)\(|;)|SymbolDefinitions\.(Single|First|SingleOrDefault|FirstOrDefault|ToDictionary)\(|(?<!\b(variables|initial))\.Find(Routine)?\(|PredefinedSymbols = (?!BasicNames\.WithCurrentNames\()|^\s*[A-Z][A-Z0-9]{1,5}:\s*$|""[A-Z][A-Z0-9]{1,5}:""|Name\.Should\(\)\.Be\(""|EntryLabels\.Should\(\)\.Contain\(""")]
    private static partial Regex RawLookup();

    // The same lookups with the symbol table on one line and the lookup on the next.
    [GeneratedRegex(@"\.Symbols\s*\n\s*\.(TryGetValue|ContainsKey|Should|GetValueOrDefault)\(")]
    private static partial Regex SplitLookup();

}
