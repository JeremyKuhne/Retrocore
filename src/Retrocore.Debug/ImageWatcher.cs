// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using System.Diagnostics;

namespace Retrocore.Debug;

/// <summary>
///  Watches the image files disks were read from, so a drive shows when its image changes on disk.
/// </summary>
/// <remarks>
///  <para>
///   Each image has an <see cref="ImageWatch"/>, its watchers and when it is next checked. Every few seconds a sweep
///   makes whole any watch that failed, and checks an image whose file changed where no event said, as through a link
///   on the way pointed elsewhere. Sweeps and checks run on the watcher's own thread, off the machine's, and not on
///   the thread pool, where they would wait behind whatever holds its threads; the thread ends when no image is
///   watched.
///  </para>
/// </remarks>
internal static class ImageWatcher
{
    // How often the watches are swept.
    private static readonly long s_sweepTicks = Stopwatch.Frequency * 2;

    private static readonly Lock s_lock = new();

    // Each image's watch, by the path a disk was read from.
    private static readonly Dictionary<string, ImageWatch> s_watches =
        [with(OperatingSystem.IsWindows() || OperatingSystem.IsMacOS() ? StringComparer.OrdinalIgnoreCase : StringComparer.Ordinal)];

    // Set when a watch has a check to wait for, so the thread works out how long to sleep again.
    private static readonly AutoResetEvent s_wake = new(initialState: false);

    private static Thread? s_thread;

    // Whether a disk still comes from an image, by its full path.
    private static Func<string, bool> s_watched = _ => false;

    /// <summary>
    ///  Watches an image, and checks it, as the file may have changed since it was read; and stops watching images no
    ///  disk comes from any more.
    /// </summary>
    /// <param name="path">The image's full path.</param>
    /// <param name="watched">Whether a disk still comes from an image, by its full path.</param>
    /// <param name="changed">
    ///  Checks an image that changed, by its full path; false when it could not be read, to be tried again.
    /// </param>
    internal static void Watch(string path, Func<string, bool> watched, Func<string, bool> changed)
    {
        lock (s_lock)
        {
            s_watched = watched;
            Prune();
            if (!s_watches.TryGetValue(path, out ImageWatch? watch))
            {
                watch = new ImageWatch(path, changed);
                s_watches[path] = watch;
            }

            if (s_thread is null)
            {
                s_thread = new Thread(Run) { IsBackground = true, Name = "Retrocore image watcher" };
                s_thread.Start();
            }

            watch.Poke();
        }
    }

    /// <summary>
    ///  Tells the watcher's thread a watch has a check waiting.
    /// </summary>
    internal static void Wake() => s_wake.Set();

    // Stops watching images no disk comes from any more.
    private static void Prune()
    {
        foreach (string gone in s_watches.Keys.Where(key => !s_watched(key)).ToList())
        {
            s_watches[gone].Close();
            s_watches.Remove(gone);
        }
    }

    // Sweeps every few seconds, after dropping the watches no disk needs, and checks each image whose events have
    // settled, sleeping until the next of those or a new event; ends once no image is watched.
    private static void Run()
    {
        long sweepAt = Stopwatch.GetTimestamp() + s_sweepTicks;
        while (true)
        {
            bool sweep = Stopwatch.GetTimestamp() >= sweepAt;
            ImageWatch[] watches;
            lock (s_lock)
            {
                if (sweep) { Prune(); }
                if (s_watches.Count == 0)
                {
                    s_thread = null;
                    return;
                }

                watches = [.. s_watches.Values];
            }

            if (sweep)
            {
                foreach (ImageWatch watch in watches) { watch.Sweep(); }
                sweepAt = Stopwatch.GetTimestamp() + s_sweepTicks;
            }

            long next = sweepAt;
            foreach (ImageWatch watch in watches)
            {
                watch.SettleIfDue(Stopwatch.GetTimestamp());
                long at = watch.SettleAt;
                if (at != 0 && at < next) { next = at; }
            }

            long wait = next - Stopwatch.GetTimestamp();
            // Rounded up to whole milliseconds, which the wait counts in, so it does not wake just short and spin.
            if (wait > 0) { s_wake.WaitOne((int)Math.Ceiling(wait * 1000.0 / Stopwatch.Frequency)); }
        }
    }
}
