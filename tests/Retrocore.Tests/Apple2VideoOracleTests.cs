// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Machines.Apple2;
using System.Diagnostics;
using System.Text.Json;

namespace Retrocore.Tests;

/// <summary>
///  Compares complete DHGR frames against the unchanged lookup renderer in the external MIT Apple2TS cache.
/// </summary>
[TestClass]
public class Apple2VideoOracleTests
{
    /// <summary>
    ///  Checks every output byte, including colours crossing seven-bit bank and byte boundaries.
    ///  Requires Fetch-M1Dependencies.ps1 and the extension's existing npm dependencies.
    /// </summary>
    /// <param name="page2">Whether PAGE2 is selected.</param>
    /// <param name="store80">Whether 80STORE overrides PAGE2.</param>
    /// <returns>The asynchronous test.</returns>
    [TestMethod]
    [TestCategory("M2Oracle")]
    [DataRow(false, false)]
    [DataRow(true, false)]
    [DataRow(false, true)]
    [DataRow(true, true)]
    public async Task DoubleHiresMatchesPinnedLookupRenderer(bool page2, bool store80)
    {
        Apple2Machine machine = new(Apple2Model.IIeEnhanced, new Apple2Roms(new byte[16384], new byte[4096]));
        Apple2Bus bus = machine.Bus;
        Random random = new(Seed: 6502);
        for (int i = 0x2000; i < 0x6000; i++)
        {
            bus.SetRam(auxiliary: false, (ushort)i, (byte)random.Next(256));
            bus.SetRam(auxiliary: true, (ushort)i, (byte)random.Next(256));
        }

        bus.Read(0xC050);
        bus.Read(0xC057);
        bus.Read(0xC05E);
        bus.Write(0xC00D, value: 0);
        if (page2) { bus.Read(0xC055); }
        if (store80) { bus.Write(0xC001, value: 0); }
        byte[] bytes = new byte[192 * 80];
        int page = page2 && !store80 ? 0x4000 : 0x2000;

        for (int row = 0; row < 192; row++)
        {
            int address = page + (row % 8) * 1024 + ((row / 8) % 8) * 128 + (row / 64) * 40;
            for (int column = 0; column < 40; column++)
            {
                bytes[row * 80 + column * 2] = bus.AuxiliaryMemory[address + column];
                bytes[row * 80 + column * 2 + 1] = bus.MainMemory[address + column];
            }
        }

        string? root = AppContext.BaseDirectory.TrimEnd(Path.DirectorySeparatorChar);
        while (root is not null && !File.Exists(Path.Join(root, "Retrocore.slnx")))
        {
            root = Path.GetDirectoryName(root);
        }

        if (root is null)
        {
            throw new InvalidOperationException("The video oracle test must run within the project output tree.");
        }

        string oracle = Path.Join(ExternalTestData.Root, "m1-dependencies", "apple2ts", "src", "ui", "graphics.ts");
        if (!File.Exists(oracle)) { Assert.Inconclusive($"The pinned Apple2TS oracle ({oracle}) is missing."); }
        string typeScript = Path.Join(root, "extension", "node_modules", "typescript");
        if (!Directory.Exists(typeScript))
        {
            Assert.Inconclusive($"The extension's npm dependencies ({typeScript}) are missing.");
        }

        ProcessStartInfo start = new("node")
        {
            RedirectStandardInput = true, RedirectStandardOutput = true, RedirectStandardError = true, UseShellExecute = false
        };

        start.ArgumentList.Add(Path.Join(root, "tools", "Test-IIeVideo.mjs"));
        using Process process = Process.Start(start) ?? throw new InvalidOperationException("Could not start the video oracle.");
        Task<string> output = process.StandardOutput.ReadToEndAsync();
        Task<string> error = process.StandardError.ReadToEndAsync();
        await process.StandardInput.WriteAsync(JsonSerializer.Serialize(bytes.Select(value => (int)value)));
        process.StandardInput.Close();
        using CancellationTokenSource timeout = new(TimeSpan.FromSeconds(30));
        try
        {
            await process.WaitForExitAsync(timeout.Token);
        }
        catch (OperationCanceledException) when (timeout.IsCancellationRequested)
        {
            process.Kill(entireProcessTree: true);
            throw new TimeoutException("The pinned Apple2TS video oracle exceeded its 30-second budget.");
        }

        process.ExitCode.Should().Be(0, await error);
        byte[] expected = Convert.FromBase64String(await output);
        expected.Length.Should().Be(560 * 192 * 4);
        bus.Video.RenderBitmap().Should().Equal(expected);
        machine.Run(Apple2Video.CyclesPerFrame);
        bus.Video.RenderScannedBitmap().Should().Equal(expected);
    }
}
