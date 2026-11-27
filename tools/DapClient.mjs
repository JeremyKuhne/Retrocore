// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

// A minimal Debug Adapter Protocol client for the integration scripts: it starts the debug host, frames
// requests and responses, and queues events until a script waits for them.

import { spawn } from "node:child_process";
import { join } from "node:path";

/**
 * Starts the Release debug host, or the executable RETROCORE_DAP_HOST names, such as a native build from
 * dotnet publish src/Retrocore.Debug -c Release -r win-x64 -p:RetrocoreAot=true.
 * @param {string} root The repository root.
 * @returns The client: request(command, args), event(name, predicate?), events (unclaimed), fail(error), close(),
 *  endInput(), failure() and received().
 */
export function startDap(root) {
    const host = process.env.RETROCORE_DAP_HOST;
    const child = host
        ? spawn(host, [])
        : spawn("dotnet", [join(root, "artifacts", "AnyCPU", "Release", "Retrocore.Debug", "net11.0", "Retrocore.Debug.dll")]);
    let buffer = Buffer.alloc(64 * 1024);
    let start = 0;
    let end = 0;
    let headerSize = 0;
    let contentLength = 0;
    let sequence = 1;
    const pending = new Map();
    const events = [];
    const listeners = [];
    let failure;
    let ended = false;
    let closing = false;
    let receivedBytes = 0;
    let receivedMessages = 0;
    child.stderr.on("data", data => process.stderr.write(data));
    child.on("error", fail);
    child.stdin.on("error", fail);
    function rejectWaiters(error) {
        for (const waiter of pending.values()) waiter.reject(error);
        pending.clear();
        for (const listener of listeners.splice(0)) listener.reject(error);
    }
    function fail(error) {
        failure ??= error;
        rejectWaiters(failure);
        child.kill();
    }

    // "exit" can precede the last stdout chunk, including the final response or run result.
    const closed = new Promise(resolve => child.once("close", (code, signal) => {
        ended = true;
        if (pending.size !== 0 || listeners.length !== 0) {
            fail(new Error(`DAP host closed before answering requests or events: ${code ?? signal}`));
        } else if (!closing && (code !== 0 || end !== start)) {
            fail(new Error(`DAP host closed unexpectedly: ${code ?? signal}${end === start ? "" : " (truncated frame)"}`));
        }
        resolve(code);
    }));
    child.stdout.on("data", data => {
        if (failure) return;
        try { consume(data); } catch (error) { fail(error); }
    });

    function consume(data) {
        receivedBytes += data.length;
        const remaining = end - start;
        if (buffer.length - end < data.length) {
            if (buffer.length - remaining >= data.length) {
                buffer.copy(buffer, 0, start, end);
                start = 0;
                end = remaining;
            } else {
                let capacity = buffer.length;
                while (capacity < remaining + data.length) capacity *= 2;
                const grown = Buffer.allocUnsafe(capacity);
                buffer.copy(grown, 0, start, end);
                buffer = grown;
                start = 0;
                end = remaining;
            }
        }

        data.copy(buffer, end);
        end += data.length;
        while (start < end) {
            if (headerSize === 0) {
                const headerEnd = buffer.subarray(0, end).indexOf("\r\n\r\n", start);
                if (headerEnd < 0) break;
                const header = buffer.toString("ascii", start, headerEnd);
                const match = /^Content-Length:[ \t]*(\d+)\r?$/im.exec(header);
                if (!match) throw new Error(`Unexpected DAP stdout: ${header}`);
                contentLength = Number(match[1]);
                if (!Number.isSafeInteger(contentLength)) throw new Error("Invalid DAP Content-Length.");
                headerSize = headerEnd + 4 - start;
            }
            const messageStart = start + headerSize;
            const messageEnd = messageStart + contentLength;
            if (end < messageEnd) break;
            const message = JSON.parse(buffer.subarray(messageStart, messageEnd).toString("utf8"));
            receivedMessages++;
            start = messageEnd;
            headerSize = 0;
            if (message.type === "response") {
                const waiter = pending.get(message.request_seq);
                if (waiter) {
                    pending.delete(message.request_seq);
                    message.success ? waiter.resolve(message.body) : waiter.reject(new Error(message.message ?? JSON.stringify(message)));
                }
            } else if (message.type === "event") {
                const index = listeners.findIndex(listener => listener.name === message.event && listener.matches(message.body));
                if (index >= 0) listeners.splice(index, 1)[0].resolve(message.body);
                else events.push(message);
            }
        }

        if (start === end) start = end = 0;
    }
    function request(command, args = {}) {
        if (ended || failure) return Promise.reject(failure ?? new Error("DAP host is closed."));
        return new Promise((resolve, reject) => {
            const seq = sequence++;
            pending.set(seq, { resolve, reject });
            const data = JSON.stringify({ seq, type: "request", command, arguments: args });
            child.stdin.write(`Content-Length: ${Buffer.byteLength(data)}\r\n\r\n${data}`);
        });
    }
    function event(name, matches = () => true) {
        const index = events.findIndex(message => message.event === name && matches(message.body));
        if (index >= 0) return Promise.resolve(events.splice(index, 1)[0].body);
        if (ended || failure) return Promise.reject(failure ?? new Error(`DAP host closed before ${name}.`));
        return new Promise((resolve, reject) => listeners.push({ name, matches, resolve, reject }));
    }
    // Closes the adapter's input without a disconnect, as a client that goes away does, and waits for it to exit.
    function endInput() {
        child.stdin.end();
        return closed;
    }
    function close() {
        closing = true;
        child.kill();
    }
    return {
        request, event, events, fail, close, endInput, failure: () => failure,
        received: () => ({ bytes: receivedBytes, messages: receivedMessages })
    };
}
