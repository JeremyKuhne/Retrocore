// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Debug;

/// <summary>
///  One image's watch: a watcher on the folder of the path a disk was read from, one on the file that path leads to
///  when it is a link, and the timer that checks the image once their events settle.
/// </summary>
/// <remarks>
///  <para>
///   Watching is best effort, so a sweep keeps it whole: it makes again a watcher that could not start or that
///   failed (a folder deleted and made again, the system out of watches), moves the target's watcher when a link on
///   the way now leads elsewhere, and checks the image when what it finds of the file (where the path leads, its
///   length, when it was written and its attributes) differs from the last sweep, which no event may have told.
///   Nothing here throws to the timers that call it.
///  </para>
/// </remarks>
internal sealed class ImageWatch
{
    // How long after the last event the image is checked.
    private const int SettleMilliseconds = 200;

    private readonly Lock _lock = new();
    private readonly Timer _settle;
    private readonly Func<string, bool> _changed;
    private FileSystemWatcher? _watcher;
    private FileSystemWatcher? _targetWatcher;
    private string? _target;
    private string? _signature;
    private volatile bool _failed;
    private bool _closed;

    /// <summary>
    ///  Starts watching an image.
    /// </summary>
    /// <param name="path">The image's full path, as the disk was read from it.</param>
    /// <param name="changed">
    ///  Checks the image, by that path; false when it could not be read, to be tried again.
    /// </param>
    internal ImageWatch(string path, Func<string, bool> changed)
    {
        Path = path;
        _changed = changed;
        _settle = new(_ => Settled());
        Sweep(check: false);
    }

    /// <summary>
    ///  Gets the image's full path, as the disk was read from it.
    /// </summary>
    internal string Path { get; }

    /// <summary>
    ///  Makes again what failed or no longer fits, and checks the image if it changed unseen.
    /// </summary>
    /// <param name="check">Whether a change found is checked; false to only take note of the file as it is.</param>
    internal void Sweep(bool check = true)
    {
        lock (_lock)
        {
            if (_closed) { return; }
            if (_watcher is null || _failed)
            {
                _failed = false;
                _watcher?.Dispose();
                _watcher = Create(Path);
            }

            string target = Target();
            if (!SamePath(target, _target ?? Path) || (_targetWatcher is null && !SamePath(target, Path)))
            {
                _targetWatcher?.Dispose();
                _targetWatcher = SamePath(target, Path) ? null : Create(target);
                _target = target;
            }

            string signature = Signature(target);
            if (signature == _signature) { return; }
            _signature = signature;
            if (check) { Poke(); }
        }
    }

    /// <summary>
    ///  Stops watching.
    /// </summary>
    internal void Close()
    {
        lock (_lock)
        {
            _closed = true;
            _watcher?.Dispose();
            _targetWatcher?.Dispose();
            _settle.Dispose();
        }
    }

    // The image is checked once its events settle, after the watch is made whole and the file noted, so the next
    // sweep does not check it again; a check that could not read the file forgets it, so the next sweep tries again.
    private void Settled()
    {
        Sweep(check: false);
        if (_changed(Path)) { return; }
        lock (_lock) { _signature = null; }
    }

    private void Poke()
    {
        try
        {
            _settle.Change(SettleMilliseconds, Timeout.Infinite);
        }
        catch (ObjectDisposedException)
        {
            // No disk comes from the image any more.
        }
    }

    // Where the path leads, every link followed, or the path itself when that cannot be told.
    private string Target()
    {
        try
        {
            return ImageWriter.Resolve(Path);
        }
        catch (Exception exception) when (exception is IOException or UnauthorizedAccessException or ArgumentException)
        {
            return Path;
        }
    }

    // What a sweep compares: where the path leads, and that file's length, last write and attributes.
    private static string Signature(string target)
    {
        try
        {
            FileInfo file = new(target);
            return file.Exists
                ? $"{target}|{file.Length}|{file.LastWriteTimeUtc.Ticks}|{file.Attributes}"
                : $"{target}|missing";
        }
        catch (Exception exception) when (exception is IOException or UnauthorizedAccessException or ArgumentException)
        {
            return $"{target}|unreadable";
        }
    }

    // A watcher on a file's folder, filtered to its name, whose events start the settle timer; or none when it cannot
    // be made, which a later sweep tries again.
    private FileSystemWatcher? Create(string file)
    {
        if (System.IO.Path.GetDirectoryName(file) is not { } folder || !Directory.Exists(folder)) { return null; }
        FileSystemWatcher? watcher = null;
        try
        {
            watcher = new(folder, System.IO.Path.GetFileName(file))
            {
                NotifyFilter = NotifyFilters.FileName
                    | NotifyFilters.LastWrite
                    | NotifyFilters.Size
                    | NotifyFilters.Attributes
                    | NotifyFilters.CreationTime,
            };

            watcher.Changed += (_, _) => Poke();
            watcher.Created += (_, _) => Poke();
            watcher.Deleted += (_, _) => Poke();
            watcher.Renamed += (_, _) => Poke();
            watcher.Error += (_, _) =>
            {
                _failed = true;
                Poke();
            };

            watcher.EnableRaisingEvents = true;
            return watcher;
        }
        catch (Exception exception) when (exception is ArgumentException or IOException or UnauthorizedAccessException)
        {
            watcher?.Dispose();
            return null;
        }
    }

    private static bool SamePath(string first, string second) =>
        string.Equals(first, second, OperatingSystem.IsWindows() || OperatingSystem.IsMacOS()
            ? StringComparison.OrdinalIgnoreCase
            : StringComparison.Ordinal);
}
