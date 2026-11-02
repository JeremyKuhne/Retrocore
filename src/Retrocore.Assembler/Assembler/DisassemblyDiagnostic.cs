// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Assembler;

/// <summary>
///  An analysis conflict or an incomplete instruction, retaining its image address.
/// </summary>
public sealed class DisassemblyDiagnostic
{
    /// <summary>
    ///  Creates an addressed diagnostic.
    /// </summary>
    /// <param name="code">The stable diagnostic family.</param>
    /// <param name="address">The affected address.</param>
    /// <param name="message">The actionable explanation.</param>
    /// <param name="isError">Whether invalid project input prevents successful analysis/export.</param>
    internal DisassemblyDiagnostic(string code, ushort address, string message, bool isError = false)
    {
        Code = code;
        Address = address;
        Message = message;
        IsError = isError;
    }

    /// <summary>
    ///  Gets a stable diagnostic family.
    /// </summary>
    public string Code { get; }

    /// <summary>
    ///  Gets the affected image address.
    /// </summary>
    public ushort Address { get; }

    /// <summary>
    ///  Gets the actionable explanation.
    /// </summary>
    public string Message { get; }

    /// <summary>
    ///  Gets whether invalid input prevents successful analysis/export.
    /// </summary>
    public bool IsError { get; }
}
