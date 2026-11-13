// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using System.Security.Cryptography;
using System.Text;
using System.Text.Json;

namespace Retrocore.Tests;

/// <summary>
///  Resolves and validates external fixture provenance without implicitly downloading data.
/// </summary>
internal static class ExternalTestData
{
    /// <summary>
    ///  The pinned MIT SingleStepTests revision.
    /// </summary>
    internal const string SingleStepPin = "2f6980a2d95757486c7bee24355c360e40e2a224";

    /// <summary>
    ///  The pinned GPL Klaus test-binary revision. No sources or binaries are bundled.
    /// </summary>
    internal const string KlausPin = "7954e2dbb49c469ea286070bf46cdd71aeb29e4b";

    /// <summary>
    ///  The pinned GPL MC6809 functional, cycle, and interrupt test programs.
    /// </summary>
    internal const string M6809Pin = "f445da35665991ec00a7bfc3ab4ce36f4482687e";

    /// <summary>
    ///  Gets the folder that holds every external file the tests read, such as fixtures, ROM dumps and disk images:
    ///  <c>RETROCORE_CACHE</c>, or <c>%USERPROFILE%\Retrocore</c>.
    /// </summary>
    /// <remarks>
    ///  <para>
    ///   It is outside AppData because a packaged Windows app, such as the Claude desktop app, sees a private copy of
    ///   AppData: what it or the shells it starts write there is invisible to Explorer, VS Code and other terminals.
    ///  </para>
    /// </remarks>
    internal static string Root => Environment.GetEnvironmentVariable("RETROCORE_CACHE")
        ?? Path.Join(Environment.GetFolderPath(Environment.SpecialFolder.UserProfile), "Retrocore");

    /// <summary>
    ///  Gets the external fixture cache.
    /// </summary>
    internal static string Cache => Environment.GetEnvironmentVariable("RETROCORE_TEST_CACHE")
        ?? Path.Join(Root, "processor-tests");

    /// <summary>
    ///  Loads a fixture after checking its pinned Git blob hash.
    /// </summary>
    /// <param name="pin">The upstream revision.</param>
    /// <param name="relativePath">The manifest's relative path.</param>
    /// <param name="flatten">Whether the binary cache stores only the leaf name.</param>
    /// <returns>The verified fixture bytes.</returns>
    internal static byte[] Read(string pin, string relativePath, bool flatten = false)
    {
        string root = Path.Join(Cache, pin);
        string manifestPath = Path.Join(root, "manifest.json");
        if (!File.Exists(manifestPath))
        {
            Assert.Inconclusive(
                $"External processor fixtures are missing ({manifestPath}). Run tools\\Fetch-ProcessorTests.ps1 with PowerShell 7.");
        }

        using JsonDocument manifest = JsonDocument.Parse(File.ReadAllBytes(manifestPath));
        string? expected = null;
        foreach (JsonElement entry in manifest.RootElement.EnumerateArray())
        {
            if (entry.GetProperty("path").GetString() == relativePath)
            {
                expected = entry.GetProperty("sha").GetString();
                break;
            }
        }

        if (expected is null)
        {
            throw new InvalidDataException($"Fixture missing from pinned manifest: {relativePath}.");
        }

        string local = flatten ? relativePath[(relativePath.LastIndexOf('/') + 1)..] : relativePath.Replace('/', '\\');
        byte[] bytes = File.ReadAllBytes(Path.Join(root, local));
        using IncrementalHash hash = IncrementalHash.CreateHash(HashAlgorithmName.SHA1);
        hash.AppendData(Encoding.UTF8.GetBytes($"blob {bytes.Length}\0"));
        hash.AppendData(bytes);
        string actual = Convert.ToHexString(hash.GetHashAndReset());
        return !actual.Equals(expected, StringComparison.OrdinalIgnoreCase)
            ? throw new InvalidDataException($"Pinned Git blob hash mismatch: {relativePath}.")
            : bytes;
    }
}
