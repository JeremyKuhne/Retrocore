// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Assembler;
using System.Diagnostics.CodeAnalysis;

namespace Retrocore.Tests;

public partial class AssemblyPreprocessorTests
{
    /// <summary>
    ///  In-memory resolver that also supplies binary includes.
    /// </summary>
    private sealed class BinaryResolver : IAssemblySourceResolver, IAssemblyBinaryResolver
    {
        private readonly Dictionary<string, byte[]> _binaries = new(StringComparer.OrdinalIgnoreCase);

        /// <summary>
        ///  Registers binary contents without filesystem I/O.
        /// </summary>
        /// <param name="path">The physical identity.</param>
        /// <param name="data">The contents.</param>
        internal void AddBinary(string path, byte[] data) => _binaries.Add(Path.GetFullPath(path), data);

        /// <inheritdoc/>
        public bool TryResolve(string fromPath, string request, [NotNullWhen(returnValue: true)] out AssemblySource? source)
        {
            source = null;
            return false;
        }

        /// <inheritdoc/>
        public bool TryResolveBinary(string fromPath, string request, [NotNullWhen(returnValue: true)] out byte[]? data) =>
            _binaries.TryGetValue(Path.GetFullPath(AssemblySourcePaths.Resolve(fromPath, request)), out data);
    }
}
