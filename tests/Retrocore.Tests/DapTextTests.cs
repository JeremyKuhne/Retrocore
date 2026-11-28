// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Debug;
using Retrocore.Machines.Apple1;
using System.Text;
using System.Text.Json.Nodes;

namespace Retrocore.Tests;

/// <summary>
///  The text-first adapter path exposes text without video and can run until text appears without blocking requests.
/// </summary>
[TestClass]
public sealed class DapTextTests
{
    private static readonly string s_inputs = Path.Join(AppContext.BaseDirectory, "Inputs");

    private static JsonObject Apple1(bool textOnly, bool fastIo = false) => new()
    {
        ["machine"] = "apple1",
        ["sdkRoms"] = s_inputs,
        ["stopOnEntry"] = true,
        ["textOnly"] = textOnly,
        ["ioMode"] = fastIo ? "fast" : null,
        ["speed"] = "max"
    };

    /// <summary>
    ///  An explicit legacy setting controls both project boot and the device preference unless a new mode is supplied.
    /// </summary>
    /// <param name="tape">Whether to check the tape or disk alias.</param>
    [TestMethod]
    [DataRow(data: true)]
    [DataRow(data: false)]
    public void LegacyMediaSpeedControlsProjectBoot(bool tape)
    {
        JsonObject launch = Apple1(textOnly: true);
        MediaSpeedPolicy policy = new(Apple1DebugTarget.Launch(launch));
        policy.Boot(tape).Should().Be(MediaSpeed.Fast, "an unspecified project boot is unpaced");
        launch[tape ? "fastCassette" : "fastDisk"] = false;
        policy.Apply(MediaSpeedPolicy.LaunchModes(launch));
        policy.Boot(tape).Should().Be(MediaSpeed.Normal);
        MediaSpeedPolicy.LaunchMode(launch, tape).Should().Be(MediaSpeed.Normal);

        launch[tape ? "tapeSpeed" : "diskSpeed"] = "skip";
        policy.Apply(MediaSpeedPolicy.LaunchModes(launch));
        policy.Boot(tape).Should().Be(MediaSpeed.Skip);
        MediaSpeedPolicy.LaunchMode(launch, tape).Should().Be(MediaSpeed.Skip);
    }

    /// <summary>
    ///  An explicit media mode overrides the legacy flag and remains selected independently of machine speed.
    /// </summary>
    [TestMethod]
    public void MediaSpeedCanChangeWithoutChangingMachineSpeed()
    {
        using DapTestClient client = new();
        client.Request("initialize", []);
        JsonObject launch = Apple1(textOnly: false);
        launch["fastCassette"] = false;
        launch["mediaSpeedDefaults"] = new JsonObject { ["tape"] = "skip" };
        Object(client.Request("launch", launch), "mediaSpeed").String("tape").Should().Be("normal");
        launch = Apple1(textOnly: false);
        launch["mediaSpeedDefaults"] = new JsonObject { ["tape"] = "normal" };
        launch["tapeSpeed"] = "skip";
        JsonObject started = client.Request("launch", launch);
        Object(started, "mediaSpeed").String("tape").Should().Be("skip");
        client.Request("configurationDone", []);
        client.Event("stopped").String("reason").Should().Be("entry");
        JsonObject requested = client.Request("retro/mediaSpeed", new JsonObject
        {
            ["kind"] = "tape", ["mode"] = "normal"
        });

        requested.String("tape").Should().Be("normal");
        client.Request("retro/mediaSpeed", []).String("tape").Should().Be("normal");
        client.Fails("retro/mediaSpeed", new JsonObject
        {
            ["kind"] = "tape", ["mode"] = "invalid"
        }).Should().Contain("normal, fast or skip");

        client.Request("retro/mediaSpeed", []).String("tape").Should().Be("normal");
    }

    /// <summary>
    ///  Normal disables the target's legacy acceleration while an Apple-1 cassette is actually playing.
    /// </summary>
    [TestMethod]
    public void NormalTapePacesAnActiveLegacyDrive()
    {
        JsonObject launch = Apple1(textOnly: true);
        launch["fastCassette"] = true;
        Apple1DebugTarget target = Apple1DebugTarget.Launch(launch);
        Apple1CassetteDrive drive = target.Machine.CassetteDrive ?? throw new AssertFailedException("No cassette drive.");
        drive.Play(new Apple1Tape([100, 100]), "tape");
        MediaSpeedPolicy policy = new(target);
        policy.Accelerated.Should().BeTrue();

        launch["tapeSpeed"] = "normal";
        policy.Apply(MediaSpeedPolicy.LaunchModes(launch));
        target.Accelerated.Should().BeFalse();
        policy.Accelerated.Should().BeFalse();

        policy.Set(tape: false, MediaSpeed.Fast);
        policy.Accelerated.Should().BeFalse("the disk setting cannot unthrottle tape");
        policy.Set(tape: true, MediaSpeed.Fast);
        policy.Accelerated.Should().BeTrue();
    }

    /// <summary>
    ///  Failing to construct a replacement machine invalidates the old media policy.
    /// </summary>
    [TestMethod]
    public void FailedReplacementLaunchDoesNotExposeOldMediaSettings()
    {
        using DapTestClient client = new();
        client.Request("initialize", []);
        JsonObject launch = Apple1(textOnly: true);
        launch["tapeSpeed"] = "skip";
        client.Request("launch", launch);
        client.Request("retro/mediaSpeed", []).String("tape").Should().Be("skip");

        client.Fails("launch", new JsonObject { ["machine"] = "pet", ["model"] = "unknown" }).Should().Contain("model");
        client.Fails("retro/mediaSpeed", []).Should().Contain("No machine has been launched");

        client.Request("launch", Apple1(textOnly: true));
        client.Request("retro/mediaSpeed", []).String("tape").Should().Be("fast");
    }

    /// <summary>
    ///  Invalid media settings are rejected before the active machine and its preferences are replaced.
    /// </summary>
    /// <param name="option">The invalid launch option.</param>
    [TestMethod]
    [DataRow("tapeSpeed")]
    [DataRow("diskSpeed")]
    public void InvalidMediaSpeedDoesNotReplaceTheCurrentTarget(string option)
    {
        using DapTestClient client = new();
        client.Request("initialize", []);
        JsonObject launch = Apple1(textOnly: true);
        launch["tapeSpeed"] = "skip";
        client.Request("launch", launch);
        client.Request("configurationDone", []);
        client.Event("stopped").String("reason").Should().Be("entry");

        JsonObject replacement = Apple1(textOnly: true);
        replacement[option] = "invalid";
        client.Fails("launch", replacement).Should().Contain("normal, fast or skip");
        client.Request("retro/mediaSpeed", []).String("tape").Should().Be("skip");
        client.Request("retro/text", []).String("machine").Should().Be("apple1");
    }

    /// <summary>
    ///  Text-only sessions return the terminal buffer, suppress frame events, and complete text waits asynchronously.
    /// </summary>
    [TestMethod]
    public void TextOnlySessionReadsTextAndRunsUntilMatchedOrOutOfBudget()
    {
        using DapTestClient client = new();
        client.Request("initialize", []);
        client.Request("launch", Apple1(textOnly: true, fastIo: true));
        client.Request("configurationDone", []);
        client.Event("stopped").String("reason").Should().Be("entry");

        JsonObject text = client.Request("retro/text", []);
        text.String("machine").Should().Be("apple1");
        text.Int("columns").Should().Be(40);
        (text["rows"] as JsonArray).Should().HaveCount(24);
        text["pixels"].Should().BeNull();
        JsonObject screen = client.Request("retro/snapshot", new JsonObject { ["surface"] = "screen" });
        screen.String("semantics").Should().Be("displayBuffer");
        screen.Long("cycles").Should().Be(text.Long("cycles"));
        JsonObject video = Object(screen, "video");
        int bytes = Field<int>(video, "width") * Field<int>(video, "height") * 4;
        Convert.FromBase64String(Field<string>(video, "pixels")).Length.Should().Be(bytes);
        client.NoEvent("retro/frame", TimeSpan.FromMilliseconds(100));
        client.NoEvent("retro/cycles", TimeSpan.FromMilliseconds(100));

        JsonObject firstWait = client.Request("retro/runUntil", new JsonObject
        {
            ["stopOn"] = new JsonObject { ["kind"] = "screenContains", ["contains"] = " " },
            ["snapshot"] = new JsonObject { ["surface"] = "visibleText" },
            ["maxCycles"] = 50_000
        });

        JsonObject matched = Result(client, firstWait);
        matched.String("outcome").Should().Be("matched");
        JsonObject matchedText = Object(matched, "snapshot");
        matchedText["rows"].Should().NotBeNull();
        client.Event("stopped").String("reason").Should().Be("pause");
        client.NoEvent("retro/frame", TimeSpan.FromMilliseconds(100));
        client.NoEvent("retro/cycles", TimeSpan.FromMilliseconds(100));

        JsonObject never = new() { ["kind"] = "screenContains", ["contains"] = "NO TEXT BUFFER WILL CONTAIN THIS" };
        JsonObject exhausted = Result(client, StartRun(client, never.DeepClone().AsObject(), maxCycles: 1_000));
        exhausted.String("outcome").Should().Be("cycleBudgetExceeded");
        client.Event("stopped").String("reason").Should().Be("pause");
        client.NoEvent("retro/frame", TimeSpan.FromMilliseconds(100));

        JsonObject waiting = StartRun(client, never, maxCycles: long.MaxValue);
        string alreadyWaiting = client.Fails("retro/runUntil", new JsonObject
        {
            ["stopOn"] = new JsonObject { ["kind"] = "screenContains", ["contains"] = "another wait" },
            ["maxCycles"] = 1_000
        });

        alreadyWaiting.Should().Contain("already waiting");
        client.Request("pause", []);
        Result(client, waiting).String("outcome").Should().Be("stopped");
        client.Event("stopped").String("reason").Should().Be("pause");
        client.NoEvent("retro/frame", TimeSpan.FromMilliseconds(100));
    }

    /// <summary>
    ///  The default launch still sends its ordinary display frames.
    /// </summary>
    [TestMethod]
    public void DefaultSessionStillSendsFrames()
    {
        using DapTestClient client = new();
        client.Request("initialize", []);
        client.Request("launch", Apple1(textOnly: false));
        client.Request("configurationDone", []);
        client.Event("stopped").String("reason").Should().Be("entry");
        client.Event("retro/frame").Should().NotBeNull();
    }

    /// <summary>
    ///  Targets without a verified fast-I/O path reject the option instead of silently ignoring it.
    /// </summary>
    [TestMethod]
    public void FastIoIsRejectedForUnsupportedTargets()
    {
        using DapTestClient client = new();
        client.Request("initialize", []);
        string error = client.Fails("launch", new JsonObject
        {
            ["machine"] = "altair",
            ["ioMode"] = "fast"
        });

        error.Should().Contain("Fast I/O is not supported");
    }

    /// <summary>
    ///  Only the verified Monitor read parks scripted time. A RAM loop does not become a demand, even at a stable PC.
    /// </summary>
    [TestMethod]
    public void VerifiedDemandParksAndAnArbitraryLoopDoesNot()
    {
        using DapTestClient client = new();
        client.Request("initialize", []);
        client.Request("launch", Apple1(textOnly: true));
        client.Fails("retro/runUntil", new JsonObject { ["stopOn"] = Demand() }).Should().Contain("configurationDone");
        client.Request("configurationDone", []);
        client.Event("stopped").String("reason").Should().Be("entry");

        JsonObject ready = Run(client, Demand());
        ready.String("outcome").Should().Be("inputDemand");
        JsonObject waiting = Object(ready, "demand");
        waiting.String("profile").Should().Be("wozMonitor");
        waiting.Bool("running").Should().BeFalse();
        client.Request("retro/input/status", []).Long("cycles").Should().Be(ready.Long("cycles"));
        Write(client, 0x300, [0x4C, 0x03, 0x03, 0x4C, 0x03, 0x03]);
        JsonObject entered = Run(client, Instruction(0x0300), text: "0300R\n");
        entered.String("outcome").Should().Be("matched");
        JsonObject input = Object(entered, "input");
        input.Int("accepted").Should().Be(6);
        input.Int("acknowledged").Should().Be(6);
        input.Int("unconfirmed").Should().Be(0);

        JsonObject initial = Run(client, Instruction(0x0300), cycles: 1);
        initial.Long("cycles").Should().Be(initial.Long("startCycle"));
        JsonObject final = Run(client, Instruction(0x0303), cycles: 1);
        final.String("outcome").Should().Be("matched");
        final.Long("cycles").Should().Be(final.Long("startCycle") + 3, "there is at most one instruction of rounding");
        JsonObject unknown = Run(client, Demand(), text: "ABBA", cycles: 10);
        unknown.String("outcome").Should().Be("cycleBudgetExceeded");
        Object(unknown, "demand").String("status").Should().Be("unknown");
        Object(unknown, "input").Int("accepted").Should().Be(0);
        Object(unknown, "input").Int("cancelled").Should().Be(4);
    }

    /// <summary>
    ///  The deadline retires an unobserved receipt but only cancels bytes not yet sent to the device.
    /// </summary>
    [TestMethod]
    public void BudgetExpiryDoesNotRetractOrRetryAnInFlightByte()
    {
        using DapTestClient client = new();
        client.Request("initialize", []);
        Launch(client, Apple1(textOnly: true));
        Run(client, Demand()).String("outcome").Should().Be("inputDemand");

        JsonObject limited = Run(client, Demand(), text: "AB", cycles: 1);
        limited.String("outcome").Should().Be("cycleBudgetExceeded");
        JsonObject receipt = Object(limited, "input");
        receipt.Int("delivered").Should().Be(1);
        receipt.Int("accepted").Should().Be(0);
        receipt.Int("unconfirmed").Should().Be(1);
        receipt.Int("cancelled").Should().Be(1);
        receipt.Int("inFlight").Should().Be(0);

        Run(client, Demand()).String("outcome").Should().Be("inputDemand");
        JsonObject echoed = Run(client, new JsonObject { ["kind"] = "screenContains", ["contains"] = "A" });
        echoed.String("outcome").Should().Be("matched");
        Rows(client.Request("retro/text", [])).Should().Contain(line => line.TrimEnd() == "A");
        Object(client.Request("retro/input/status", []), "input").Int("accepted").Should().Be(0,
            "receipt ownership ended with the original run");
    }

    /// <summary>
    ///  Failed observations still send the correlated result and retire both pending and in-flight input.
    /// </summary>
    /// <param name="field">Which completion observation fails.</param>
    [TestMethod]
    [DataRow("demand")]
    [DataRow("snapshot")]
    [DataRow("receipt")]
    public void CompletionObservationFailureStillReportsTheRun(string field)
    {
        const string Failure = "Could not read the completion observation.";
        InputBatch input = new(7, ['A', 'B'], 0, guestDemand: true);
        input.Deliver(new("test", "keyboardDevice", _ => InputReceipt.Pending, ReadReceipt));
        InteractionRun run = new(17, 100, 5)
        {
            Condition = "instruction",
            Policy = "scripted",
            Surface = "visibleText",
            Snapshot = "screen",
            Input = input
        };

        List<(string Name, JsonObject Body)> events = [];
        run.ReportResult(
            launchId: 9,
            cycles: 105,
            outcome: "matched",
            readDemand: ReadDemand,
            readSnapshot: ReadSnapshot,
            textUpdateSurface: null,
            notify: (name, body) => events.Add((name, body)));

        events.Should().ContainSingle();
        (string name, JsonObject body) = events[0];
        name.Should().Be("retro/run/result");
        body.Long("launchId").Should().Be(9);
        body.Long("runId").Should().Be(17);
        Field<ulong>(body, "cycles").Should().Be(105);
        body.String("outcome").Should().Be("matched");
        Object(body, "observationErrors").String(field).Should().Be(Failure);
        body.ContainsKey("demand").Should().Be(field != "demand");
        body.ContainsKey("snapshot").Should().Be(field != "snapshot");
        JsonObject receipt = Object(body, "input");
        receipt.Int("unconfirmed").Should().Be(1);
        receipt.Int("cancelled").Should().Be(1);
        receipt.Int("inFlight").Should().Be(0);

        InputReceipt ReadReceipt(int _) =>
            field == "receipt" ? throw new InvalidOperationException(Failure) : InputReceipt.Pending;

        JsonObject ReadDemand()
        {
            if (field == "demand") { throw new InvalidDataException(Failure); }
            return new JsonObject { ["status"] = "unknown" };
        }

        JsonObject ReadSnapshot(string surface)
        {
            if (field == "snapshot") { throw new InvalidOperationException(Failure); }
            return new JsonObject { ["surface"] = surface };
        }
    }

    /// <summary>
    ///  Booting resident BASIC from the Monitor changes the verified PIA read while preserving repeated key input.
    /// </summary>
    [TestMethod]
    public void Apple1BasicRecognizesItsOwnInputLoop()
    {
        using DapTestClient client = new();
        client.Request("initialize", []);
        Launch(client, Apple1(textOnly: true));
        JsonObject ready = Run(client, Demand(), text: "E000R\n");
        Object(ready, "demand").String("profile").Should().Be("apple1Basic");
        JsonObject read = Run(client, Demand(), text: "PRINT 1221\n");
        Object(read, "input").Int("accepted").Should().Be(11);
        Rows(client.Request("retro/text", [])).Should().Contain(line => line.Trim() == "1221");
    }

    // The PET and BBC firmware boots wait synchronously for in-process emulator workers, apart from CPU-heavy tests.

    /// <summary>
    ///  The PET profiles deliver one byte per editor read, including repetitions, on each supported ROM/keyboard.
    /// </summary>
    /// <param name="model">The PET launch model.</param>
    /// <param name="version">The expected editor's BASIC version.</param>
    [TestMethod]
    [DoNotParallelize]
    [DataRow("pet2001", 1)]
    [DataRow("pet2001-basic2", 2)]
    [DataRow("pet4032", 4)]
    [DataRow("pet4032-business", 4)]
    public void PetTypesThroughTheActiveEditor(string model, int version)
    {
        using DapTestClient client = new();
        client.Request("initialize", []);
        Launch(client, new JsonObject
        {
            ["machine"] = "pet", ["model"] = model, ["textOnly"] = true, ["stopOnEntry"] = true, ["sound"] = "off", ["speed"] = "max"
        });

        const string Line = "PRINT \"BOOKKEEPER\"\n";
        JsonObject result = Run(client, Demand(), text: Line, cycles: 12_000_000);
        Object(result, "demand").String("profile").Should().Be($"petBasic{version}Editor");
        Object(result, "input").Int("accepted").Should().Be(Line.Length);
        Rows(client.Request("retro/text", [])).Should().Contain(line => line.Trim().Equals("BOOKKEEPER", StringComparison.OrdinalIgnoreCase));
    }

    /// <summary>
    ///  A redirected or replaced BBC input vector must not match even at the same MOS wait address.
    /// </summary>
    [TestMethod]
    [DoNotParallelize]
    public void BbcDemandRequiresItsNormalInputRoute()
    {
        using DapTestClient client = new();
        client.Request("initialize", []);
        Launch(client, new JsonObject
        {
            ["machine"] = "bbc", ["textOnly"] = true, ["stopOnEntry"] = true, ["sound"] = "off", ["speed"] = "max"
        });

        JsonObject ready = Run(client, Demand(), cycles: 12_000_000);
        Object(ready, "demand").String("profile").Should().Be("bbcMos120Rdch");
        JsonObject timed = Run(client, Demand(), text: "PRINT INKEY(100)\n", cycles: 500_000);
        timed.String("outcome").Should().Be("cycleBudgetExceeded", "the MOS wait has a real guest-time deadline");
        Object(timed, "input").Int("accepted").Should().Be(17);
        Run(client, Demand(), cycles: 5_000_000).String("outcome").Should().Be("inputDemand");
        Write(client, 0x0241, [1]);
        client.Request("retro/input/status", []).String("status").Should().Be("unknown");
        Write(client, 0x0241, [0]);
        client.Request("retro/input/status", []).String("status").Should().Be("waiting");
        Write(client, 0x0210, [0, 3]);
        client.Request("retro/input/status", []).String("status").Should().Be("unknown");
    }

    /// <summary>
    ///  The BBC snapshot reports teletext geometry and recognizes the pound glyph in the 80-column bitmap mode.
    /// </summary>
    [TestMethod]
    [DoNotParallelize]
    public void BbcSnapshotFollowsTheCrtcAndCharset()
    {
        using DapTestClient client = new();
        client.Request("initialize", []);
        Launch(client, new JsonObject
        {
            ["machine"] = "bbc", ["textOnly"] = true, ["stopOnEntry"] = true, ["sound"] = "off", ["speed"] = "max"
        });

        Run(client, Demand(), cycles: 12_000_000).String("outcome").Should().Be("inputDemand");
        JsonObject teletext = client.Request("retro/text", []);
        teletext.Int("columns").Should().Be(40);
        teletext.String("decoding").Should().Be("bbcTeletextCodes");

        Run(client, Demand(), text: "MODE 0\nPRINT \"£\"\n").String("outcome").Should().Be("inputDemand");
        JsonObject bitmap = client.Request("retro/text", []);
        bitmap.Int("columns").Should().Be(80);
        bitmap.Int("rowCount").Should().Be(32);
        bitmap.String("decoding").Should().Be("bbcMosFontInference");
        Rows(bitmap).Should().Contain(line => line.Trim() == "£");
    }

    /// <summary>
    ///  The configured input-wait update describes the same boundary as the result, not a later periodic sample.
    /// </summary>
    [TestMethod]
    public void ConfiguredInputWaitUpdateUsesTheParkedBoundary()
    {
        using DapTestClient client = new();
        client.Request("initialize", []);
        JsonObject launch = Apple1(textOnly: true);
        launch["textPolicy"] = "onInputWait";
        Launch(client, launch);

        JsonObject request = new() { ["stopOn"] = Demand(), ["snapshot"] = new JsonObject { ["surface"] = "editor" } };
        JsonObject result = Result(client, client.Request("retro/runUntil", request));
        Object(result, "snapshot").Bool("supported").Should().BeFalse();
        JsonObject update = client.Event("retro/text/update");
        update.String("surface").Should().Be("visibleText");
        update.Long("launchId").Should().Be(result.Long("launchId"));
        update.Long("cycles").Should().Be(result.Long("cycles"));
        client.Event("stopped").String("reason").Should().Be("pause");
    }

    /// <summary>
    ///  Live observations do not park guest time, and lifecycle actions each retire the matching run once.
    /// </summary>
    [TestMethod]
    public void LiveAndLifecycleKeepRunOwnership()
    {
        using DapTestClient client = new();
        client.Request("initialize", []);
        Launch(client, Apple1(textOnly: true));
        JsonObject live = Run(client, Demand(), policy: "live");
        Object(live, "demand").Bool("running").Should().BeTrue();
        ulong first = Field<ulong>(live, "cycles");
        SpinWait.SpinUntil(() => Field<ulong>(client.Request("retro/input/status", []), "cycles") > first, 1000)
            .Should().BeTrue("the live worker keeps ticking the verified poll");

        JsonObject never = new() { ["kind"] = "screenContains", ["contains"] = "never appears" };
        JsonObject waiting = StartRun(client, never, maxCycles: long.MaxValue);
        JsonObject id = Identity(waiting);
        id["launchId"] = waiting.Long("launchId") + 1;
        client.Request("retro/run/cancel", id).Bool("cancelled").Should().BeFalse();
        client.Fails("next", []).Should().Contain("automation run");
        client.Request("retro/run/cancel", Identity(waiting)).Bool("cancelled").Should().BeTrue();
        Result(client, waiting).String("outcome").Should().Be("cancelled");
        client.Event("stopped").String("reason").Should().Be("pause");
        client.Request("retro/run/cancel", Identity(waiting)).Bool("cancelled").Should().BeFalse();

        waiting = StartRun(client, never.DeepClone().AsObject(), maxCycles: long.MaxValue);
        client.Request("pause", new JsonObject { ["threadId"] = 2 });
        Result(client, waiting).String("outcome").Should().Be("stopped");
        client.Event("stopped").String("reason").Should().Be("pause");

        waiting = StartRun(client, never.DeepClone().AsObject(), maxCycles: long.MaxValue);
        client.Request("retro/reset", []);
        Result(client, waiting).String("outcome").Should().Be("reset");
        JsonObject resetStop = client.Event("stopped");
        resetStop.String("reason").Should().Be("pause");
        resetStop.Bool("allThreadsStopped").Should().BeTrue();
        client.Request("retro/input/status", []).Bool("running").Should().BeFalse();

        waiting = StartRun(client, never.DeepClone().AsObject(), maxCycles: long.MaxValue, policy: "live");
        client.Request("retro/reset", []);
        Result(client, waiting).String("outcome").Should().Be("reset");
        client.Request("retro/input/status", []).Bool("running").Should().BeTrue();

        waiting = StartRun(client, never.DeepClone().AsObject(), maxCycles: long.MaxValue);
        client.Request("launch", Apple1(textOnly: true));
        Result(client, waiting).String("outcome").Should().Be("replaced");
        client.Request("configurationDone", []);
        client.Event("stopped").String("reason").Should().Be("entry");
        JsonObject next = StartRun(client, never.DeepClone().AsObject(), maxCycles: long.MaxValue);
        next.Long("launchId").Should().NotBe(waiting.Long("launchId"));
        client.Request("retro/run/cancel", Identity(waiting)).Bool("cancelled").Should().BeFalse();
        client.Request("disconnect", []);
        Result(client, next).String("outcome").Should().Be("disconnected");
    }

    /// <summary>
    ///  Fresh matching rejects a stale screen, and a named sink sees actual terminal bytes across batched reads.
    /// </summary>
    [TestMethod]
    public void ScreenFreshnessAndConsoleCaptureAreSeparate()
    {
        using DapTestClient client = new();
        client.Request("initialize", []);
        JsonObject launch = Apple1(textOnly: true, fastIo: true);
        launch["consoleCapture"] = new JsonObject { ["sink"] = "apple1Terminal", ["capacity"] = 16 };
        Launch(client, launch);
        JsonObject stale = Run(client, new JsonObject
        {
            ["kind"] = "screenContains", ["contains"] = " ", ["fresh"] = true
        }, cycles: 250);

        stale.String("outcome").Should().Be("cycleBudgetExceeded");
        Run(client, Demand()).String("outcome").Should().Be("inputDemand");
        JsonObject prefix = client.Request("retro/console/read", []);
        string prefixText = Encoding.ASCII.GetString(Convert.FromBase64String(Field<string>(prefix, "data")));
        prefixText.Should().EndWith("\r");

        JsonObject match = Run(client, new JsonObject
        {
            ["kind"] = "transcriptContains", ["contains"] = "ABBA"
        }, text: "ABBA");

        match.String("outcome").Should().Be("matched");
        JsonObject first = client.Request("retro/console/read", new JsonObject { ["maxBytes"] = 2 });
        JsonObject last = client.Request("retro/console/read", []);
        first.Long("offset").Should().Be(prefix.Long("count"));
        last.Long("offset").Should().Be(first.Long("offset") + 2);
        Field<ulong>(first, "firstCycle").Should().BeLessThan(Field<ulong>(last, "lastCycle"));
        string text = Encoding.ASCII.GetString(Convert.FromBase64String(Field<string>(first, "data")))
            + Encoding.ASCII.GetString(Convert.FromBase64String(Field<string>(last, "data")));

        text.Should().Be("ABBA");

        JsonObject overflow = Run(client, Demand(), text: new string('A', 24), stopped: "exception");
        overflow.String("outcome").Should().Be("captureOverflow");
        JsonObject retained = client.Request("retro/console/read", []);
        retained.Bool("overflow").Should().BeTrue();
        retained.Int("count").Should().Be(16);
    }

    private static void Launch(DapTestClient client, JsonObject launch)
    {
        client.Request("launch", launch);
        client.Request("configurationDone", []);
        client.Event("stopped").String("reason").Should().Be("entry");
    }

    private static JsonObject Object(JsonObject body, string field) =>
        body.Object(field) ?? throw new AssertFailedException($"Missing object '{field}' in {body}.");

    private static T Field<T>(JsonObject body, string field) =>
        (body[field] ?? throw new AssertFailedException($"Missing '{field}' in {body}.")).GetValue<T>();

    private static IEnumerable<string> Rows(JsonObject snapshot) =>
        (snapshot["rows"] as JsonArray ?? throw new AssertFailedException("No screen rows.")).Select(row => row?.GetValue<string>() ?? "");

    private static JsonObject Demand() => new() { ["kind"] = "inputDemand" };

    private static JsonObject Instruction(int address) => new() { ["kind"] = "instruction", ["address"] = address };

    private static JsonObject Identity(JsonObject run) => new()
    {
        ["launchId"] = run.Long("launchId"),
        ["runId"] = run.Long("runId")
    };

    private static JsonObject StartRun(
        DapTestClient client, JsonObject stopOn, long maxCycles, string? text = null, string policy = "scripted") =>
            client.Request("retro/runUntil", new JsonObject
            {
                ["policy"] = policy,
                ["maxCycles"] = maxCycles,
                ["stopOn"] = stopOn,
                ["input"] = text is null ? null : new JsonObject { ["text"] = text }
            });

    private static JsonObject Result(DapTestClient client, JsonObject run)
    {
        JsonObject result = client.Event("retro/run/result");
        result.Long("launchId").Should().Be(run.Long("launchId"));
        result.Long("runId").Should().Be(run.Long("runId"));
        return result;
    }

    private static JsonObject Run(
        DapTestClient client, JsonObject stopOn, string? text = null, long cycles = 1_000_000, string policy = "scripted",
        string stopped = "pause")
    {
        JsonObject result = Result(client, StartRun(client, stopOn, cycles, text, policy));
        if (policy == "scripted") { client.Event("stopped").String("reason").Should().Be(stopped); }
        return result;
    }

    private static void Write(DapTestClient client, int address, byte[] bytes) =>
        client.Request("writeMemory", new JsonObject
        {
            ["memoryReference"] = $"0x{address:X4}",
            ["data"] = Convert.ToBase64String(bytes)
        });
}
