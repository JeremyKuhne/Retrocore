// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Media.Commodore;

/// <summary>
///  A DOS 2 file's type, as its directory entry's low three bits hold it and a listing shows it.
/// </summary>
public enum CbmDosFileType
{
    /// <summary>
    ///  <c>DEL</c>: a deleted file, or an entry not in use when the whole byte is zero.
    /// </summary>
    Deleted = 0,

    /// <summary>
    ///  <c>SEQ</c>: a sequential file.
    /// </summary>
    Sequential = 1,

    /// <summary>
    ///  <c>PRG</c>: a program file, which starts with its load address.
    /// </summary>
    Program = 2,

    /// <summary>
    ///  <c>USR</c>: a user file, laid out as a sequential one.
    /// </summary>
    User = 3,

    /// <summary>
    ///  <c>REL</c>: a relative file, of fixed-length records.
    /// </summary>
    Relative = 4
}
