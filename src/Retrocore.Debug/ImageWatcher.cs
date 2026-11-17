// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Debug;

/// <summary>
///  Watches the image files disks were read from, so a drive shows when its image changes on disk.
/// </summary>
/// <remarks>
///  <para>
///   Each image has an <see cref="ImageWatch"/>, its watchers and settle timer. Every few seconds a sweep makes whole
///   any watch that failed, and checks an image whose file changed where no event said, as through a link on the way
///   pointed elsewhere. Checks run off the machine's thread.
///  </para>
/// </remarks>
internal static class ImageWatcher
{
    // How often the watches are swept.
    private const int SweepMilliseconds = 2000;

    private static readonly Lock s_lock = new();

    // Each image's watch, by the path a disk was read from.
    private static readonly Dictionary<string, ImageWatch> s_watches =
        [with(OperatingSystem.IsWindows() || OperatingSystem.IsMacOS() ? StringComparer.OrdinalIgnoreCase : StringComparer.Ordinal)];

    private static Timer? s_sweep;

    // Whether a disk still comes from an image, by its full path.
    private static Func<string, bool> s_watched = _ => false;

    /// <summary>
    ///  Watches an image, and stops watching images no disk comes from any more.
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
            if (!s_watches.ContainsKey(path)) { s_watches[path] = new ImageWatch(path, changed); }
            s_sweep ??= new(_ => Sweep(), state: null, SweepMilliseconds, SweepMilliseconds);
        }
    }

    // Stops watching images no disk comes from any more, and sweeping once none are left.
    private static void Prune()
    {
        foreach (string gone in s_watches.Keys.Where(key => !s_watched(key)).ToList())
        {
            s_watches[gone].Close();
            s_watches.Remove(gone);
        }

        if (s_watches.Count == 0)
        {
            s_sweep?.Dispose();
            s_sweep = null;
        }
    }

    // Sweeps each watch in turn, after dropping those no disk needs.
    private static void Sweep()
    {
        ImageWatch[] watches;
        lock (s_lock)
        {
            Prune();
            watches = [.. s_watches.Values];
        }

        foreach (ImageWatch watch in watches) { watch.Sweep(); }
    }
}
