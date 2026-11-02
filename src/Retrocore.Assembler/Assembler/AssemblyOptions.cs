// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Cpu.M6502;

namespace Retrocore.Assembler;

/// <summary>
///  Immutable CPU and fixed-image options; no Roslyn or generated C# type metadata is required.
/// </summary>
public sealed class AssemblyOptions
{
    private AssemblyWidthPolicy _widthPolicy;
    private AssemblyDialect _dialect;
    private string _outputFile = "output.bin";
    private IReadOnlyList<string> _includePaths = [];
    private IReadOnlyList<string> _sdkPaths = [];
    private IReadOnlyDictionary<string, long> _predefined = new Dictionary<string, long>(StringComparer.Ordinal);
    private int _maximumIncludeDepth = 32;
    private int _maximumMacroDepth = 64;
    private int _maximumRepeatCount = 1_000_000;
    private int _maximumExpandedLines = 1_000_000;

    /// <summary>
    ///  Creates a bounded, zero-padded output region.
    /// </summary>
    /// <param name="variant">An existing CPU variant.</param>
    /// <param name="origin">The load address.</param>
    /// <param name="imageSize">The full output size.</param>
    public AssemblyOptions(ProcessorVariant variant, int origin, int imageSize)
        : this(VariantName(variant), origin, imageSize)
    {
    }

    /// <summary>
    ///  Creates options for a CPU named as <c>.cpu</c> names it.
    /// </summary>
    /// <param name="cpu">The CPU, such as <c>Mos6502</c>, <c>65SC02</c> or <c>Z80</c>.</param>
    /// <param name="origin">The address of the first image byte.</param>
    /// <param name="imageSize">The image size in bytes.</param>
    /// <exception cref="ArgumentException"><paramref name="cpu"/> is empty.</exception>
    /// <exception cref="ArgumentOutOfRangeException">The origin or size is outside the address space.</exception>
    public AssemblyOptions(string cpu, int origin, int imageSize)
    {
        // The generator's .NET Standard 2.0 lacks ArgumentException.ThrowIfNullOrWhiteSpace.
        if (string.IsNullOrWhiteSpace(cpu)) { throw new ArgumentException("A CPU name is required.", nameof(cpu)); }
        if (origin < 0 || origin > ushort.MaxValue) { throw new ArgumentOutOfRangeException(nameof(origin)); }
        if (imageSize <= 0 || imageSize > InstructionEncoding.AddressSpaceSize - origin)
        {
            throw new ArgumentOutOfRangeException(nameof(imageSize));
        }

        Cpu = cpu;
        Origin = origin;
        ImageSize = imageSize;
    }

    /// <summary>
    ///  Gets the CPU in effect before any <c>.cpu</c>, by the name <c>.cpu</c> selects it with.
    /// </summary>
    public string Cpu { get; }

    /// <summary>
    ///  Gets the 6502 family variant the options name.
    /// </summary>
    /// <exception cref="InvalidOperationException"><see cref="Cpu"/> is not a 6502 variant.</exception>
    public ProcessorVariant Variant =>
        Enum.TryParse(Cpu, ignoreCase: true, out ProcessorVariant variant) && Enum.IsDefined(variant)
            ? variant
            : throw new InvalidOperationException($"The CPU '{Cpu}' is not a 6502 variant.");

    private static string VariantName(ProcessorVariant variant) =>
        Enum.IsDefined(variant) ? variant.ToString() : throw new ArgumentOutOfRangeException(nameof(variant));

    /// <summary>
    ///  Gets the fixed image origin.
    /// </summary>
    public int Origin { get; }

    /// <summary>
    ///  Gets the full padded image size.
    /// </summary>
    public int ImageSize { get; }

    /// <summary>
    ///  Gets the default address-width policy. Native sources shrink unless explicitly overridden.
    /// </summary>
    public AssemblyWidthPolicy WidthPolicy
    {
        get => _widthPolicy;
        init
        {
            if (!Enum.IsDefined(value)) { throw new ArgumentOutOfRangeException(nameof(value)); }
            _widthPolicy = value;
        }
    }

    /// <summary>
    ///  Gets the build timestamp shared by every source in this assembly. Set it for reproducible output; the source
    ///  generator uses RetrocoreBuildTime or SOURCE_DATE_EPOCH, otherwise the Unix epoch.
    /// </summary>
    public DateTimeOffset BuildTime { get; init; } = DateTimeOffset.UtcNow;

    /// <summary>
    ///  Gets an optional single-object ld65 MEMORY/SEGMENTS configuration. ca65 defaults to the none target.
    /// </summary>
    public AssemblySource? LinkerConfiguration { get; init; }

    /// <summary>
    ///  Gets the in-memory output filename substituted for %O. Assembly never writes output files itself.
    /// </summary>
    public string OutputFile
    {
        get => _outputFile;
        init => _outputFile = value ?? throw new ArgumentNullException(nameof(value));
    }

    /// <summary>
    ///  Gets the inherited dialect, overridden by a source's first-line pragma or resolver metadata.
    /// </summary>
    public AssemblyDialect Dialect
    {
        get => _dialect;
        init
        {
            if (!Enum.IsDefined(value)) { throw new ArgumentOutOfRangeException(nameof(value)); }
            _dialect = value;
        }
    }

    /// <summary>
    ///  Gets the explicit include resolver. No filesystem reads occur without a resolver.
    /// </summary>
    public IAssemblySourceResolver? SourceResolver { get; init; }

    /// <summary>
    ///  Gets quoted-include search paths, tried after the including document's directory.
    /// </summary>
    public IReadOnlyList<string> IncludePaths
    {
        get => _includePaths;
        init => _includePaths = CopyPaths(value);
    }

    /// <summary>
    ///  Gets symbols defined before any source is read, such as a build variant switch.
    /// </summary>
    /// <remarks>
    ///  <para>
    ///   Each becomes a constant every dialect can reference. MACRO-10 conditionals, including <c>IFDEF</c>, also
    ///   see them, so a source can default a switch with <c>IFNDEF NAME,&lt;NAME==1&gt;</c> that a build overrides.
    ///  </para>
    /// </remarks>
    public IReadOnlyDictionary<string, long> PredefinedSymbols
    {
        get => _predefined;
        init => _predefined = (value ?? throw new ArgumentNullException(nameof(value))).ToDictionary(
            pair => pair.Key,
            pair => pair.Value,
            StringComparer.Ordinal);
    }

    /// <summary>
    ///  Gets SDK search paths, the only paths searched by angle-bracket includes.
    /// </summary>
    public IReadOnlyList<string> SdkPaths
    {
        get => _sdkPaths;
        init => _sdkPaths = CopyPaths(value);
    }

    /// <summary>
    ///  Gets the maximum include nesting, counting the root document as depth one.
    /// </summary>
    public int MaximumIncludeDepth
    {
        get => _maximumIncludeDepth;
        init => _maximumIncludeDepth = Positive(value);
    }

    /// <summary>
    ///  Gets the maximum nested macro calls.
    /// </summary>
    public int MaximumMacroDepth
    {
        get => _maximumMacroDepth;
        init => _maximumMacroDepth = Positive(value);
    }

    /// <summary>
    ///  Gets the maximum count accepted by one .repeat.
    /// </summary>
    public int MaximumRepeatCount
    {
        get => _maximumRepeatCount;
        init => _maximumRepeatCount = Positive(value);
    }

    /// <summary>
    ///  Gets the total line-visit budget across source, includes, repeats and macro calls.
    /// </summary>
    public int MaximumExpandedLines
    {
        get => _maximumExpandedLines;
        init => _maximumExpandedLines = Positive(value);
    }

    private static int Positive(int value) => value > 0 ? value : throw new ArgumentOutOfRangeException(nameof(value));

    private static System.Collections.ObjectModel.ReadOnlyCollection<string> CopyPaths(IReadOnlyList<string> paths)
    {
        ArgumentNullException.ThrowIfNull(paths);
        string[] copy = new string[paths.Count];
        for (int index = 0; index < copy.Length; index++)
        {
            string path = paths[index];
            if (string.IsNullOrWhiteSpace(path))
            {
                throw new ArgumentException("Include paths cannot be empty.", nameof(paths));
            }

            copy[index] = path;
        }

        return Array.AsReadOnly(copy);
    }
}
