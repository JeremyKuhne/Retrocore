// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Pascal.Source;

/// <summary>
///  A problem the Pascal lint finds in a source.
/// </summary>
/// <param name="File">The file.</param>
/// <param name="Line">The line, from 0.</param>
/// <param name="Column">The first column, from 0.</param>
/// <param name="EndColumn">The column after the last.</param>
/// <param name="IsError">Whether it is an error, which keeps the source from compiling or reading as it should.</param>
/// <param name="Rule">The rule, a short name such as <c>line-length</c>.</param>
/// <param name="Message">What is wrong, and what to do.</param>
public sealed record PascalDiagnostic(
    string File,
    int Line,
    int Column,
    int EndColumn,
    bool IsError,
    string Rule,
    string Message);
