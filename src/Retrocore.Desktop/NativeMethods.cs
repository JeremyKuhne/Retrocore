// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using System.Runtime.InteropServices;
using System.Runtime.Versioning;

namespace Retrocore.Desktop;

/// <summary>
///  The few calls to the operating system that Avalonia has no API for.
/// </summary>
internal static partial class NativeMethods
{
    /// <summary>
    ///  Moves the pointer to a point on the screen, as the mouse card does to keep its hidden pointer from stopping at
    ///  an edge.
    /// </summary>
    /// <param name="x">Across, in screen pixels.</param>
    /// <param name="y">Down, in screen pixels.</param>
    /// <returns>Whether it moved.</returns>
    [SupportedOSPlatform("windows")]
    [LibraryImport("user32.dll", EntryPoint = "SetCursorPos")]
    [return: MarshalAs(UnmanagedType.Bool)]
    internal static partial bool SetCursorPos(int x, int y);
}
