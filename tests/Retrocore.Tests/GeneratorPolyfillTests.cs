// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

extern alias Generator;

using System.Runtime.InteropServices;
using Retrocore.Assembler;
using GeneratorChar = Generator::System.CharExtensions;
using GeneratorDictionary = Generator::System.Collections.Generic.DictionaryExtensions;
using GeneratorEnum = Generator::System.EnumExtensions;
using GeneratorMemory = Generator::System.MemoryExtensionsPolyfills;

namespace Retrocore.Tests;

/// <summary>
///  Checks that generator-only API polyfills match .NET 10 without entering the product assembly.
/// </summary>
[TestClass]
public class GeneratorPolyfillTests
{
    /// <summary>
    ///  Checks all trim variants retain the same owner, slice offset and whitespace semantics as .NET 10.
    /// </summary>
    /// <param name="text">The original memory slice.</param>
    [TestMethod]
    [DataRow("")]
    [DataRow(" \t\r\n")]
    [DataRow("value")]
    [DataRow(" \tvalue \r\n")]
    [DataRow("\u00A0\u2003value\u2003\u00A0")]
    [DataRow("  a b  ")]
    [DataRow("' '")]
    public void MemoryTrimmingMatchesModernDotNet(string text)
    {
        string original = "[" + text + "]";
        ReadOnlyMemory<char> memory = original.AsMemory(1, text.Length);
        AssertSameSlice(GeneratorMemory.Trim(memory), memory.Trim());
        AssertSameSlice(GeneratorMemory.TrimStart(memory), memory.TrimStart());
        AssertSameSlice(GeneratorMemory.TrimEnd(memory), memory.TrimEnd());
        ReadOnlyMemory<char> empty = default;
        AssertSameSlice(GeneratorMemory.Trim(empty), empty.Trim());
        AssertSameSlice(GeneratorMemory.TrimStart(empty), empty.TrimStart());
        AssertSameSlice(GeneratorMemory.TrimEnd(empty), empty.TrimEnd());
    }

    /// <summary>
    ///  Checks generator character classifications match the native APIs for every UTF-16 code unit.
    /// </summary>
    [TestMethod]
    public void AsciiPredicatesMatchModernDotNet()
    {
        for (int code = char.MinValue; code <= char.MaxValue; code++)
        {
            char value = (char)code;
            GeneratorChar.IsAsciiLetter(value).Should().Be(char.IsAsciiLetter(value));
            GeneratorChar.IsAsciiDigit(value).Should().Be(char.IsAsciiDigit(value));
            GeneratorChar.IsAsciiLetterOrDigit(value).Should().Be(char.IsAsciiLetterOrDigit(value));
            GeneratorChar.IsAsciiHexDigit(value).Should().Be(char.IsAsciiHexDigit(value));
        }
    }

    /// <summary>
    ///  Checks duplicate insertion respects custom comparers and never overwrites an existing value.
    /// </summary>
    [TestMethod]
    public void DictionaryInsertionMatchesModernDotNet()
    {
        Dictionary<string, int> legacy = new(StringComparer.OrdinalIgnoreCase);
        Dictionary<string, int> modern = new(StringComparer.OrdinalIgnoreCase);
        (string Name, int Value)[] entries = [("Entry", 1), ("entry", 2), ("Other", 3)];
        foreach ((string name, int value) in entries)
        {
            GeneratorDictionary.TryAdd(legacy, name, value).Should().Be(modern.TryAdd(name, value));
        }

        legacy.Should().BeEquivalentTo(modern);
        legacy["ENTRY"].Should().Be(1);
#pragma warning disable CS8625 // Exercise the underlying dictionary's null-key validation.
        Action invalidLegacyKey = () => GeneratorDictionary.TryAdd<string, int>(legacy, key: null, value: 0);
        Action invalidModernKey = () => modern.TryAdd(key: null, value: 0);
#pragma warning restore CS8625
        invalidLegacyKey.Should().Throw<ArgumentNullException>().WithParameterName("key");
        invalidModernKey.Should().Throw<ArgumentNullException>().WithParameterName("key");
    }

    /// <summary>
    ///  Checks generic enum validation handles declared, undefined, negative and combined flag values.
    /// </summary>
    [TestMethod]
    public void EnumDefinitionMatchesModernDotNet()
    {
        for (int value = byte.MinValue; value <= byte.MaxValue; value++)
        {
            ProcessorVariant variant = (ProcessorVariant)value;
            GeneratorEnum.IsDefined(variant).Should().Be(Enum.IsDefined(variant));
        }

        GeneratorEnum.IsDefined(DayOfWeek.Sunday).Should().BeTrue();
        GeneratorEnum.IsDefined((DayOfWeek)(-1)).Should().BeFalse();
        GeneratorEnum.IsDefined(FileAttributes.ReadOnly).Should().BeTrue();
        FileAttributes combined = FileAttributes.ReadOnly | FileAttributes.Hidden;
        GeneratorEnum.IsDefined(combined).Should().Be(Enum.IsDefined(combined));
    }

    /// <summary>
    ///  Checks compatibility implementation types belong only to the generator, not the AOT product.
    /// </summary>
    [TestMethod]
    public void ProductAssemblyContainsNoGeneratorPolyfills()
    {
        string[] names =
        [
            "System.MemoryExtensionsPolyfills",
            "System.CharExtensions",
            "System.EnumExtensions",
            "System.Collections.Generic.DictionaryExtensions",
            "System.ArgumentNullExtensions"
        ];

        foreach (string name in names)
        {
            typeof(AssemblySource).Assembly.GetType(name).Should().BeNull();
            typeof(GeneratorMemory).Assembly.GetType(name).Should().NotBeNull();
        }
    }

    /// <summary>
    ///  Checks complete slice identity, not only equal resulting characters.
    /// </summary>
    /// <param name="actual">The generator polyfill result.</param>
    /// <param name="expected">The .NET 10 result.</param>
    private static void AssertSameSlice(ReadOnlyMemory<char> actual, ReadOnlyMemory<char> expected)
    {
        actual.Equals(expected).Should().BeTrue();
        MemoryMarshal.TryGetString(actual, out string? actualOwner, out int actualStart, out int actualLength)
            .Should().Be(MemoryMarshal.TryGetString(expected, out string? expectedOwner, out int expectedStart, out int expectedLength));

        actualOwner.Should().BeSameAs(expectedOwner);
        actualStart.Should().Be(expectedStart);
        actualLength.Should().Be(expectedLength);
    }
}
