// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using System.Text.Json.Nodes;

namespace Retrocore.Debug;

/// <summary>
///  Owns unsent keys and at most one awaiting a verified receipt.
/// </summary>
/// <param name="id">The session's batch identifier.</param>
/// <param name="codes">The mapped key codes, in input order.</param>
/// <param name="skipped">The number of characters skipped during mapping.</param>
/// <param name="guestDemand">Whether delivery requires observed guest demand.</param>
internal sealed class InputBatch(long id, List<int> codes, int skipped, bool guestDemand)
{
    private int _next;
    private GuestInputPath? _path;
    private int _key;
    private bool _acknowledged;
    private string? _backend;
    private int _accepted;
    private int _acknowledgements;
    private int _cancelled;

    /// <summary>
    ///  Gets whether delivery requires observed guest demand.
    /// </summary>
    internal bool GuestDemand => guestDemand;

    /// <summary>
    ///  Gets the number of bytes still owned by the host.
    /// </summary>
    internal int Pending => codes.Count - _next;

    /// <summary>
    ///  Gets the number of bytes sent to the device or guest buffer.
    /// </summary>
    internal int Delivered { get; private set; }

    /// <summary>
    ///  Gets the number of bytes the backend refused.
    /// </summary>
    internal int Rejected { get; private set; }

    /// <summary>
    ///  Gets the number of guest-demand deliveries whose disposition could not be verified.
    /// </summary>
    internal int Unconfirmed { get; private set; }

    /// <summary>
    ///  Gets whether a guest-demand delivery is awaiting its receipt.
    /// </summary>
    internal bool InFlight => _path is not null;

    /// <summary>
    ///  Gets whether the host has unsent input or a receipt in flight.
    /// </summary>
    internal bool NeedsInput => Pending != 0 || InFlight;

    /// <summary>
    ///  Attempts to deliver the next key to an ordinary device.
    /// </summary>
    /// <param name="target">The machine that owns the device.</param>
    /// <param name="key">The attempted key, for pacing before the next one.</param>
    internal void DeliverPhysical(IDebugTarget target, out int key)
    {
        key = codes[_next++];
        if (target.Key(key)) { Delivered++; }
        else { Rejected++; }
    }

    /// <summary>
    ///  Delivers one key using the verified demand at the current guest cycle.
    /// </summary>
    /// <param name="path">The verified path.</param>
    internal void Deliver(GuestInputPath path)
    {
        _backend = path.Backend;
        _path = path;
        _key = codes[_next++];
        _acknowledged = false;
        Receive(path.Send(_key));
    }

    /// <summary>
    ///  Samples receipt of the single key in flight.
    /// </summary>
    internal void Observe()
    {
        if (_path is { Observe: { } observe }) { Receive(observe(_key), sending: false); }
    }

    private void Receive(InputReceipt receipt, bool sending = true)
    {
        if (sending && receipt != InputReceipt.Rejected) { Delivered++; }
        if (_path?.Observe is not null
            && !_acknowledged
            && receipt is InputReceipt.Acknowledged or InputReceipt.Accepted)
        {
            _acknowledged = true;
            _acknowledgements++;
        }

        switch (receipt)
        {
            case InputReceipt.Pending or InputReceipt.Acknowledged:
                return;
            case InputReceipt.Accepted:
                _accepted++;
                break;
            case InputReceipt.Rejected:
                Rejected++;
                break;
            case InputReceipt.Unconfirmed:
                Unconfirmed++;
                break;
        }

        _path = null;
    }

    /// <summary>
    ///  Cancels unsent input and retires an unresolved receipt without retracting the key.
    /// </summary>
    internal void Cancel()
    {
        _cancelled += Pending;
        _next = codes.Count;
        if (_path is null) { return; }
        Unconfirmed++;
        _path = null;
    }

    /// <summary>
    ///  Snapshots the batch counters without implying application consumption.
    /// </summary>
    /// <returns>The protocol representation.</returns>
    internal JsonObject ToJson() => new()
    {
        ["batchId"] = id,
        ["backend"] = GuestDemand ? "guestDemand" : "physical",
        ["delivery"] = _backend,
        ["mapped"] = codes.Count,
        ["skipped"] = skipped,
        ["pending"] = Pending,
        ["delivered"] = Delivered,
        ["acknowledged"] = GuestDemand && _backend is "keyboardDevice" ? _acknowledgements : null,
        ["accepted"] = GuestDemand ? _accepted : null,
        ["rejected"] = Rejected,
        ["inFlight"] = InFlight ? 1 : 0,
        ["unconfirmed"] = GuestDemand ? Unconfirmed : Delivered,
        ["cancelled"] = _cancelled
    };
}
