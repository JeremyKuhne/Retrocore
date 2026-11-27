// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Debug.Project;

/// <summary>
///  A <c>retrocore.json</c> that is malformed, or a target that cannot be built as it says.
/// </summary>
/// <remarks>
///  <para>
///   Its message says what is wrong, naming the file, so whatever reads the project can report it as it is.
///  </para>
/// </remarks>
internal sealed class ProjectException : Exception
{
    /// <summary>
    ///  Creates the exception.
    /// </summary>
    /// <param name="message">What is wrong, naming the file, the field or the target.</param>
    internal ProjectException(string message) : base(message) { }
}