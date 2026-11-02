// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Assembler;
using System.Diagnostics.CodeAnalysis;

namespace Retrocore.Tests;

public partial class AssemblyPreprocessorTests
{
    /// <summary>
    ///  In-memory source resolver with observable lookup order.
    /// </summary>
    private sealed class Resolver : IAssemblySourceResolver
    {
        private readonly Dictionary<string, AssemblySource> _sources = new(StringComparer.OrdinalIgnoreCase);

        /// <summary>
        ///  Gets attempted include requests.
        /// </summary>
        internal List<(string From, string Request)> Requests { get; } = [];

        /// <summary>
        ///  Registers a source without filesystem I/O.
        /// </summary>
        /// <param name="path">The physical identity.</param>
        /// <param name="text">The contents.</param>
        /// <param name="dialect">Optional resolver metadata.</param>
        internal void Add(string path, string text, AssemblyDialect? dialect = null) =>
            _sources.Add(Path.GetFullPath(path), new(text, path, dialect));

        /// <inheritdoc/>
        public bool TryResolve(string fromPath, string request, [NotNullWhen(returnValue: true)] out AssemblySource? source)
        {
            Requests.Add((fromPath, request));
            string path = AssemblySourcePaths.Resolve(fromPath, request);
            return _sources.TryGetValue(Path.GetFullPath(path), out source);
        }
    }
}
