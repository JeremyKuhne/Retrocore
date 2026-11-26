// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Media.Acorn;

/// <summary>
///  A file in an Acorn DFS catalogue: its directory and name, load and execution addresses, contents and lock.
/// </summary>
/// <remarks>
///  <para>
///   An address is 18 bits, <c>&amp;00000</c>-<c>&amp;2FFFF</c>, or <c>&amp;FFFF0000</c>-<c>&amp;FFFFFFFF</c> for the
///   I/O processor's memory: the catalogue keeps bits 16-17, and the DFS reads both set as <c>&amp;FFFF</c>.
///  </para>
/// </remarks>
/// <param name="Directory">The directory, one character, <c>$</c> by default.</param>
/// <param name="Name">The name: 1-7 printable characters, none of them a space or <c>. : " # *</c>.</param>
/// <param name="LoadAddress">Where it loads.</param>
/// <param name="ExecutionAddress">Where *RUN starts it.</param>
/// <param name="Data">Its contents, at most 262,143 bytes.</param>
/// <param name="Locked">Whether it is locked, so it cannot be deleted or written over.</param>
public sealed record AcornDfsFile(
    char Directory,
    string Name,
    uint LoadAddress,
    uint ExecutionAddress,
    byte[] Data,
    bool Locked = false)
{
    /// <summary>
    ///  The most characters a name holds.
    /// </summary>
    public const int MaximumNameLength = 7;

    /// <summary>
    ///  The longest file the catalogue records: an 18-bit length.
    /// </summary>
    public const int MaximumLength = 0x3FFFF;

    /// <summary>
    ///  Gets the name as <c>D.NAME</c>.
    /// </summary>
    public string FullName => $"{Directory}.{Name}";

    /// <summary>
    ///  Gets whether a character may be part of a DFS name or be a directory: printable ASCII, but not a space or
    ///  <c>. : " # *</c>, which the DFS reads as separators, quotes and wildcards.
    /// </summary>
    /// <param name="character">The character.</param>
    /// <returns>Whether it may.</returns>
    public static bool IsNameCharacter(char character) =>
        character is > ' ' and < (char)0x7F and not ('.' or ':' or '"' or '#' or '*');

    /// <summary>
    ///  Gets whether an address fits the catalogue: 18 bits, or the I/O processor's <c>&amp;FFFFxxxx</c>.
    /// </summary>
    /// <param name="address">The address.</param>
    /// <returns>Whether it does.</returns>
    public static bool IsCatalogueAddress(uint address) => address <= 0x2FFFF || (address >> 16) == 0xFFFF;

    /// <summary>
    ///  Checks the file can go in a catalogue.
    /// </summary>
    /// <exception cref="ArgumentException">
    ///  The directory, name, an address or the length is not one a DFS keeps.
    /// </exception>
    public void Validate()
    {
        ArgumentNullException.ThrowIfNull(Name);
        ArgumentNullException.ThrowIfNull(Data);
        if (!IsNameCharacter(Directory))
        {
            throw new ArgumentException(
                $"'{Directory}' is not a DFS directory: one printable character, not a space or . : \" # *.");
        }

        if (Name.Length is 0 or > MaximumNameLength || !Name.All(IsNameCharacter))
        {
            throw new ArgumentException(
                $"'{Name}' is not a DFS name: 1-7 printable characters, none of them a space or . : \" # *.");
        }

        if (!IsCatalogueAddress(LoadAddress))
        {
            throw new ArgumentException(
                $"{FullName}'s load address &{LoadAddress:X} is neither 18 bits nor &FFFFxxxx.");
        }

        if (!IsCatalogueAddress(ExecutionAddress))
        {
            throw new ArgumentException(
                $"{FullName}'s execution address &{ExecutionAddress:X} is neither 18 bits nor &FFFFxxxx.");
        }

        if (Data.Length > MaximumLength)
        {
            throw new ArgumentException(
                $"{FullName} is {Data.Length} bytes; a DFS file holds at most {MaximumLength}.");
        }
    }
}
