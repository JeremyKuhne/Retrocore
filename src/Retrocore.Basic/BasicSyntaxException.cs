// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Basic;

/// <summary>
///  A line the interpreter refuses as it is typed, as Integer BASIC does a line its grammar does not allow.
/// </summary>
public sealed class BasicSyntaxException : FormatException
{
    /// <summary>
    ///  Creates the exception.
    /// </summary>
    /// <param name="message">What the interpreter says.</param>
    /// <param name="column">The column of the statements' text where the interpreter stopped.</param>
    public BasicSyntaxException(string message, int column)
        : base(message)
    {
        Column = column;
    }

    /// <summary>
    ///  Creates the exception.
    /// </summary>
    public BasicSyntaxException()
    {
    }

    /// <summary>
    ///  Creates the exception.
    /// </summary>
    /// <param name="message">What the interpreter says.</param>
    public BasicSyntaxException(string message)
        : base(message)
    {
    }

    /// <summary>
    ///  Creates the exception.
    /// </summary>
    /// <param name="message">What the interpreter says.</param>
    /// <param name="innerException">The cause.</param>
    public BasicSyntaxException(string message, Exception innerException)
        : base(message, innerException)
    {
    }

    /// <summary>
    ///  Gets the column of the statements' text where the interpreter stopped, from 0.
    /// </summary>
    public int Column { get; }
}
