// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using System.ComponentModel;
using System.IO.Pipes;
using System.Runtime.InteropServices;
using Microsoft.Win32.SafeHandles;

namespace Retrocore.Debug;

/// <summary>
///  Adapts the debugger's inherited pipes for cancellable reads and observable peer disconnects.
/// </summary>
internal static partial class DapStandardIo
{
    private const int WaitMilliseconds = 20;

    /// <summary>
    ///  Creates the cancellable reader for the process's standard input.
    /// </summary>
    /// <param name="input">The standard input stream.</param>
    /// <returns>The reader, or null for a stream that can use the regular transport reader.</returns>
    internal static Func<Memory<byte>, CancellationToken, int>? Reader(Stream input)
    {
        if (!Console.IsInputRedirected) { return null; }
        if (!OperatingSystem.IsWindows()) { return (bytes, token) => ReadUnix(input, bytes, token); }
        nint handle = GetStdHandle(-10);
        return handle != 0 && handle != -1 && GetFileType(handle) == 3
            ? (bytes, token) => ReadWindows(input, handle, bytes, token)
            : null;
    }

    /// <summary>
    ///  Reads from the transport's input without moving a synchronous Windows pipe read onto the thread pool.
    /// </summary>
    /// <param name="input">The adapter's request stream.</param>
    /// <param name="bytes">The destination buffer.</param>
    /// <param name="token">Cancels the input wait.</param>
    /// <returns>The bytes read, or zero at EOF.</returns>
    internal static int Read(Stream input, Memory<byte> bytes, CancellationToken token)
    {
        if (OperatingSystem.IsWindows() && input is PipeStream { IsAsync: false } pipe)
        {
            SafePipeHandle handle = pipe.SafePipeHandle;
            bool held = false;
            try
            {
                handle.DangerousAddRef(ref held);
                return ReadWindows(input, handle.DangerousGetHandle(), bytes, token);
            }
            finally
            {
                if (held) { handle.DangerousRelease(); }
            }
        }

        return input.ReadAsync(bytes, token).AsTask().GetAwaiter().GetResult();
    }

    /// <summary>
    ///  Opens the debugger output without the console stream's suppression of broken-pipe errors.
    /// </summary>
    /// <returns>The output stream.</returns>
    internal static Stream OpenOutput()
    {
        if (!Console.IsOutputRedirected) { return Console.OpenStandardOutput(); }
        nint handle = OperatingSystem.IsWindows() ? GetStdHandle(-11) : 1;
        if (handle == -1 || handle == 0) { return Console.OpenStandardOutput(); }
        return new FileStream(new SafeFileHandle(handle, ownsHandle: false), FileAccess.Write, bufferSize: 1);
    }

    private static int ReadWindows(Stream input, nint handle, Memory<byte> bytes, CancellationToken token)
    {
        while (true)
        {
            token.ThrowIfCancellationRequested();
            if (PeekNamedPipe(handle, 0, 0, 0, out uint available, 0) == 0)
            {
                int error = Marshal.GetLastPInvokeError();
                if (error is 109 or 232 or 233) { return 0; }
                throw new Win32Exception(error, "Could not inspect the debugger input pipe.");
            }

            if (available != 0) { return input.Read(bytes.Span[..(int)Math.Min(available, (uint)bytes.Length)]); }
            token.WaitHandle.WaitOne(WaitMilliseconds);
        }
    }

    private static int ReadUnix(Stream input, Memory<byte> bytes, CancellationToken token)
    {
        // struct pollfd: fd 0 (stdin), POLLIN, and revents.
        PollFd fd = new() { Events = 1 };
        while (true)
        {
            token.ThrowIfCancellationRequested();
            int ready = Poll(ref fd, 1, WaitMilliseconds);
            if (ready > 0) { return input.Read(bytes.Span); }
            if (ready < 0)
            {
                int error = Marshal.GetLastPInvokeError();
                if (error != 4) { throw new Win32Exception(error, "Could not wait for debugger input."); }
            }
        }
    }

    [LibraryImport("kernel32.dll")]
    private static partial nint GetStdHandle(int standardHandle);

    [LibraryImport("kernel32.dll")]
    private static partial uint GetFileType(nint handle);

    [LibraryImport("kernel32.dll", SetLastError = true)]
    private static partial int PeekNamedPipe(nint pipe, nint buffer, uint size, nint read, out uint available, nint left);

    [LibraryImport("libc", EntryPoint = "poll", SetLastError = true)]
    private static partial int Poll(ref PollFd fds, nuint count, int timeout);

}
