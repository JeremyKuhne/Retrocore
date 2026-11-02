// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Tests;

/// <summary>
///  Measures managed allocation on the test's thread.
/// </summary>
internal static class Allocations
{
    /// <summary>
    ///  Gets the fewest bytes the work allocates in any of a few runs.
    /// </summary>
    /// <param name="work">The work, already run once so its code and types are loaded.</param>
    /// <param name="attempts">The runs to measure.</param>
    /// <returns>The lowest count, which is 0 for allocation-free work.</returns>
    /// <remarks>
    ///  Under a loaded parallel test run the runtime can allocate on the thread once, while the work's code is
    ///  being promoted to optimized code. Work that allocates does so on every run, so the lowest count still
    ///  shows it.
    /// </remarks>
    internal static long Fewest(Action work, int attempts = 3)
    {
        long fewest = long.MaxValue;
        for (int attempt = 0; attempt < attempts && fewest != 0; attempt++)
        {
            long start = GC.GetAllocatedBytesForCurrentThread();
            work();
            fewest = Math.Min(fewest, GC.GetAllocatedBytesForCurrentThread() - start);
        }

        return fewest;
    }
}
