// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

import * as assert from "node:assert/strict";
import { test } from "node:test";
import { Script, createContext } from "node:vm";
import { webviewHtml } from "../display";

function panelScript(): string {
    const html = webviewHtml("NONCE");
    const open = '<script nonce="NONCE">';
    const start = html.indexOf(open);
    const end = html.lastIndexOf("</script>");
    assert.ok(start >= 0 && end > start, "the page has its script");
    return html.slice(start + open.length, end);
}

test("the display panel's script parses", () => {
    const script = panelScript();
    assert.doesNotThrow(() => new Script(script), "a template-string escape broke the script");
    assert.ok(script.includes(String.raw`join('\n')`), "the rows are joined by a newline escape, not a line break");
});

test("the screen has its own context menu, whose Paste types the clipboard, in place of VS Code's", () => {
    const html = webviewHtml("NONCE");
    const match = /<canvas id="screen"[^>]*data-vscode-context='([^']*)'/.exec(html);
    assert.ok(match, "the screen names its context");
    assert.deepEqual(JSON.parse(match[1]), { webviewSection: "screen", preventDefaultContextMenuItems: true });
});

type Listener = (event: Record<string, unknown>) => void;

interface FakeImage { width: number; height: number; data: Uint8ClampedArray }

/** A stand-in for the canvas's 2D context, recording the pictures put on it. */
class Context2d {
    readonly created: FakeImage[] = [];
    readonly put: Uint8ClampedArray[] = [];
    readonly strokes: { style: string; path: string[] }[] = [];
    private path: string[] = [];
    strokeStyle = "";
    createImageData(width: number, height: number): FakeImage {
        const image = { width, height, data: new Uint8ClampedArray(width * height * 4) };
        this.created.push(image);
        return image;
    }
    putImageData(image: FakeImage): void { this.put.push(image.data.slice()); }
    beginPath(): void { this.path = []; }
    moveTo(x: number, y: number): void { this.path.push(`M${x},${y}`); }
    lineTo(x: number, y: number): void { this.path.push(`L${x},${y}`); }
    stroke(): void { this.strokes.push({ style: this.strokeStyle, path: this.path }); }
}

/** A stand-in for the few DOM pieces the panel's script uses, recording what it posts to the extension. */
class Element {
    readonly listeners = new Map<string, Listener[]>();
    readonly attributes = new Map<string, string>();
    readonly style: Record<string, string> = {};
    hidden = false;
    textContent = "";
    value = "";
    readonly classes = new Set<string>();
    readonly classList = {
        toggle: (name: string, on: boolean): void => { if (on) this.classes.add(name); else this.classes.delete(name); },
        contains: (name: string): boolean => this.classes.has(name)
    };
    width = 0;
    height = 0;
    clientWidth = 0;
    clientHeight = 0;
    offsetHeight = 0;
    constructor(readonly dataset: Record<string, string> = {}) {}
    addEventListener(type: string, listener: Listener): void { this.listeners.set(type, [...this.listeners.get(type) ?? [], listener]); }
    setAttribute(name: string, value: string): void { this.attributes.set(name, value); }
    getAttribute(name: string): string | null { return this.attributes.get(name) ?? null; }
    focus(): void { /* nothing to focus */ }
    readonly context = new Context2d();
    getContext(): Context2d { return this.context; }
    dispatch(type: string, event: Record<string, unknown> = {}): void {
        for (const listener of this.listeners.get(type) ?? []) listener({ preventDefault: () => undefined, stopPropagation: () => undefined, ...event });
    }
}

interface PanelWindow extends Element { innerHeight: number; devicePixelRatio: number }

/** The panel's document, with the pointer lock the mouse card uses. */
interface PanelDocument { pointerLockElement: Element | undefined; events: Element }

function loadPanel(state?: unknown, audioContext?: unknown): {
    posted: unknown[]; screen: Element; byId: Map<string, Element>; buttons: Element[]; codes: Element[]; window: PanelWindow;
    body: Element; saved: () => unknown; sharpSize: (machine: string, width: number, height: number, ratio: number) => unknown;
    document: PanelDocument; frames: (() => void)[];
} {
    const posted: unknown[] = [];
    const ids = ["screen", "display", "text", "status", "disk", "details", "overlay", "ctrl", "reset", "trs80-reset", "hint", "sound", "volume", "bezel", "scale", "speed", "fastDisk", "off", "offName", "restart", "startMachine", "close", "basic", "screenType", "mouseState"];
    const byId = new Map(ids.map(id => [id, new Element()]));
    byId.get("ctrl")?.setAttribute("aria-pressed", "false");
    const buttons = [new Element({ button: "0" }), new Element({ button: "1" })];
    const codes = [new Element({ code: "3" }), new Element({ code: "27" })];
    const groups = [new Element({ machine: "apple2 apple3" }), new Element({ machine: "trs80-model1" })];
    // A panel 1240 pixels wide with 900 left for the screen, at 100% display scaling: room for the IIe at 2x.
    const window: PanelWindow = Object.assign(new Element(), { innerHeight: 1000, devicePixelRatio: 1, AudioContext: audioContext });
    const body = new Element();
    body.offsetHeight = 1100;
    (byId.get("bezel") as Element).clientWidth = 1220;
    (byId.get("display") as Element).offsetHeight = 1000;
    const events = new Element();
    const frames: (() => void)[] = [];
    const document = {
        body,
        events,
        pointerLockElement: undefined as Element | undefined,
        addEventListener: (type: string, listener: Listener) => events.addEventListener(type, listener),
        getElementById: (id: string) => byId.get(id),
        activeElement: undefined,
        querySelector: (selector: string) => buttons.find(button => selector === `[data-button="${button.dataset.button}"]`),
        querySelectorAll: (selector: string) =>
            selector === "[data-button]" ? buttons : selector === "[data-code]" ? codes : selector === "[data-machine]" ? groups : []
    };
    // Messages are copied out of the script's own realm, as postMessage does.
    const post = (message: unknown): number => posted.push(JSON.parse(JSON.stringify(message)));
    // The panel's state round-trips through JSON, as VS Code keeps it.
    let kept = state === undefined ? undefined : JSON.stringify(state);
    const getState = (): unknown => kept === undefined ? undefined : JSON.parse(kept);
    const setState = (value: unknown): void => { kept = JSON.stringify(value); };
    const screen = byId.get("screen") as Element & { requestPointerLock?: () => void };
    screen.requestPointerLock = () => {
        document.pointerLockElement = screen;
        events.dispatch("pointerlockchange");
    };
    const requestAnimationFrame = (callback: () => void): number => frames.push(callback);
    const context = createContext({ window, document, Buffer, Promise, requestAnimationFrame, acquireVsCodeApi: () => ({ postMessage: post, getState, setState }) });
    // Node lacks Uint8Array.prototype.setFromBase64, which VS Code's Chromium has; this one behaves the same.
    new Script(`Uint8Array.prototype.setFromBase64 ??= function (text) {
        const bytes = Buffer.from(text, "base64");
        if (bytes.length > this.length) throw new SyntaxError("too long");
        this.set(bytes);
        return { read: text.length, written: bytes.length };
    };`).runInContext(context);
    new Script(panelScript()).runInContext(context);
    const sharpSize = context.sharpSize as (machine: string, width: number, height: number, ratio: number) => unknown;
    return { posted, screen, byId, buttons, codes, window, body, saved: getState, sharpSize, document, frames };
}

test("with a mouse card, a click locks the pointer and the mouse moves the card's mouse", () => {
    const { posted, screen, window, document, frames, byId } = loadPanel();
    screen.clientWidth = 560;
    screen.clientHeight = 384;
    const frame = (mouse: number): Record<string, unknown> => ({
        machine: "apple2", rows: [""], cycles: 1, running: true, mouse,
        video: { width: 1, height: 1, pixelFormat: "rgba", pixels: Buffer.from([0, 0, 0, 255]).toString("base64") }
    });
    window.dispatch("message", { data: frame(0) });
    screen.dispatch("mousedown", { button: 0 });
    assert.equal(document.pointerLockElement, undefined, "without a mouse card a click only focuses the screen");
    const state = byId.get("mouseState") as Element;
    assert.equal(state.hidden, true, "no mouse card, no mouse strip");

    window.dispatch("message", { data: frame(4) });
    assert.equal(state.hidden, false);
    assert.match(state.textContent, /click the screen to capture/);
    posted.splice(0);
    screen.dispatch("mousedown", { button: 0 });
    assert.equal(document.pointerLockElement, screen, "the first click locks the pointer");
    assert.match(state.textContent, /captured .*press Esc to release/);
    assert.equal(state.classList.contains("captured"), true);
    assert.equal(byId.get("bezel")?.classList.contains("captured"), true, "the screen's border lights");
    assert.deepEqual(posted.splice(0), [], "and does not press the button");

    // 560 by 384 pixels show 280 by 192 dots: two pixels a dot, and movement goes once a frame.
    screen.dispatch("mousemove", { movementX: 5, movementY: -4 });
    screen.dispatch("mousemove", { movementX: 2, movementY: 0 });
    assert.deepEqual(posted.splice(0), []);
    frames.splice(0).forEach(callback => callback());
    assert.deepEqual(posted.splice(0), [{ mouse: { dx: 3, dy: -2 } }], "half a dot waits for the next movement");

    screen.dispatch("mousedown", { button: 0 });
    screen.dispatch("mouseup", { button: 0 });
    assert.deepEqual(posted.splice(0), [{ mouse: { pressed: true } }, { mouse: { pressed: false } }]);

    document.pointerLockElement = undefined;
    document.events.dispatch("pointerlockchange");
    assert.deepEqual(posted.splice(0), [{ mouse: { pressed: false } }], "letting go releases the button");
    assert.match(state.textContent, /click the screen to capture/, "the strip says how to capture it again");
    assert.equal(byId.get("bezel")?.classList.contains("captured"), false);
});

test("Screen follows the host's monitor, and the panel's choice is kept and sent to each new session", () => {
    const frame = (screen: string): Record<string, unknown> => ({
        machine: "apple2", rows: [""], cycles: 1, running: true, screen,
        video: { width: 1, height: 1, pixelFormat: "rgba", pixels: Buffer.from([0, 0, 0, 255]).toString("base64") }
    });
    const first = loadPanel();
    const select = first.byId.get("screenType") as Element;
    first.window.dispatch("message", { data: frame("amber") });
    assert.equal(select.value, "amber", "the launch's monitor shows");
    first.posted.splice(0);
    select.value = "green";
    select.dispatch("change");
    assert.deepEqual(first.posted.splice(0), [{ command: "screen", screen: "green" }]);
    assert.equal((first.saved() as { screen?: string }).screen, "green");

    // A later session starts in color: the panel sends its choice once, and the host's frames then agree.
    const later = loadPanel(first.saved());
    later.window.dispatch("message", { data: frame("color") });
    later.window.dispatch("message", { data: frame("color") });
    assert.deepEqual(later.posted.filter(message => (message as { command?: string }).command === "screen"), [{ command: "screen", screen: "green" }]);
    later.window.dispatch("message", { data: frame("green") });
    assert.equal((later.byId.get("screenType") as Element).value, "green");
});

test("the panel sends control characters, the Apple keys and CONTROL-RESET", () => {
    const { posted, screen, byId, buttons } = loadPanel();
    const key = (key: string, extra: Record<string, unknown> = {}): void =>
        screen.dispatch("keydown", { key, code: "", ctrlKey: false, altKey: false, ...extra });

    key("c", { ctrlKey: true });
    key("[", { ctrlKey: true });
    key("Cancel", { ctrlKey: true });
    key("a");
    screen.dispatch("keydown", { key: "Alt", code: "AltLeft" });
    screen.dispatch("keyup", { key: "Alt", code: "AltLeft" });
    screen.dispatch("keydown", { key: "Alt", code: "AltRight" });
    assert.deepEqual(posted.splice(0), [
        { code: 3 }, { code: 27 }, { command: "reset" }, { code: 97 },
        { button: 0, pressed: true }, { button: 0, pressed: false }, { button: 1, pressed: true }
    ]);

    // A clicked Apple key stays down until clicked again.
    buttons[0].dispatch("click");
    assert.equal(buttons[0].getAttribute("aria-pressed"), "true");
    posted.splice(0);
    byId.get("ctrl")?.dispatch("click");
    key("g");
    assert.deepEqual(posted.splice(0), [{ code: 7 }], "the Ctrl button makes the next letter CONTROL-G");
    byId.get("reset")?.dispatch("click");
    assert.deepEqual(posted.splice(0), [{ command: "reset" }]);
});

test("the Model I's Reset button, Ctrl+Break and Ctrl+F12 press its reset", () => {
    const { posted, screen, byId, window } = loadPanel();
    // A frame without pixels reports an error, but still switches the key bar to the Model I's keys.
    window.dispatch("message", { data: { machine: "trs80-model1" } });
    posted.splice(0);
    byId.get("trs80-reset")?.dispatch("click");
    screen.dispatch("keydown", { key: "Pause", code: "Pause", ctrlKey: true, altKey: false });
    screen.dispatch("keydown", { key: "F12", code: "F12", ctrlKey: true, altKey: false });
    screen.dispatch("keydown", { key: "F12", code: "F12", ctrlKey: false, altKey: false });
    assert.deepEqual(posted.splice(0), [{ command: "reset" }, { command: "reset" }, { command: "reset" }], "F12 alone does not reset");
});

test("a frame without pixels keeps the last picture, which is decoded into one kept image", () => {
    const { posted, screen, window } = loadPanel();
    const frame = (pixels?: Uint8Array): Record<string, unknown> => ({
        machine: "trs80-model1", rows: ["READY"], cycles: 1, running: true,
        video: { width: 2, height: 1, pixelFormat: "rgba", ...(pixels ? { pixels: Buffer.from(pixels).toString("base64") } : {}) }
    });
    window.dispatch("message", { data: frame() });
    assert.equal(screen.context.put.length, 0, "nothing to show before the first picture");
    window.dispatch("message", { data: frame(Uint8Array.of(1, 2, 3, 255, 4, 5, 6, 255)) });
    window.dispatch("message", { data: frame() });
    window.dispatch("message", { data: frame(Uint8Array.of(9, 9, 9, 255, 8, 8, 8, 255)) });
    assert.deepEqual(screen.context.put.map(data => [...data]), [
        [1, 2, 3, 255, 4, 5, 6, 255], [1, 2, 3, 255, 4, 5, 6, 255], [9, 9, 9, 255, 8, 8, 8, 255]
    ]);
    assert.equal(screen.context.created.length, 1, "the image is made once and kept");
    assert.deepEqual([screen.width, screen.height], [2, 1]);

    // A picture of the wrong size is reported, not drawn.
    window.dispatch("message", { data: frame(Uint8Array.of(1, 2, 3, 4)) });
    assert.deepEqual(posted.splice(0), [{ error: "Incorrect RGBA frame size from the debug host." }]);
    assert.equal(screen.context.put.length, 3);
});

test("the screen keeps the machine's keys from VS Code, and lets the debugger's and the Command Palette's through", () => {
    const { posted, screen } = loadPanel();
    const press = (key: string, extra: Record<string, unknown> = {}): boolean => {
        let stopped = false;
        screen.dispatch("keydown", { key, code: "", ctrlKey: false, shiftKey: false, altKey: false, metaKey: false,
            stopPropagation: () => { stopped = true; }, ...extra });
        return stopped;
    };
    assert.equal(press("p", { ctrlKey: true }), true, "Ctrl+P is CONTROL-P, not Quick Open");
    assert.equal(press("a"), true);
    assert.equal(press("Escape"), true);
    assert.equal(press("Alt", { code: "AltLeft", altKey: true }), true, "Alt is Open Apple, not the menu bar");
    assert.equal(press("F12", { ctrlKey: true }), true, "Ctrl+F12 is reset");
    assert.deepEqual(posted.splice(0), [{ code: 16 }, { code: 97 }, { code: 27 }, { button: 0, pressed: true }, { command: "reset" }]);

    assert.equal(press("F5"), false, "F5 continues the debugger");
    assert.equal(press("F10", { shiftKey: true }), false);
    assert.equal(press("F12"), false);
    assert.equal(press("P", { ctrlKey: true, shiftKey: true }), false, "Ctrl+Shift+P opens the Command Palette");
    assert.equal(press("p", { metaKey: true }), false, "Cmd shortcuts are VS Code's on a Mac");
    assert.deepEqual(posted, [], "keys left to VS Code reach the machine as nothing");

    let released = false;
    screen.dispatch("keyup", { key: "a", code: "KeyA", stopPropagation: () => { released = true; } });
    assert.equal(released, true, "a kept key's release is kept too");
});

test("stopped, the beam shows as a cross on the picture, and in blanking as a dimmer marker at its edge", () => {
    const { screen, window, byId } = loadPanel();
    byId.get("overlay")?.setAttribute("checked", "");
    (byId.get("overlay") as Element & { checked: boolean }).checked = true;
    const at = (scanline: number, column: number): { style: string; path: string[] } | undefined => {
        screen.context.strokes.length = 0;
        window.dispatch("message", { data: {
            machine: "apple2", rows: [""], cycles: 1, running: false,
            video: { width: 560, height: 192, pixelFormat: "rgba", pixels: Buffer.alloc(560 * 192 * 4).toString("base64"),
                beam: { scanline, column, cycleInFrame: 0, horizontalBlank: column < 25, verticalBlank: scanline >= 192 } }
        } });
        return screen.context.strokes[0];
    };
    assert.deepEqual(at(100, 45), { style: "#ff4040", path: ["M280,100", "L294,100", "M287,97", "L287,103"] });
    assert.deepEqual(at(0, 7), { style: "rgba(255,64,64,0.6)", path: ["M0.5,0", "L0.5,3.5", "M0.5,0.5", "L8,0.5"] },
        "horizontal blanking: the left edge of the line, as at the power-on stop");
    assert.deepEqual(at(200, 45), { style: "rgba(255,64,64,0.6)", path: ["M284,191.5", "L290,191.5", "M287,191.5", "L287,183.5"] },
        "vertical blanking: the bottom edge, under the column");
    assert.deepEqual(at(230, 3)?.path, ["M-2.5,191.5", "L3.5,191.5", "M0.5,191.5", "L0.5,183.5"], "both: the bottom-left corner");

    (byId.get("overlay") as Element & { checked: boolean }).checked = false;
    assert.equal(at(100, 45), undefined, "with Beam overlay off, nothing is drawn");
});

test("Beam overlay shows on the IIe running or stopped, starts off, and is kept with the panel's state", () => {
    const first = loadPanel();
    const overlay = first.byId.get("overlay") as Element & { checked: boolean };
    const details = first.byId.get("details") as Element;
    assert.equal(overlay.checked, false, "off by default");
    const frame = (machine: string, running: boolean): Record<string, unknown> => ({
        machine, rows: [""], cycles: 1, running,
        video: { width: 2, height: 1, pixelFormat: "rgba", pixels: "AAAAAAAAAAA=", beam: { scanline: 0, column: 30 } }
    });
    first.window.dispatch("message", { data: frame("apple2", true) });
    assert.equal(details.hidden, false, "shown while the IIe runs");
    first.window.dispatch("message", { data: frame("trs80-model1", false) });
    assert.equal(details.hidden, true, "the Model I has no beam");

    overlay.checked = true;
    overlay.dispatch("change");
    assert.deepEqual(first.saved(), { overlay: true });
    const again = loadPanel(first.saved());
    assert.equal((again.byId.get("overlay") as Element & { checked: boolean }).checked, true);
});

test("sharp scales are whole physical pixels per dot, in the screen's shape, as large as fit", () => {
    const { sharpSize } = loadPanel();
    const size = (machine: string, width: number, height: number, ratio: number): unknown =>
        JSON.parse(JSON.stringify(sharpSize(machine, width, height, ratio)));
    assert.deepEqual(size("apple2", 1200, 900, 1), { width: 1120, height: 768, scale: 2 });
    assert.deepEqual(size("apple2", 2000, 500, 1), { width: 560, height: 384, scale: 1 }, "the height limits it");
    assert.deepEqual(size("apple2", 1200, 900, 1.5), { width: 1120, height: 768, scale: 3 },
        "at 150% display scaling, 3x is 1680x1152 physical pixels");
    assert.deepEqual(size("trs80-model1", 1000, 900, 1), { width: 768, height: 576, scale: 1 }, "Model I dots are 2 by 3");
    assert.equal(size("trs80-model1", 700, 900, 1), null, "too small for 1x");
});

test("Scale starts sharp, sizes the screen, follows resizing, and keeps Fit with the panel's state", () => {
    const first = loadPanel();
    const display = first.byId.get("display") as Element;
    const scale = first.byId.get("scale") as Element;
    assert.deepEqual([display.style.width, display.style.height, scale.textContent], ["1120px", "768px", "Scale: sharp (2x)"]);

    (first.byId.get("bezel") as Element).clientWidth = 600;
    first.window.dispatch("resize");
    assert.deepEqual([display.style.width, scale.textContent], ["560px", "Scale: sharp (1x)"]);
    (first.byId.get("bezel") as Element).clientWidth = 400;
    first.window.dispatch("resize");
    assert.deepEqual([display.style.width, scale.textContent], ["", "Scale: sharp (too small, fits)"]);

    scale.dispatch("click");
    assert.deepEqual([display.style.width, display.style.height, scale.textContent], ["", "", "Scale: fit"]);
    assert.deepEqual(first.saved(), { scale: "fit" });
    assert.equal((loadPanel(first.saved()).byId.get("scale") as Element).textContent, "Scale: fit");
});

test("Speed asks the host for a speed, follows the host's setting, and the status line shows the measured speed", () => {
    const { posted, byId, window } = loadPanel();
    const speed = byId.get("speed") as Element & { value: string };
    speed.value = "4";
    speed.dispatch("change");
    speed.value = "max";
    speed.dispatch("change");
    assert.deepEqual(posted.splice(0), [{ command: "speed", speed: 4 }, { command: "speed", speed: "max" }]);

    const frame = (setting: number | string, actual: number | null, hertz: number | null): Record<string, unknown> => ({
        machine: "trs80-model1", rows: [""], cycles: 1, running: true, speed: { setting, actual, hertz },
        video: { width: 2, height: 1, pixelFormat: "rgba", pixels: "AAAAAAAAAAA=" }
    });
    window.dispatch("message", { data: frame(2, 1.998, 3544620) });
    assert.equal(speed.value, "2", "the host's setting shows");
    assert.equal(byId.get("status")?.textContent, "Running · 2.00× · 3.54 MHz");
    window.dispatch("message", { data: frame("max", 38.4, 68124672) });
    assert.equal(byId.get("status")?.textContent, "Running · Max · 38.40× · 68.12 MHz");
    window.dispatch("message", { data: frame(1, null, null) });
    assert.equal(byId.get("status")?.textContent, "Running", "nothing measured yet");
});

test("Fast disk follows the host, asks it to change, and the status line says when it runs flat out", () => {
    const { posted, byId, window } = loadPanel();
    const fast = byId.get("fastDisk") as Element & { checked: boolean };
    const frame = (fastDisk: boolean, accelerated: boolean, machine = "apple2"): Record<string, unknown> => ({
        machine, rows: [""], cycles: 1, running: true, fastDisk,
        speed: { setting: 1, accelerated, actual: accelerated ? 13.9 : 1, hertz: accelerated ? 14184728 : 1020484 },
        video: { width: 2, height: 1, pixelFormat: "rgba", pixels: "AAAAAAAAAAA=", beam: { scanline: 0, column: 30 } }
    });
    window.dispatch("message", { data: frame(false, false) });
    assert.equal(fast.checked, false, "the host's setting shows");
    assert.equal(byId.get("status")?.textContent, "Running · 1.00× · 1.02 MHz");
    window.dispatch("message", { data: frame(true, true) });
    assert.equal(byId.get("status")?.textContent, "Running · Fast disk · 13.90× · 14.18 MHz");
    window.dispatch("message", { data: frame(true, true, "trs80-model1") });
    assert.equal(byId.get("status")?.textContent, "Running · Fast tape · 13.90× · 14.18 MHz");

    posted.splice(0);
    fast.checked = false;
    fast.dispatch("change");
    assert.deepEqual(posted, [{ command: "fastDisk", enabled: false }]);
});

test("the volume starts at 50%, is kept with the panel's state and is restored", () => {
    const first = loadPanel();
    const volume = first.byId.get("volume") as Element & { value: string };
    assert.equal(volume.value, "50");
    volume.value = "25";
    volume.dispatch("input");
    assert.deepEqual(first.saved(), { volume: 0.25 });
    const again = loadPanel(first.saved());
    assert.equal((again.byId.get("volume") as Element & { value: string }).value, "25");
});

test("the Sound button cycles the modes, the Mockingboard's only while it is in, and audio without Web Audio is ignored", () => {
    const { posted, byId, window } = loadPanel();
    const sound = byId.get("sound") as Element;
    sound.dispatch("click");
    sound.dispatch("click");
    assert.deepEqual(posted.splice(0), [{ command: "sound", mode: "off" }, { command: "sound", mode: "speaker" }],
        "without the Mockingboard there is off and the speaker");
    assert.equal(sound.textContent, "Sound: speaker (click the screen to hear it)", "the speaker is the default");

    // A frame says the Mockingboard is in, and the button offers it.
    const frame = (mockingboard: boolean, mode: string): Record<string, unknown> => ({
        machine: "apple2", rows: [""], cycles: 1, running: false, sound: mode, mockingboard,
        video: { width: 2, height: 1, pixelFormat: "rgba", pixels: "AAAAAAAAAAA=", beam: { scanline: 0, column: 30 } }
    });
    window.dispatch("message", { data: frame(true, "speaker") });
    sound.dispatch("click");
    sound.dispatch("click");
    sound.dispatch("click");
    assert.deepEqual(posted.splice(0), [
        { command: "sound", mode: "mockingboard" }, { command: "sound", mode: "off" }, { command: "sound", mode: "speaker" }
    ]);

    // Taking the card out leaves the speaker, as the host says.
    window.dispatch("message", { data: frame(false, "speaker") });
    sound.dispatch("click");
    assert.deepEqual(posted.splice(0), [{ command: "sound", mode: "off" }]);

    // A frame carries the host's mode; a chunk of audio with no Web Audio to play it changes nothing.
    window.dispatch("message", { data: { audio: { rate: 48000, channels: 1, samples: "AAA=" } } });
    assert.deepEqual(posted, []);
});

test("Ctrl+V is CONTROL-V, Shift+Insert pastes, and pasted text goes to the machine to type", () => {
    const { posted, screen } = loadPanel();
    const press = (key: string, extra: Record<string, unknown> = {}): boolean => {
        let stopped = false;
        screen.dispatch("keydown", { key, code: "", ctrlKey: false, shiftKey: false, altKey: false, metaKey: false,
            stopPropagation: () => { stopped = true; }, ...extra });
        return stopped;
    };
    assert.equal(press("v", { ctrlKey: true }), true, "Ctrl+V stays with the screen");
    assert.equal(press("Insert", { shiftKey: true }), true);
    assert.deepEqual(posted.splice(0), [{ code: 22 }, { command: "paste" }],
        "Ctrl+V types CONTROL-V; for Shift+Insert the extension reads the clipboard");

    let prevented = false;
    const paste = (text: string): void => screen.dispatch("paste", {
        clipboardData: { getData: (type: string) => type === "text/plain" ? text : "" },
        preventDefault: () => { prevented = true; }
    });
    paste("10 PRINT “HI”\r\nRUN\r\n");
    paste("");
    assert.equal(prevented, true);
    assert.deepEqual(posted, [{ command: "paste", text: "10 PRINT “HI”\r\nRUN\r\n" }], "the host makes keys of it; nothing is pasted for no text");
});

test("the Apple III has the Apple keys, Solid Apple among them, and sound without a Mockingboard", () => {
    const { posted, screen, byId, buttons, window } = loadPanel();
    const frame = (machine: string, extra: Record<string, unknown> = {}): Record<string, unknown> => ({
        machine, rows: [""], cycles: 1, running: false, sound: "speaker", ...extra,
        video: { width: 2, height: 1, pixelFormat: "rgba", pixels: "AAAAAAAAAAA=", beam: { scanline: 0, column: 30 } }
    });
    // After an Apple II with the Mockingboard in, the Apple III's frame, which names none, takes it away.
    window.dispatch("message", { data: frame("apple2", { mockingboard: true }) });
    window.dispatch("message", { data: frame("apple3") });
    assert.deepEqual(buttons.map(button => button.textContent), ["Open Apple", "Solid Apple"]);
    assert.match((byId.get("hint") as Element).textContent, /Open\/Solid Apple/);
    assert.doesNotMatch((byId.get("sound") as Element & { title: string }).title, /Mockingboard/);

    const sound = byId.get("sound") as Element;
    sound.dispatch("click");
    sound.dispatch("click");
    screen.dispatch("keydown", { key: "Alt", code: "AltRight", ctrlKey: false, altKey: true });
    buttons[0].dispatch("click");
    assert.deepEqual(posted.splice(0), [
        { command: "sound", mode: "off" }, { command: "sound", mode: "speaker" },
        { button: 1, pressed: true }, { button: 0, pressed: true }
    ]);
});

// Web Audio as Chromium runs it: a context runs only once the page has had a click or key. Made before then
// it starts suspended, and resuming it waits for one.
function fakeAudio(): { made: () => number; activate: () => void; Context: unknown } {
    let made = 0;
    let activated = false;
    const waiting: (() => void)[] = [];
    class Context {
        state = activated ? "running" : "suspended";
        onstatechange: (() => void) | undefined;
        currentTime = 0;
        destination = {};
        constructor() { made++; }
        createGain(): unknown { return { gain: { value: 1 }, connect: () => undefined }; }
        resume(): Promise<void> {
            const run = (): void => {
                this.state = "running";
                this.onstatechange?.();
            };

            if (activated) { run(); } else { waiting.push(run); }
            return Promise.resolve();
        }
    }

    return {
        made: () => made,
        activate: () => {
            activated = true;
            waiting.splice(0).forEach(run => run());
        },
        Context
    };
}

test("the sound hint clears when a click starts the audio, paused or running", () => {
    // Paused: no audio has come, so the click makes the context, which starts out running.
    const paused = fakeAudio();
    const first = loadPanel(undefined, paused.Context);
    const firstSound = first.byId.get("sound") as Element;
    paused.activate();
    first.screen.dispatch("pointerdown");
    assert.equal(paused.made(), 1);
    assert.equal(firstSound.textContent, "Sound: speaker", "the context made by the click runs");

    // Running: audio came first and made a suspended context, which the click resumes.
    const running = fakeAudio();
    const second = loadPanel(undefined, running.Context);
    const secondSound = second.byId.get("sound") as Element;
    second.window.dispatch("message", { data: { audio: { rate: 48000, channels: 1, samples: "AAA=" } } });
    assert.equal(running.made(), 1);
    assert.equal(secondSound.textContent, "Sound: speaker (click the screen to hear it)", "nothing has been clicked");
    running.activate();
    second.screen.dispatch("pointerdown");
    assert.equal(secondSound.textContent, "Sound: speaker", "the resumed context runs");
});

test("the key bar names the II and II Plus's game-port buttons and the IIe's Apple keys", () => {
    const { byId, buttons, window } = loadPanel();
    const frame = (model: string): Record<string, unknown> => ({
        machine: "apple2", model, rows: [""], cycles: 1, running: false,
        video: { width: 2, height: 1, pixelFormat: "rgba", pixels: "AAAAAAAAAAA=", beam: { scanline: 0, column: 30 } }
    });
    window.dispatch("message", { data: frame("Apple II Plus") });
    assert.deepEqual(buttons.map(button => button.textContent), ["Button 0", "Button 1"]);
    assert.match(byId.get("hint")?.textContent ?? "", /game-port buttons 0 and 1/);
    window.dispatch("message", { data: frame("Enhanced Apple IIe") });
    assert.deepEqual(buttons.map(button => button.textContent), ["Open Apple", "Closed Apple"]);
    assert.match(byId.get("hint")?.textContent ?? "", /Open\/Closed Apple/);
});

test("the BASIC button shows while the machine's BASIC can be edited, and asks to open the program", () => {
    const { byId, window, posted } = loadPanel();
    const basic = byId.get("basic") as Element;
    basic.hidden = true;
    window.dispatch("message", { data: { basic: true } });
    assert.equal(basic.hidden, false);
    basic.dispatch("click");
    assert.deepEqual(posted.at(-1), { command: "basic" });
    window.dispatch("message", { data: { basic: false } });
    assert.equal(basic.hidden, true);
});

test("when the session ends the panel says the machine is off and offers Restart, Start Machine and Close", () => {
    const { byId, window, posted } = loadPanel();
    const off = byId.get("off") as Element;
    off.hidden = true;
    const frame = {
        machine: "apple2", model: "Apple II Plus", rows: [""], cycles: 1, running: true,
        video: { width: 2, height: 1, pixelFormat: "rgba", pixels: "AAAAAAAAAAA=", beam: { scanline: 0, column: 30 } }
    };
    window.dispatch("message", { data: frame });
    window.dispatch("message", { data: { basic: true } });
    window.dispatch("message", { data: { ended: { name: "Apple II Plus (Retrocore)" } } });
    assert.equal(off.hidden, false);
    assert.equal(byId.get("offName")?.textContent, "Apple II Plus (Retrocore)");
    assert.equal(byId.get("basic")?.hidden, true, "an ended machine has no program to open");
    assert.equal(byId.get("status")?.textContent, "Stopped");
    for (const id of ["restart", "startMachine", "close"]) {
        byId.get(id)?.dispatch("click");
        assert.deepEqual(posted.at(-1), { command: id });
    }

    // The next session's first frame brings the machine back.
    window.dispatch("message", { data: frame });
    assert.equal(off.hidden, true);
});
