// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Tests;

/// <summary>
///  Measures managed allocation on the test's thread.
/// </summary>
internal static class Allocations
{
    // Room for the work's own allocations and for what the tests running beside it allocate meanwhile, which in a
    // full run with the machines' fixtures used up 64 MB during a measurement that rendered 32 frames.
    private const long RegionSize = 256 * 1024 * 1024;

    // A measurement whose region a GC broke into is taken again, up to this many times in all.
    private const int Attempts = 5;

    // The no-GC region covers the whole process, and only one can be open at a time.
    private static readonly Lock s_region = new();

    /// <summary>
    ///  Gets the bytes the work allocates on this thread, measured while no GC can run.
    /// </summary>
    /// <param name="work">
    ///  The work, already run once so its code, types and pooled buffers are ready. Keep it short: the tests running
    ///  beside it allocate meanwhile, and once the region is used up a GC ends it.
    /// </param>
    /// <returns>The bytes allocated, which is 0 for allocation-free work.</returns>
    /// <exception cref="InvalidOperationException">A GC ran during every attempt.</exception>
    /// <remarks>
    ///  <para>
    ///   <see cref="GC.GetAllocatedBytesForCurrentThread"/> counts the unused part of the thread's allocation
    ///   context, up to about 8 KB, as allocated when a GC retires it. Another thread can start that GC, including a
    ///   background GC's suspension, which leaves <see cref="GC.CollectionCount(int)"/> unchanged. So the work runs in
    ///   a no-GC region, and when <see cref="GC.EndNoGCRegion"/> reports that a GC ran anyway, it is measured again.
    ///  </para>
    /// </remarks>
    internal static long During(Action work)
    {
        ArgumentNullException.ThrowIfNull(work);
        lock (s_region)
        {
            for (int attempt = 0; attempt < Attempts; attempt++)
            {
                if (!GC.TryStartNoGCRegion(RegionSize)) { continue; }
                long allocated;
                bool held;
                try
                {
                    long start = GC.GetAllocatedBytesForCurrentThread();
                    work();
                    allocated = GC.GetAllocatedBytesForCurrentThread() - start;
                }
                finally
                {
                    held = EndRegion();
                }

                if (held) { return allocated; }
            }
        }

        throw new InvalidOperationException($"A GC ran during each of {Attempts} measurements.");
    }

    // Ends the no-GC region; false when a GC ran in it, which may have retired the thread's allocation context.
    private static bool EndRegion()
    {
        try
        {
            GC.EndNoGCRegion();
            return true;
        }
        catch (InvalidOperationException)
        {
            return false;
        }
    }
}
