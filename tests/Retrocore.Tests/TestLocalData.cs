// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Tests;

/// <summary>
///  Points local data, where saves keep their backups and locks, at one folder for the whole test run, so tests in
///  parallel never move it under each other.
/// </summary>
[TestClass]
public static class TestLocalData
{
    /// <summary>
    ///  Gets the folder that holds the run's local data.
    /// </summary>
    public static string Root { get; } = Path.Join(Path.GetTempPath(), $"retrocore-local-{Environment.ProcessId}");

    /// <summary>
    ///  Sets local data to the run's folder before any test.
    /// </summary>
    /// <param name="context">The test context.</param>
    [AssemblyInitialize]
    public static void Initialize(TestContext context)
    {
        _ = context;
        Directory.CreateDirectory(Root);
        Environment.SetEnvironmentVariable("RETROCORE_LOCAL_DATA", Root);
    }

    /// <summary>
    ///  Removes the run's folder after every test.
    /// </summary>
    [AssemblyCleanup]
    public static void Cleanup()
    {
        if (!Directory.Exists(Root)) { return; }
        foreach (string file in Directory.EnumerateFiles(Root, "*", SearchOption.AllDirectories))
        {
            File.SetAttributes(file, FileAttributes.Normal);
        }

        Directory.Delete(Root, recursive: true);
    }
}
