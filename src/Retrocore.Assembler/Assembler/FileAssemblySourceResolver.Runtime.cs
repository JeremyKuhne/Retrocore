// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Assembler;

/// <summary>
///  Opts runtime assembly into reading text and binary includes from the host filesystem.
/// </summary>
public sealed class FileAssemblySourceResolver : IAssemblySourceResolver, IAssemblyBinaryResolver
{
    /// <inheritdoc/>
    public bool TryResolve(string fromPath, string request, [NotNullWhen(returnValue: true)] out AssemblySource? source)
    {
        string path = AssemblySourcePaths.Resolve(fromPath, request);
        try
        {
            source = new(File.ReadAllText(path), path);
            return true;
        }
        catch (FileNotFoundException)
        {
            source = null;
            return false;
        }
        catch (DirectoryNotFoundException)
        {
            source = null;
            return false;
        }
    }

    /// <inheritdoc/>
    public bool TryResolveBinary(string fromPath, string request, [NotNullWhen(returnValue: true)] out byte[]? data)
    {
        string path = AssemblySourcePaths.Resolve(fromPath, request);
        try
        {
            data = File.ReadAllBytes(path);
            return true;
        }
        catch (FileNotFoundException)
        {
            data = null;
            return false;
        }
        catch (DirectoryNotFoundException)
        {
            data = null;
            return false;
        }
    }
}
