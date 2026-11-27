// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using System.Text.Json.Nodes;

namespace Retrocore.Debug;

/// <summary>
///  One session-owned execution condition, sampled under the emulation gate.
/// </summary>
/// <param name="id">The correlation ID within the session.</param>
/// <param name="start">The guest cycle at reservation.</param>
/// <param name="budget">The maximum requested guest advancement, before boundary rounding.</param>
internal sealed class InteractionRun(long id, ulong start, ulong budget)
{
    /// <summary>
    ///  Gets the correlation ID.
    /// </summary>
    internal long Id { get; } = id;

    /// <summary>
    ///  Gets the guest cycle at reservation.
    /// </summary>
    internal ulong Start { get; } = start;

    /// <summary>
    ///  Gets the deadline, saturated at the largest cycle count.
    /// </summary>
    internal ulong Deadline { get; } = start + Math.Min(budget, ulong.MaxValue - start);

    /// <summary>
    ///  Gets the observation that finishes this run.
    /// </summary>
    internal required string Condition { get; init; }

    /// <summary>
    ///  Gets the guest-time policy, independent of input delivery.
    /// </summary>
    internal required string Policy { get; init; }

    /// <summary>
    ///  Gets the optional surface to return at completion.
    /// </summary>
    internal required string? Snapshot { get; init; }

    /// <summary>
    ///  Gets the surface a text condition samples.
    /// </summary>
    internal required string Surface { get; init; }

    /// <summary>
    ///  Gets the screen substring to look for.
    /// </summary>
    internal string? Contains { get; init; }

    /// <summary>
    ///  Gets the optional CPU address that finishes an instruction run.
    /// </summary>
    internal ushort? Address { get; init; }

    /// <summary>
    ///  Gets the optional incremental matcher for new console bytes.
    /// </summary>
    internal ConsoleMatch? Transcript { get; init; }

    /// <summary>
    ///  Gets the input batch owned by this run, if supplied.
    /// </summary>
    internal InputBatch? Input { get; init; }

    /// <summary>
    ///  Gets or sets the guest cycle of the last screen sample, if any.
    /// </summary>
    internal ulong? LastSample { get; set; }

    /// <summary>
    ///  Gets or sets whether a sampled screen match can finish the run.
    /// </summary>
    internal bool MatchArmed { get; set; }

    /// <summary>
    ///  Retires the input and sends the correlated result even if a completion observation fails.
    /// </summary>
    /// <param name="launchId">The launch that owns the run.</param>
    /// <param name="cycles">The guest cycle at completion.</param>
    /// <param name="outcome">Why the run finished.</param>
    /// <param name="readDemand">Reads the final input status.</param>
    /// <param name="readSnapshot">Reads a named surface at the completion boundary.</param>
    /// <param name="textUpdateSurface">The configured input-wait update surface, or null.</param>
    /// <param name="notify">Sends the ordered events.</param>
    internal void ReportResult(
        long launchId,
        ulong cycles,
        string outcome,
        Func<JsonObject> readDemand,
        Func<string, JsonObject> readSnapshot,
        string? textUpdateSurface,
        Action<string, JsonObject> notify)
    {
        JsonObject body = new()
        {
            ["launchId"] = launchId,
            ["runId"] = Id,
            ["outcome"] = outcome,
            ["cycles"] = cycles,
            ["startCycle"] = Start
        };

        JsonObject? errors = null;
        JsonObject? update = null;
        try
        {
            InputBatch? batch = Input;
            try
            {
                if (batch is { InFlight: true }) { Observe("receipt", batch.Observe); }
            }
            finally
            {
                batch?.Cancel();
                body["input"] = batch?.ToJson();
            }

            Observe("demand", () => body["demand"] = readDemand());
            if (Snapshot is { } surface)
            {
                Observe("snapshot", () => body["snapshot"] = readSnapshot(surface));
            }

            if (textUpdateSurface is not null)
            {
                Observe("textUpdate", () => update = readSnapshot(textUpdateSurface));
            }
        }
        finally
        {
            if (errors is not null) { body["observationErrors"] = errors; }
            notify("retro/run/result", body);
        }

        if (update is not null) { notify("retro/text/update", update); }

        void Observe(string field, Action read)
        {
            string? error = "The observation failed unexpectedly.";
            try
            {
                read();
                error = null;
            }
            catch (Exception exception) when (exception is InvalidOperationException
                or ArgumentException
                or InvalidDataException
                or IOException
                or UnauthorizedAccessException
                or FormatException
                or OverflowException)
            {
                error = exception.Message;
            }
            finally
            {
                if (error is not null) { (errors ??= new())[field] = error; }
            }
        }
    }
}
