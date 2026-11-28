// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Media.Trs80;

namespace Retrocore.Tests;

/// <summary>
///  A TRS-80 recorder that holds the bytes a test gives it.
/// </summary>
internal sealed class HoldingRecorder : ICassetteRecorder
{
    /// <summary>
    ///  Gets or sets the bytes the held bits make.
    /// </summary>
    public IReadOnlyList<byte> Bytes { get; set; } = [];

    /// <inheritdoc/>
    public IReadOnlyList<byte> Buffered() => Bytes;
}
