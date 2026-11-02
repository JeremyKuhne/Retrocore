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
 * @returns The client: request(command, args), event(name), events (unclaimed), fail(error), close() and failure().
 */
export function startDap(root) {
    const host = process.env.RETROCORE_DAP_HOST;
    const child = host
        ? spawn(host, [])
        : spawn("dotnet", [join(root, "artifacts", "AnyCPU", "Release", "Retrocore.Debug", "net10.0", "Retrocore.Debug.dll")]);
    let buffer = Buffer.alloc(0);
    let sequence = 1;
    const pending = new Map();
    const events = [];
    const listeners = [];
    let failure;
    child.stderr.on("data", data => process.stderr.write(data));
    child.on("error", error => { failure = error; });
    function fail(error) {
        failure = error;
        for (const waiter of pending.values()) waiter.reject(error);
        pending.clear();
        for (const listener of listeners.splice(0)) listener.reject(error);
        child.kill();
    }
    child.on("exit", code => {
        if (pending.size !== 0 || listeners.length !== 0) fail(new Error(`DAP host exited while requests were pending: ${code}`));
    });
    child.stdout.on("data", data => {
        buffer = Buffer.concat([buffer, data]);
        while (true) {
            const end = buffer.indexOf("\r\n\r\n");
            if (end < 0) break;
            const header = buffer.subarray(0, end).toString("ascii");
            const match = /^Content-Length:\s*(\d+)/im.exec(header);
            if (!match) throw new Error(`Unexpected DAP stdout: ${header}`);
            const length = Number(match[1]);
            if (buffer.length < end + 4 + length) break;
            const message = JSON.parse(buffer.subarray(end + 4, end + 4 + length).toString("utf8"));
            buffer = buffer.subarray(end + 4 + length);
            if (message.type === "response") {
                const waiter = pending.get(message.request_seq);
                if (waiter) {
                    pending.delete(message.request_seq);
                    message.success ? waiter.resolve(message.body) : waiter.reject(new Error(message.message ?? JSON.stringify(message)));
                }
            } else if (message.type === "event") {
                const index = listeners.findIndex(listener => listener.name === message.event);
                if (index >= 0) listeners.splice(index, 1)[0].resolve(message.body);
                else events.push(message);
            }
        }
    });
    function request(command, args = {}) {
        return new Promise((resolve, reject) => {
            const seq = sequence++;
            pending.set(seq, { resolve, reject });
            const data = JSON.stringify({ seq, type: "request", command, arguments: args });
            child.stdin.write(`Content-Length: ${Buffer.byteLength(data)}\r\n\r\n${data}`);
        });
    }
    function event(name) {
        const index = events.findIndex(message => message.event === name);
        if (index >= 0) return Promise.resolve(events.splice(index, 1)[0].body);
        return new Promise((resolve, reject) => listeners.push({ name, resolve, reject }));
    }
    return { request, event, events, fail, close: () => child.kill(), failure: () => failure };
}
