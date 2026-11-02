// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using SDL3;
using System.Runtime.InteropServices;
using Touki;

namespace AppleSharp;

/// <summary>
///  A native file dialog's request, kept alive until SDL calls back: SDL reads the filters while the dialog is
///  open, not just during the call that opens it.
/// </summary>
internal sealed class DialogRequest : DisposableBase
{
    private readonly SDL.DialogFileFilter[] _filters;
    private GCHandle _pinned;

    /// <summary>
    ///  Creates a request.
    /// </summary>
    /// <param name="command">The operation the dialog serves.</param>
    /// <param name="label">The file type's name, or null for a folder.</param>
    /// <param name="pattern">Its extensions, separated by semicolons, or null for a folder.</param>
    internal DialogRequest(Command command, string? label, string? pattern)
    {
        Command = command;
        _filters = label is null || pattern is null ? [] : [new SDL.DialogFileFilter(label, pattern)];
        _pinned = GCHandle.Alloc(_filters, GCHandleType.Pinned);
    }

    /// <summary>
    ///  Gets the operation the dialog serves.
    /// </summary>
    internal Command Command { get; }

    /// <summary>
    ///  Gets the filters' native array, valid until the request is disposed.
    /// </summary>
    internal IntPtr Filters => _filters.Length == 0 ? IntPtr.Zero : _pinned.AddrOfPinnedObject();

    /// <summary>
    ///  Gets how many filters there are.
    /// </summary>
    internal int FilterCount => _filters.Length;

    /// <inheritdoc/>
    protected override void Dispose(bool disposing)
    {
        if (_pinned.IsAllocated) { _pinned.Free(); }
        foreach (SDL.DialogFileFilter filter in _filters) { filter.Dispose(); }
    }
}
