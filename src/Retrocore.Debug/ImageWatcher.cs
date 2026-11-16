// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Debug;

/// <summary>
///  Watches the image files disks were read from, so a drive shows when its image changes on disk.
/// </summary>
/// <remarks>
///  <para>
///   Each image has a watcher on its folder, filtered to its name, and, when its path is a link, one on the file the
///   link leads to, as a save writes there; a link pointed elsewhere moves that watcher. A change is checked a moment
///   after the last event, as a save or a copy raises several, off the machine's thread.
///  </para>
/// </remarks>
internal static class ImageWatcher
{
    // How long after the last event a change is checked.
    private const int SettleMilliseconds = 200;

    private static readonly Lock s_lock = new();
    private static readonly StringComparer s_paths =
        OperatingSystem.IsWindows() || OperatingSystem.IsMacOS() ? StringComparer.OrdinalIgnoreCase : StringComparer.Ordinal;

    // Each image's watcher, by the path the disk was read from, and the timer that checks it once its events settle.
    private static readonly Dictionary<string, (FileSystemWatcher? Watcher, Timer Settle)> s_watches = [with(s_paths)];

    // For an image whose path is a link, the file it leads to and that file's watcher.
    private static readonly Dictionary<string, (string Target, FileSystemWatcher? Watcher)> s_targets = [with(s_paths)];

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
                s_watches[gone].Watcher?.Dispose();
                s_watches[gone].Settle.Dispose();
                s_watches.Remove(gone);
                if (s_targets.Remove(gone, out (string Target, FileSystemWatcher? Watcher) target))
                {
                    target.Watcher?.Dispose();
                }
            }

            if (s_watches.ContainsKey(path)) { return; }
            Timer settle = new(_ =>
            {
                Retarget(path);
                changed(path);
            });

            s_watches[path] = (Create(path, settle), settle);
            Retarget(path);
        }
    }

    // Watches the file a link leads to, moving the watcher when the link now leads elsewhere, and dropping it when the
    // path is no longer a link.
    private static void Retarget(string path)
    {
        lock (s_lock)
        {
            if (!s_watches.TryGetValue(path, out (FileSystemWatcher? Watcher, Timer Settle) watch)) { return; }
            string target;
            try
            {
                target = ImageWriter.Resolve(path);
            }
            catch (Exception exception) when (exception is IOException or UnauthorizedAccessException)
            {
                target = path;
            }

            bool known = s_targets.TryGetValue(path, out (string Target, FileSystemWatcher? Watcher) old);
            if (known && s_paths.Equals(old.Target, target)) { return; }
            if (known)
            {
                old.Watcher?.Dispose();
                s_targets.Remove(path);
            }

            if (!s_paths.Equals(target, path)) { s_targets[path] = (target, Create(target, watch.Settle)); }
        }
    }

    // A watcher on a file's folder, filtered to its name, whose events start the settle timer; or none for a folder
    // that is not there.
    private static FileSystemWatcher? Create(string file, Timer settle)
    {
        if (Path.GetDirectoryName(file) is not { } folder || !Directory.Exists(folder)) { return null; }
        FileSystemWatcher watcher;
        try
        {
            watcher = new(folder, Path.GetFileName(file))
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
            return null;
        }

        void Poke()
        {
            try
            {
                settle.Change(SettleMilliseconds, Timeout.Infinite);
            }
            catch (ObjectDisposedException)
            {
                // No disk comes from the image any more.
            }
        }

        watcher.Changed += (_, _) => Poke();
        watcher.Created += (_, _) => Poke();
        watcher.Deleted += (_, _) => Poke();
        watcher.Renamed += (_, _) => Poke();
        watcher.Error += (_, _) => Poke();
        watcher.EnableRaisingEvents = true;
        return watcher;
    }
}
