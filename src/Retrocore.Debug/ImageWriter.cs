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

    /// <summary>
    ///  Writes an image.
    /// </summary>
    /// <param name="path">The image's full path; a link is followed to its target.</param>
    /// <param name="bytes">The image.</param>
    /// <param name="expected">
    ///  The revision the image must still be, or null to write whatever is there, as a save to a new file the user
    ///  chose does.
    /// </param>
    /// <param name="authorized">
    ///  The SHA-256 of a revision the user saw and agreed to replace, though it is not <paramref name="expected"/>, or
    ///  null.
    /// </param>
    /// <returns>What came of it.</returns>
    /// <exception cref="IOException">The file could not be written for a reason no one can act on here.</exception>
    internal static ImageWrite Write(string path, byte[] bytes, FileRevision? expected, string? authorized = null)
    {
        string target = Resolve(path);
        using FileStream held = Lock(target);

        FileRevision? current = FileRevision.Read(target);
        if (expected is not null && !expected.SameAs(current) && (authorized is null || current?.Sha256 != authorized))
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

            return new("written", FileRevision.Read(target), Backup: backup);
        }
        finally
        {
            File.Delete(temporary);
        }
    }

    // The file a path names: a symbolic link's final target, so a link into a repository stays a link.
    private static string Resolve(string path)
    {
        FileInfo file = new(path);
        return file.LinkTarget is null ? file.FullName : file.ResolveLinkTarget(returnFinalTarget: true)?.FullName ?? file.FullName;
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
    private static void Retry(Action operation)
    {
        DateTime until = DateTime.UtcNow + s_retryFor;
        while (true)
        {
            try
            {
                operation();
                return;
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
