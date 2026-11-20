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
    ///  The work, already run once so its code and types are ready. Keep it short: the tests running
    ///  beside it allocate meanwhile, and once the region is used up a GC ends it.
    /// </param>
    /// <param name="pooled">
    ///  <see langword="true"/> when the work rents from a shared pool such as <see cref="System.Buffers.ArrayPool{T}.Shared"/>:
    ///  it then runs once more in the region, unmeasured, to refill the pool before it is measured.
    /// </param>
    /// <returns>The bytes allocated, which is 0 for allocation-free work.</returns>
    /// <exception cref="InvalidOperationException">
    ///  No attempt held: each either could not start a no-GC region or had a GC run during it.
    /// </exception>
    /// <remarks>
    ///  <para>
    ///   <see cref="GC.GetAllocatedBytesForCurrentThread"/> counts the unused part of the thread's allocation
    ///   context, up to about 8 KB, as allocated when a GC retires it. Another thread can start that GC, including a
    ///   background GC's suspension, which leaves <see cref="GC.CollectionCount(int)"/> unchanged. So the work runs in
    ///   a no-GC region, and when <see cref="GC.EndNoGCRegion"/> reports that a GC ran anyway, it is measured again.
    ///  </para>
    ///  <para>
    ///   Starting the region runs a full blocking GC, and after a full GC the shared array pools trim themselves on
    ///   the finalizer thread. When the machine's memory load is above the GC's high threshold (90% by default), as it
    ///   can be during a full run, they drop every array they hold, including those the caller's warm-up returned. So each measurement first waits for that trim
    ///   to finish, and pooled work runs once before it is measured.
    ///  </para>
    /// </remarks>
    internal static long During(Action work, bool pooled = false)
    {
        ArgumentNullException.ThrowIfNull(work);
        int unstarted = 0;
        lock (s_region)
        {
            for (int attempt = 0; attempt < Attempts; attempt++)
            {
                if (!GC.TryStartNoGCRegion(RegionSize))
                {
                    unstarted++;
                    continue;
                }

                long allocated;
                bool held;
                try
                {
                    // The pools' trim after the region's GC runs as a finalizer; let it finish before refilling them.
                    GC.WaitForPendingFinalizers();
                    if (pooled) { work(); }

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

        string unstartedText = $"{unstarted} could not start a no-GC region of {RegionSize / (1024 * 1024)} MB";
        string interruptedText = $"a GC ran during the other {Attempts - unstarted}";
        throw new InvalidOperationException($"No measurement held in {Attempts} attempts: {unstartedText}, and {interruptedText}.");
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
