// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Debug;

/// <summary>
///  Watches the image files disks were read from, so a drive shows when its image changes on disk.
/// </summary>
/// <remarks>
///  <para>
///   Each image has one watcher on its folder, filtered to its name. A change is checked a moment after the last
///   event, as a save or a copy raises several, off the machine's thread: the file is hashed once and every disk read
///   from it learns what was found.
///  </para>
/// </remarks>
internal static class ImageWatcher
{
    // How long after the last event a change is checked.
    private const int SettleMilliseconds = 200;

    private static readonly Lock s_lock = new();

    // Each image's watcher, and the timer that checks it once its events settle.
    private static readonly Dictionary<string, (FileSystemWatcher Watcher, Timer Settle)> s_watches =
        [with(OperatingSystem.IsWindows() || OperatingSystem.IsMacOS() ? StringComparer.OrdinalIgnoreCase : StringComparer.Ordinal)];

    /// <summary>
    ///  Watches an image, and stops watching images no disk comes from any more.
    /// </summary>
    /// <param name="path">The image's full path.</param>
    /// <param name="watched">Whether a disk still comes from an image, by its full path.</param>
    /// <param name="changed">Checks an image that changed, by its full path.</param>
    internal static void Watch(string path, Func<string, bool> watched, Action<string> changed)
    {
        lock (s_lock)
        {
            foreach (string gone in s_watches.Keys.Where(key => !watched(key)).ToList())
            {
                s_watches[gone].Watcher.Dispose();
                s_watches[gone].Settle.Dispose();
                s_watches.Remove(gone);
            }

            if (s_watches.ContainsKey(path)
                || Path.GetDirectoryName(path) is not { } folder
                || !Directory.Exists(folder))
            {
                return;
            }

            Timer settle = new(_ => changed(path));
            FileSystemWatcher watcher;
            try
            {
                watcher = new(folder, Path.GetFileName(path))
                {
                    NotifyFilter = NotifyFilters.FileName
                        | NotifyFilters.LastWrite
                        | NotifyFilters.Size
                        | NotifyFilters.Attributes
                        | NotifyFilters.CreationTime,
                };
            }
            catch (Exception exception) when (exception is ArgumentException or IOException)
            {
                settle.Dispose();
                return;
            }

            void Poke() => settle.Change(SettleMilliseconds, Timeout.Infinite);
            watcher.Changed += (_, _) => Poke();
            watcher.Created += (_, _) => Poke();
            watcher.Deleted += (_, _) => Poke();
            watcher.Renamed += (_, _) => Poke();
            watcher.Error += (_, _) => Poke();
            watcher.EnableRaisingEvents = true;
            s_watches[path] = (watcher, settle);
        }
    }
}
