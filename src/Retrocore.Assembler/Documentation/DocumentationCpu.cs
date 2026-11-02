// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Isa;

namespace Retrocore.Documentation;

/// <summary>
///  The registers and flags documentation may name for one CPU, from its instruction-set description. Registers
///  are named by the CPU's own letters; flags only by words that are the same on every CPU, such as
///  <c>carry</c>, so a flag never reads as a register.
/// </summary>
public sealed class DocumentationCpu
{
    private static readonly Dictionary<IsaDescription, DocumentationCpu> s_cpus = [];

    private readonly Dictionary<string, IsaFlag> _words = new(StringComparer.OrdinalIgnoreCase);
    private readonly HashSet<string> _registers = new(StringComparer.OrdinalIgnoreCase);
    private readonly bool _alternates;

    private DocumentationCpu(IsaDescription description)
    {
        foreach (IsaRegister register in description.Registers)
        {
            _registers.Add(register.Name);
            _alternates |= register.Name.EndsWith('\'');
        }

        foreach (IsaFlag flag in description.Flags)
        {
            foreach (string word in flag.Words) { _words[word] = flag; }
        }

        Flags = description.Flags;
    }

    /// <summary>
    ///  Gets the CPU's flags.
    /// </summary>
    public IReadOnlyList<IsaFlag> Flags { get; }

    /// <summary>
    ///  Gets the documentation names for a CPU.
    /// </summary>
    /// <param name="description">The CPU's instruction-set description.</param>
    /// <returns>Its names.</returns>
    public static DocumentationCpu For(IsaDescription description)
    {
        lock (s_cpus)
        {
            if (!s_cpus.TryGetValue(description, out DocumentationCpu? cpu))
            {
                s_cpus[description] = cpu = new DocumentationCpu(description);
            }

            return cpu;
        }
    }

    /// <summary>
    ///  Gets whether a name is one of the CPU's registers, including the Z80's alternate registers run
    ///  together, as in <c>C'H'L'</c>.
    /// </summary>
    /// <param name="name">The name.</param>
    /// <returns>Whether it names registers.</returns>
    public bool IsRegister(string name)
    {
        if (_registers.Contains(name)) { return true; }
        if (!_alternates || !name.EndsWith('\'')) { return false; }
        foreach (string part in name.Split(['\''], StringSplitOptions.RemoveEmptyEntries))
        {
            if (!_registers.Contains(part)) { return false; }
        }

        return true;
    }

    /// <summary>
    ///  Gets the flag a word names, such as <c>carry</c>.
    /// </summary>
    /// <param name="word">The word.</param>
    /// <returns>The flag, or null when the word names none of the CPU's flags.</returns>
    public IsaFlag? Flag(string word) => _words.TryGetValue(word, out IsaFlag? flag) ? flag : null;

    /// <summary>
    ///  Gets the flag a letter names in the CPU's manuals, such as <c>C</c>, for a warning that suggests its word.
    /// </summary>
    /// <param name="letter">The letter.</param>
    /// <returns>The flag, or null when the letter names none with a word.</returns>
    public IsaFlag? FlagByLetter(string letter)
    {
        foreach (IsaFlag flag in Flags)
        {
            if (flag.Words.Count != 0 && string.Equals(flag.Name, letter, StringComparison.OrdinalIgnoreCase))
            {
                return flag;
            }
        }

        return null;
    }

    /// <summary>
    ///  Describes a flag as hover text shows it: <c>negative (N) flag: what it means</c>.
    /// </summary>
    /// <param name="word">The word the documentation used.</param>
    /// <param name="flag">The flag.</param>
    /// <returns>The description, in Markdown.</returns>
    public static string Describe(string word, IsaFlag flag) =>
        $"**{word.ToLowerInvariant()} ({flag.Name}) flag**: {flag.Description}";
}
