// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using System.Globalization;

namespace Retrocore.Media.Acorn;

/// <summary>
///  A file for an Acorn cassette: its name, load and execution addresses, contents and lock, as an archive keeps it
///  in a data file beside an <c>.inf</c> file.
/// </summary>
/// <param name="Name">The name: 1-10 characters, none of them a zero.</param>
/// <param name="LoadAddress">Where it loads.</param>
/// <param name="ExecutionAddress">Where *RUN starts it.</param>
/// <param name="Data">Its contents.</param>
/// <param name="Locked">Whether it is protected, so it can only be *RUN.</param>
public sealed record AcornTapeFile(
    string Name,
    uint LoadAddress,
    uint ExecutionAddress,
    byte[] Data,
    bool Locked = false)
{
    /// <summary>
    ///  Reads a file's <c>.inf</c> description and contents: the name, then the load and execution addresses in hex,
    ///  then optionally the length in hex and <c>L</c> or <c>Locked</c>. A name with a directory, as <c>$.NAME</c>,
    ///  keeps only the part after the dot.
    /// </summary>
    /// <param name="inf">The <c>.inf</c> file's text.</param>
    /// <param name="data">The data file's bytes.</param>
    /// <returns>The file.</returns>
    /// <exception cref="InvalidDataException">The text is not an <c>.inf</c> description.</exception>
    public static AcornTapeFile FromInf(string inf, byte[] data)
    {
        ArgumentNullException.ThrowIfNull(inf);
        ArgumentNullException.ThrowIfNull(data);
        string[] fields = inf.Split(separator: (char[]?)null, StringSplitOptions.RemoveEmptyEntries);
        if (fields.Length < 3
            || !uint.TryParse(fields[1], NumberStyles.HexNumber, CultureInfo.InvariantCulture, out uint load)
            || !uint.TryParse(fields[2], NumberStyles.HexNumber, CultureInfo.InvariantCulture, out uint execute))
        {
            throw new InvalidDataException("An .inf file starts with a name, a load address and an execution address.");
        }

        string name = fields[0];
        if (name.Length > 2 && name[1] == '.') { name = name[2..]; }
        bool locked = fields.Skip(3).Any(field => field.Equals("L", StringComparison.OrdinalIgnoreCase)
            || field.Equals("Locked", StringComparison.OrdinalIgnoreCase));

        return new(name.Length > 10 ? name[..10] : name, load, execute, data, locked);
    }
}
