// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Pascal;

public sealed partial class PascalDecompiler
{
    /// <summary>
    ///  The parameters and result of an assembled procedure, which its calls show.
    /// </summary>
    /// <param name="ParameterWords">The words of its parameters.</param>
    /// <param name="IsFunction">Whether it is a function, whose calls leave two words for its result.</param>
    private sealed record NativeSignature(int ParameterWords, bool IsFunction);
}
