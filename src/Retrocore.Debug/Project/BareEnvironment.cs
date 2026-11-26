// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Debug.Project;

/// <summary>
///  The <c>bare</c> environment: a raw binary, loaded straight into RAM and started at its entry, which calls only the
///  ROM's routines. The binary is its file, and it builds no image.
/// </summary>
internal sealed class BareEnvironment : TargetEnvironment
{
    /// <inheritdoc/>
    internal override string Name => ProjectTarget.Bare;

    /// <inheritdoc/>
    internal override TargetMedia Write(TargetBuild build) => TargetMedia.None;
}
