// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Assembler;
using System.Diagnostics.CodeAnalysis;

namespace Retrocore.Tests;

public partial class AssemblyPreprocessorTests
{
    /// <summary>
    ///  A resolver that fails every request with a given error.
    /// </summary>
    /// <param name="error">The error to throw.</param>
    private sealed class ThrowingResolver(Exception error) : IAssemblySourceResolver
    {
        /// <inheritdoc/>
        public bool TryResolve(string fromPath, string request, [NotNullWhen(returnValue: true)] out AssemblySource? source) =>
            throw error;
    }
}
