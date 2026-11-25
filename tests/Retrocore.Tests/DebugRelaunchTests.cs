// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Debug;
using System.Text.Json.Nodes;

namespace Retrocore.Tests;

/// <summary>
///  Verifies that each launch on one debug connection waits for its own <c>configurationDone</c>, so the exception
///  filters and breakpoints a client sends after a relaunch apply to the new machine from its first instruction.
/// </summary>
[TestClass]
public sealed class DebugRelaunchTests
{
    private const string PowerOn = "The machine reset as it powered on.";
    private static readonly string s_inputs = Path.Join(AppContext.BaseDirectory, "Inputs");

    // The II Plus from the SDK's sources, running at once rather than stopping on entry.
    private static JsonObject IIPlus() => new()
    {
        ["machine"] = "apple2",
        ["model"] = "iiplus",
        ["sdkRoms"] = s_inputs,
        ["controllers"] = false,
        ["sound"] = "off",
        ["stopOnEntry"] = false,
        ["speed"] = "max"
    };

    /// <summary>
    ///  A relaunch does not start until its configurationDone: the machineReset filter set after it stops the new
    ///  machine as it powers on, clearing the filter after the next relaunch lets that machine run past its reset, and
    ///  an instruction breakpoint set after a relaunch stops it at its first instruction.
    /// </summary>
    [TestMethod]
    public void RelaunchWaitsForItsOwnConfigurationDone()
    {
        using DapTestClient client = new();
        client.Request("initialize", []);

        // The first launch powers on and runs: no filter, no breakpoints.
        client.Request("launch", IIPlus());
        client.Request("configurationDone", []);

        // The machineReset filter, set after the relaunch, stops it as it powers on.
        client.Request("launch", IIPlus());
        client.Request("setExceptionBreakpoints", new JsonObject { ["filters"] = new JsonArray("machineReset") });
        client.Request("configurationDone", []);
        JsonObject stopped = client.Event("stopped");
        stopped.String("reason").Should().Be("breakpoint");
        stopped.String("description").Should().Be(PowerOn);

        // Cleared after the next relaunch, the filter no longer stops it.
        client.Request("launch", IIPlus());
        client.Request("setExceptionBreakpoints", new JsonObject { ["filters"] = new JsonArray() });
        client.Request("configurationDone", []);
        client.NoStop(TimeSpan.FromMilliseconds(500), "the cleared filter does not stop the relaunch at power on");

        // A breakpoint set after a relaunch, at the instruction it powers on to, stops it there.
        client.Request("launch", IIPlus());
        JsonObject evaluated = client.Request("evaluate", new JsonObject { ["expression"] = "PC" });
        string pc = evaluated.String("memoryReference") ?? throw new AssertFailedException("PC has no reference.");
        JsonObject breakpoint = new() { ["instructionReference"] = pc };
        client.Request("setInstructionBreakpoints", new JsonObject { ["breakpoints"] = new JsonArray(breakpoint) });
        client.Request("configurationDone", []);
        stopped = client.Event("stopped");
        stopped.String("reason").Should().Be("instruction breakpoint");
        JsonObject trace = client.Request("stackTrace", new JsonObject { ["threadId"] = 1 });
        JsonObject frame = trace["stackFrames"]?[0] as JsonObject ?? throw new AssertFailedException("No frame.");
        frame.String("instructionPointerReference").Should().Be(pc);
    }

    /// <summary>
    ///  A configurationDone sent before the launch starts the machine once the launch is answered, and is used up
    ///  by that launch: the next launch waits for its own.
    /// </summary>
    [TestMethod]
    public void ConfigurationDoneBeforeLaunchStartsOnlyThatLaunch()
    {
        using DapTestClient client = new();
        client.Request("initialize", []);
        client.Request("setExceptionBreakpoints", new JsonObject { ["filters"] = new JsonArray("machineReset") });
        client.Request("configurationDone", []);
        client.Request("launch", IIPlus());
        client.Event("stopped").String("description").Should().Be(PowerOn);

        client.Request("launch", IIPlus());
        client.NoStop(TimeSpan.FromMilliseconds(500), "the second launch waits for its own configurationDone");
        client.Request("configurationDone", []);
        client.Event("stopped").String("description").Should().Be(PowerOn);
    }
}
