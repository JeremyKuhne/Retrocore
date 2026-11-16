// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Debug;

/// <summary>
///  Writes an image file as a save does: atomically where the file system allows, only over the revision the user
///  authorized, through a link to its target, past brief locks, and keeping the revision it replaces as the image's
///  one backup.
/// </summary>
/// <remarks>
///  <para>
///   The image is written to <c>.name.guid.saving</c> beside it, flushed, and then replaces the image:
///   <see cref="File.Replace(string, string, string?, bool)"/> on Windows, which keeps its attributes and ACLs, and a
///   rename elsewhere. Every Retrocore host on the PC takes the image's lock in <see cref="LocalData"/> around the
///   revision check and the replace, so two hosts never interleave them; a program outside Retrocore that writes the
///   file in that instant can still be overwritten, and the backup then holds what Retrocore read.
///  </para>
/// </remarks>
internal static class ImageWriter
{
    // How long a sharing violation, as OneDrive or an antivirus program holding a new file, is retried.
    private static readonly TimeSpan s_retryFor = TimeSpan.FromSeconds(2);

    // How many links a path may go through, as the file systems' own limits are about this.
    private const int MaximumLinks = 40;

    /// <summary>
    ///  Writes an image.
    /// </summary>
    /// <param name="path">
    ///  The image's full path; a link, to the file or to a folder on its way, is followed to its target, so every path
    ///  to one image takes the same lock and backup.
    /// </param>
    /// <param name="bytes">The image.</param>
    /// <param name="expected">
    ///  The revision the image must still be, or null for no file there, as a save to a new file does.
    /// </param>
    /// <param name="authorized">
    ///  A revision the user saw and agreed to replace, though it is not <paramref name="expected"/>, or null. Its
    ///  null SHA-256 agrees to write where there is no file, as over an image deleted since.
    /// </param>
    /// <returns>What came of it.</returns>
    /// <exception cref="IOException">The file could not be written for a reason no one can act on here.</exception>
    internal static ImageWrite Write(string path, byte[] bytes, FileRevision? expected, Overwrite? authorized = null)
    {
        string target = Resolve(path);
        using FileStream held = Lock(target);

        // Only over the revision expected, or the one the user agreed to replace: a file that appeared or changed
        // since either was seen is a conflict.
        FileRevision? current = FileRevision.Read(target);
        bool expectedNow = expected is null ? current is null : expected.SameAs(current);
        if (!expectedNow && (authorized is null || authorized.Sha256 != current?.Sha256))
        {
            return new("conflict", current);
        }

        if (current is not null && File.GetAttributes(target).HasFlag(FileAttributes.ReadOnly))
        {
            return new("readOnly", current, Reason: "file");
        }

        string folder = Path.GetDirectoryName(target) ?? throw new ArgumentException($"{target} is not a file.", nameof(path));
        string temporary = Path.Join(folder, $".{Path.GetFileName(target)}.{Guid.NewGuid():N}.saving");
        try
        {
            try
            {
                using FileStream stream = new(temporary, FileMode.CreateNew, FileAccess.Write, FileShare.None);
                stream.Write(bytes);
                stream.Flush(flushToDisk: true);
            }
            catch (UnauthorizedAccessException)
            {
                return new("readOnly", current, Reason: "access");
            }

            // The revision it replaces is kept first, so a save never claims a backup it did not make.
            string? backup = null;
            if (current is not null)
            {
                backup = LocalData.BackupFor(target);
                Directory.CreateDirectory(Path.GetDirectoryName(backup) ?? LocalData.Root);
                Retry(() => File.Copy(target, backup, overwrite: true));
            }

            try
            {
                Retry(() =>
                {
                    if (current is not null && OperatingSystem.IsWindows())
                    {
                        File.Replace(temporary, target, destinationBackupFileName: null, ignoreMetadataErrors: true);
                    }
                    else
                    {
                        File.Move(temporary, target, overwrite: true);
                    }
                });
            }
            catch (UnauthorizedAccessException)
            {
                return new("readOnly", current, Reason: "access");
            }

            // The revision written is the bytes committed, not a read after, which another writer may already have
            // replaced: a change made since stays a change.
            return new("written", FileRevision.Of(target, bytes), Backup: backup);
        }
        finally
        {
            File.Delete(temporary);
        }
    }

    // The file a path names, with every link on the way followed, to the file and to the folders it is in: so a link
    // into a repository stays a link, and two paths to one image are the same file for its lock and its backup.
    private static string Resolve(string path)
    {
        string current = Path.GetFullPath(path);
        for (int links = 0; links < MaximumLinks; links++)
        {
            string? folder = Path.GetDirectoryName(current);
            string resolved = folder is null ? current : Path.Join(ResolveFolder(folder, depth: 0), Path.GetFileName(current));
            FileInfo file = new(resolved);
            if (file.LinkTarget is null) { return resolved; }
            current = file.ResolveLinkTarget(returnFinalTarget: false)?.FullName ?? resolved;
        }

        throw new IOException($"{path} goes through more than {MaximumLinks} links.");
    }

    // A folder with every link on its way followed, from the root down.
    private static string ResolveFolder(string folder, int depth)
    {
        if (depth > MaximumLinks) { throw new IOException($"{folder} goes through more than {MaximumLinks} links."); }
        DirectoryInfo info = new(folder);
        if (info.Parent is null) { return info.FullName; }
        string resolved = Path.Join(ResolveFolder(info.Parent.FullName, depth), info.Name);
        DirectoryInfo at = new(resolved);
        return at.LinkTarget is null || at.ResolveLinkTarget(returnFinalTarget: true) is not DirectoryInfo target
            ? resolved
            : ResolveFolder(target.FullName, depth + 1);
    }

    // Takes the image's lock, which another host may hold for a moment.
    private static FileStream Lock(string image)
    {
        string lockFile = LocalData.LockFor(image);
        Directory.CreateDirectory(Path.GetDirectoryName(lockFile) ?? LocalData.Root);
        FileStream? held = null;
        Retry(() => held = new FileStream(lockFile, FileMode.OpenOrCreate, FileAccess.ReadWrite, FileShare.None));
        return held ?? throw new IOException($"The lock on {image} could not be taken.");
    }

    // Retries a file operation through sharing and lock violations for a moment, as files new to OneDrive or an
    // antivirus program are held briefly; any other failure, and one that outlasts the moment, is thrown.
    private static void Retry(Action operation) => Retry(() =>
    {
        operation();
        return true;
    });

    /// <summary>
    ///  Retries a file operation through sharing and lock violations for a moment, as files new to OneDrive or an
    ///  antivirus program are held briefly.
    /// </summary>
    /// <typeparam name="T">What the operation gives.</typeparam>
    /// <param name="operation">The operation.</param>
    /// <returns>What it gave.</returns>
    /// <exception cref="IOException">It failed otherwise, or its file was held for longer than the moment.</exception>
    internal static T Retry<T>(Func<T> operation)
    {
        DateTime until = DateTime.UtcNow + s_retryFor;
        while (true)
        {
            try
            {
                return operation();
            }
            catch (IOException exception) when (IsTransient(exception) && DateTime.UtcNow < until)
            {
                Thread.Sleep(50);
            }
        }
    }

    // ERROR_SHARING_VIOLATION and ERROR_LOCK_VIOLATION, and their POSIX equivalent where the file is locked.
    private static bool IsTransient(IOException exception) =>
        (exception.HResult & 0xFFFF) is 32 or 33 || exception.HResult == 11;
}
