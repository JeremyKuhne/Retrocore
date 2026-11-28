// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

import * as assert from "node:assert/strict";
import { test } from "node:test";
import { Script, createContext } from "node:vm";
import { panelKeyCode, webviewHtml } from "../display";

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
    children: unknown[] = [];
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
    replaceChildren(...children: unknown[]): void { this.children = children; }
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
    const ids = ["screen", "display", "text", "status", "disk", "details", "overlay", "ctrl", "reset", "trs80-reset", "model3-reset", "model2-reset", "model100-reset", "kaypro-reset", "apple1-reset", "apple1-clear", "coco-reset", "pet-reset", "vic20-reset", "altair-reset", "altair-clear", "bbc-reset", "hint", "sound", "volume", "bezel", "scale", "speed", "tapeSpeed", "diskSpeed", "tapeSpeedChoice", "diskSpeedChoice", "mediaSpeedHelp", "off", "offName", "restart", "startMachine", "close", "basic", "screenType", "screenChoice", "mouseState"];
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
        exitPointerLock: (): void => {
            document.pointerLockElement = undefined;
            events.dispatch("pointerlockchange");
        },
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
    // A select's option, as the Screen menu builds them.
    const Option = class { constructor(readonly text: string, readonly value: string) {} };
    const context = createContext({ window, document, Buffer, Promise, requestAnimationFrame, Option, acquireVsCodeApi: () => ({ postMessage: post, getState, setState }) });
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

test("taking the mouse card out, or the session ending, gives the pointer back", () => {
    const { screen, window, document, byId } = loadPanel();
    screen.clientWidth = 560;
    screen.clientHeight = 384;
    const frame = (mouse: number): Record<string, unknown> => ({
        machine: "apple2", rows: [""], cycles: 1, running: true, mouse,
        video: { width: 1, height: 1, pixelFormat: "rgba", pixels: Buffer.from([0, 0, 0, 255]).toString("base64") }
    });
    const state = byId.get("mouseState") as Element;
    window.dispatch("message", { data: frame(4) });
    screen.dispatch("mousedown", { button: 0 });
    assert.equal(document.pointerLockElement, screen);

    window.dispatch("message", { data: frame(0) });
    assert.equal(document.pointerLockElement, undefined, "the card was taken out");
    assert.equal(state.hidden, true);
    assert.equal(byId.get("bezel")?.classList.contains("captured"), false);

    window.dispatch("message", { data: frame(4) });
    screen.dispatch("mousedown", { button: 0 });
    assert.equal(document.pointerLockElement, screen);
    window.dispatch("message", { data: { ended: { name: "IIe" } } });
    assert.equal(document.pointerLockElement, undefined, "the session ended");
    assert.equal(state.hidden, true);
    screen.dispatch("mousedown", { button: 0 });
    assert.equal(document.pointerLockElement, undefined, "an ended machine's last frame does not capture the mouse");
});

test("Screen follows the host's monitor, and the panel's choice is kept and sent to each new session", () => {
    const frame = (screen: string): Record<string, unknown> => ({
        machine: "apple2", rows: [""], cycles: 1, running: true, screen, screens: ["color", "white", "green", "amber"],
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

test("Screen offers each machine's own monitors, and keeps a choice another machine lacks", () => {
    const frame = (machine: string, screen: string | undefined, screens: string[] | undefined): Record<string, unknown> => ({
        machine, rows: [""], cycles: 1, running: true, screen, screens,
        video: { width: 1, height: 1, pixelFormat: "rgba", pixels: Buffer.from([0, 0, 0, 255]).toString("base64") }
    });
    const screenCommands = (posted: unknown[]): unknown[] => posted.filter(message => (message as { command?: string }).command === "screen");
    const panel = loadPanel({ screen: "color" });
    const choice = panel.byId.get("screenChoice") as Element;
    const select = panel.byId.get("screenType") as Element;
    // The Apple-1's media is a cassette alone, with no disks.
    const apple1 = { ...frame("apple1", "green", ["green", "white", "amber"]), media: { cassette: { path: "basic.wav", recording: false, motor: true } } };
    panel.window.dispatch("message", { data: apple1 });
    assert.deepEqual(panel.posted.filter(message => "error" in (message as object)), [], "the frame draws without an error");
    assert.match((panel.byId.get("status") as Element).textContent, /Tape playing/);
    assert.equal(choice.hidden, false, "every machine has the menu");
    assert.deepEqual(select.children.map(option => (option as { value: string }).value), ["green", "white", "amber"], "a monochrome machine offers no color");
    assert.equal(select.value, "green", "a monochrome machine starts green");
    assert.deepEqual(screenCommands(panel.posted), [], "color is not asked of a machine without it");
    assert.equal((panel.saved() as { screen?: string }).screen, "color", "the choice is kept for the next machine that has it");

    select.value = "amber";
    select.dispatch("change");
    assert.deepEqual(screenCommands(panel.posted.splice(0)), [{ command: "screen", screen: "amber" }]);

    // A host too old to say leaves the menu out.
    panel.window.dispatch("message", { data: frame("trs80-model1", undefined, undefined) });
    assert.equal(choice.hidden, true);
});

test("Screen names a IIe's RGB monitor Color RGB, after Color", () => {
    const panel = loadPanel();
    const select = panel.byId.get("screenType") as Element;
    panel.window.dispatch("message", { data: {
        machine: "apple2", model: "Enhanced Apple IIe", rows: [""], cycles: 1, running: true, screen: "rgb",
        screens: ["color", "rgb", "white", "green", "amber"],
        video: { width: 1, height: 1, pixelFormat: "rgba", pixels: Buffer.from([0, 0, 0, 255]).toString("base64") }
    } });
    const options = select.children as unknown as { text: string; value: string }[];
    assert.deepEqual(options.map(option => option.text), ["Color", "Color RGB", "Black and white", "Green", "Amber"]);
    assert.equal(select.value, "rgb");
});

test("the panel sends control characters, the Apple keys and CONTROL-RESET", () => {
    const { posted, screen, byId, buttons } = loadPanel();
    const key = (key: string, extra: Record<string, unknown> = {}): void =>
        screen.dispatch("keydown", { key, code: "", ctrlKey: false, altKey: false, ...extra });

    key("c", { ctrlKey: true });
    key("[", { ctrlKey: true });
    key("Cancel", { ctrlKey: true });
    key("ñ");                   // not ASCII, and no machine's key: nothing is sent
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

test("the PET types PETSCII: STOP, HOME, the cursor keys, DEL and INST, and its key bar has Stop, Clr and Reset", () => {
    const { posted, screen, byId, window } = loadPanel();
    window.dispatch("message", { data: {
        machine: "pet", model: "pet2001-basic2", rows: [""], cycles: 1, running: true,
        speed: { setting: 1, accelerated: true, actual: 20, hertz: 20000000 },
        media: {
            cassette1: { path: "game.tap", mode: "playing", recording: false, motor: true }, cassette2: { path: null },
            disks: [
                { device: "disk8-0", path: "demo.d64", mounted: true, writeProtected: false, track: 18, motor: true },
                { device: "disk8-1", path: null, mounted: false, writeProtected: false, track: 1, motor: false }
            ]
        },
        video: { width: 1, height: 1, pixelFormat: "rgba", pixels: Buffer.from([0, 0, 0, 255]).toString("base64") }
    } });
    assert.deepEqual(posted.filter(message => "error" in (message as object)), [], "the frame draws without an error");
    assert.equal(byId.get("status")?.textContent, "Running · Fast tape · 20.00× · 20.00 MHz · Tape 1 playing · motor on");
    assert.equal(byId.get("disk")?.textContent, "Unit 8 drive 0 track 18 · motor on", "a 4040's drive by its unit and track");
    assert.equal(byId.get("display")?.style.aspectRatio, "320/200", "the PET's dots are square");
    assert.match(byId.get("hint")?.textContent ?? "", /^Esc: STOP · Home: HOME · arrows: the cursor keys · Backspace: DEL · Insert: INST · Tab: TAB \(business keyboard\) · Ctrl\+F12: reset/);
    posted.splice(0);
    for (const key of ["Escape", "Home", "ArrowLeft", "ArrowRight", "ArrowUp", "ArrowDown", "Backspace", "Delete", "Insert", "Enter", "a"]) {
        screen.dispatch("keydown", { key, code: "", ctrlKey: false, altKey: false, shiftKey: false });
    }
    assert.deepEqual(posted.splice(0).map(message => (message as { code: number }).code), [3, 19, 157, 29, 145, 17, 20, 20, 148, 13, 97]);
    byId.get("pet-reset")?.dispatch("click");
    assert.deepEqual(posted.splice(0), [{ command: "reset" }], "the reset switch");
});

test("the VIC-20 types PETSCII, shows its Datasette stopped and its drive by device, and its RESTORE codes pass to the host", () => {
    const { posted, screen, byId, window } = loadPanel();
    window.dispatch("message", { data: {
        machine: "vic20", standard: "pal", rows: [""], cycles: 1, running: true,
        speed: { setting: 1, accelerated: false, actual: 1, hertz: 1108404 },
        media: {
            cassette: { path: "game.tap", mode: "stopped", recording: false, motor: false },
            disks: [{ device: "disk8", path: "demo.d64", mounted: true, writeProtected: false, track: 18, motor: true }]
        },
        video: { width: 1, height: 1, pixelFormat: "rgba", pixels: Buffer.from([0, 0, 0, 255]).toString("base64") }
    } });
    assert.deepEqual(posted.filter(message => "error" in (message as object)), [], "the frame draws without an error");
    assert.equal(byId.get("status")?.textContent, "Running · 1.00× · 1.11 MHz · Tape stopped");
    assert.equal(byId.get("disk")?.textContent, "Device 8 track 18 · motor on", "a 1541 by its device and track");
    assert.equal(byId.get("display")?.style.aspectRatio, "4/3");
    assert.match(byId.get("hint")?.textContent ?? "", /^Esc: RUN\/STOP · Home: HOME/);
    posted.splice(0);
    for (const key of ["Escape", "Home", "ArrowLeft", "ArrowRight", "ArrowUp", "ArrowDown", "Backspace", "Insert", "Enter", "a"]) {
        screen.dispatch("keydown", { key, code: "", ctrlKey: false, altKey: false, shiftKey: false });
    }
    assert.deepEqual(posted.splice(0).map(message => (message as { code: number }).code), [3, 19, 157, 29, 145, 17, 20, 148, 13, 97]);
    // The key bar's buttons post their data-code, which the key bar's test reads; those above 255 pass the panel's check.
    const html = webviewHtml("NONCE");
    const bar = /<span class="keys" data-machine="vic20">([\s\S]*?)<\/span>/.exec(html)?.[1] ?? "";
    for (const code of [256, 257, 258]) {
        assert.match(bar, new RegExp(`data-code="${code}"`));
        assert.equal(panelKeyCode({ code }), code, "the key bar's RESTORE keys pass to the host");
    }
    byId.get("vic20-reset")?.dispatch("click");
    assert.deepEqual(posted.splice(0), [{ command: "reset" }], "the reset switch");
});

test("the page focuses its screen as it loads only when asked, so a stopped machine's panel leaves the focus", () => {
    const tail = (html: string) => html.slice(html.lastIndexOf("showKeys();"));
    assert.match(tail(webviewHtml("NONCE")), /^screen\.focus\(\);$/m, "a running machine's page takes the keyboard");
    assert.match(tail(webviewHtml("NONCE", false)), /window\.addEventListener\('focus'/, "a focused panel gives its screen the keyboard");
    assert.doesNotMatch(tail(webviewHtml("NONCE", false)), /^screen\.focus\(\);$/m, "a stopped machine's page leaves the focus");
});

test("the PET's key bar has Stop and Clr, the shifted HOME", () => {
    const html = webviewHtml("NONCE");
    const bar = /<span class="keys" data-machine="pet">([\s\S]*?)<\/span>/.exec(html)?.[1] ?? "";
    assert.match(bar, /data-code="3"[^>]*>Stop</);
    assert.match(bar, /data-code="147"[^>]*>Clr</);
    assert.match(bar, /id="pet-reset"[^>]*>Reset</);
    assert.match(html, /data-machine="apple2 apple3 coco pet vic20 bbc atari800"/, "the PET, the VIC-20 and the BBC Micro have the Sound button");
});

test("the VIC-20's key bar has RUN/STOP, RESTORE alone and with RUN/STOP, CLR, HOME, the Commodore key and f1-f8", () => {
    const html = webviewHtml("NONCE");
    const bar = /<span class="keys" data-machine="vic20">([\s\S]*?)<\/span>/.exec(html)?.[1] ?? "";
    assert.match(bar, /data-code="3"[^>]*>Run\/Stop</);
    assert.match(bar, /data-code="256"[^>]*>Restore</);
    assert.match(bar, /data-code="257"[^>]*>Stop\+Restore</);
    assert.match(bar, /data-code="147"[^>]*>Clr</);
    assert.match(bar, /data-code="19"[^>]*>Home</);
    assert.match(bar, /data-code="258"[^>]*>C= Shift</);
    const keys = [...bar.matchAll(/data-code="(\d+)"[^>]*>f(\d)</g)].map(match => [Number(match[2]), Number(match[1])]);
    assert.deepEqual(keys.sort((a, b) => a[0] - b[0]).map(key => key[1]), [133, 137, 134, 138, 135, 139, 136, 140], "f1-f8 in PETSCII");
    assert.match(bar, /id="vic20-reset"[^>]*>Reset</);
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
        [1, 2, 3, 255, 4, 5, 6, 255], [9, 9, 9, 255, 8, 8, 8, 255]
    ]);
    assert.equal(screen.context.created.length, 1, "the image is made once and kept");
    assert.deepEqual([screen.width, screen.height], [2, 1]);

    // A picture of the wrong size is reported, not drawn.
    window.dispatch("message", { data: frame(Uint8Array.of(1, 2, 3, 4)) });
    assert.deepEqual(posted.splice(0), [{ error: "Incorrect RGBA frame size from the debug host." }]);
    assert.equal(screen.context.put.length, 2);
});

test("resuming without new pixels clears the stopped beam overlay once", () => {
    const { screen, window, byId } = loadPanel();
    (byId.get("overlay") as Element & { checked: boolean }).checked = true;
    const video = { width: 2, height: 1, pixelFormat: "rgba", pixels: "AAAAAAAAAAA=", beam: { scanline: 0, column: 30 } };
    window.dispatch("message", { data: { machine: "apple2", rows: [""], running: false, video } });
    const withoutPixels = { width: 2, height: 1, pixelFormat: "rgba", beam: video.beam };
    window.dispatch("message", { data: { machine: "apple2", rows: [""], running: true, video: withoutPixels } });
    window.dispatch("message", { data: { machine: "apple2", rows: [""], running: true, video: withoutPixels } });
    assert.equal(screen.context.put.length, 2);
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
    const { sharpSize, window } = loadPanel();
    const size = (machine: string, width: number, height: number, ratio: number): unknown =>
        JSON.parse(JSON.stringify(sharpSize(machine, width, height, ratio)));
    assert.deepEqual(size("apple2", 1200, 900, 1), { width: 1120, height: 768, scale: 2 });
    assert.deepEqual(size("apple2", 2000, 500, 1), { width: 560, height: 384, scale: 1 }, "the height limits it");
    assert.deepEqual(size("apple2", 1200, 900, 1.5), { width: 1120, height: 768, scale: 3 },
        "at 150% display scaling, 3x is 1680x1152 physical pixels");
    assert.deepEqual(size("trs80-model1", 1000, 900, 1), { width: 768, height: 576, scale: 1 }, "Model I dots are 2 by 3");
    assert.deepEqual(size("pet", 1300, 900, 1), { width: 1280, height: 800, scale: 2 }, "the PET's 320x200 square dots, doubled at 1x");
    assert.deepEqual(size("vic20", 1300, 1000, 1), { width: 1200, height: 992, scale: 2 }, "the VIC-20's dots three wide by two tall");
    // A PAL VIC-20's frame says so, and its 224x296 frame sizes larger.
    window.dispatch("message", { data: {
        machine: "vic20", standard: "pal", rows: [""], cycles: 1, running: false,
        video: { width: 1, height: 1, pixelFormat: "rgba", pixels: Buffer.from([0, 0, 0, 255]).toString("base64") }
    } });
    assert.deepEqual(size("vic20", 1400, 1200, 1), { width: 1344, height: 1184, scale: 2 }, "PAL's 224x296 frame");
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

test("Tape and disk speeds follow the host and report Skip fallback without losing the selection", () => {
    const { posted, byId, window } = loadPanel();
    const disk = byId.get("diskSpeed") as Element & { value: string };
    const frame = (mediaSpeed: Record<string, unknown>, accelerated: boolean, machine = "apple2"): Record<string, unknown> => ({
        machine, rows: [""], cycles: 1, running: true, mediaSpeed,
        speed: { setting: 1, accelerated, actual: accelerated ? 13.9 : 1, hertz: accelerated ? 14184728 : 1020484 },
        video: { width: 2, height: 1, pixelFormat: "rgba", pixels: "AAAAAAAAAAA=", beam: { scanline: 0, column: 30 } }
    });
    window.dispatch("message", { data: frame({ tape: null, disk: "normal" }, false) });
    assert.equal(disk.value, "normal", "the host's setting shows");
    assert.equal(byId.get("tapeSpeedChoice")?.hidden, true);
    assert.equal(byId.get("status")?.textContent, "Running · 1.00× · 1.02 MHz");
    window.dispatch("message", { data: frame({ tape: "fast", disk: "skip", diskFallback: true }, true) });
    assert.equal(byId.get("tapeSpeedChoice")?.hidden, false);
    assert.equal(disk.value, "skip");
    assert.match(byId.get("status")?.textContent ?? "", /Disk: Fast \(Skip not supported\)/);

    window.dispatch("message", { data: {
        ...frame({ tape: null, disk: "skip", boot: { kind: "disk", requested: "skip", effective: "fast" } }, false),
        running: false
    } });
    assert.match(byId.get("status")?.textContent ?? "", /Disk: Fast \(Skip not supported\)/);

    posted.splice(0);
    disk.value = "fast";
    disk.dispatch("change");
    assert.deepEqual(posted, [{ command: "mediaSpeed", kind: "disk", mode: "fast" }]);
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

test("the BBC Micro types £ and SHIFT LOCK, and Shift with BREAK is SHIFT-BREAK", () => {
    const { posted, screen, byId, window } = loadPanel();
    window.dispatch("message", { data: {
        machine: "bbc", rows: [""], cycles: 1, running: true,
        video: { width: 1, height: 1, pixelFormat: "rgba", pixels: Buffer.from([0, 0, 0, 255]).toString("base64") }
    } });
    posted.splice(0);
    for (const key of ["£", "ScrollLock", "End", "`"]) {
        screen.dispatch("keydown", { key, code: "", ctrlKey: false, altKey: false, shiftKey: false });
    }
    assert.deepEqual(posted.splice(0).map(message => (message as { code: number }).code), [96, 140, 135, 96], "£ is &60, as ` is");
    screen.dispatch("keydown", { key: "F12", code: "", ctrlKey: true, altKey: false, shiftKey: true, preventDefault: () => {} });
    byId.get("bbc-reset")?.dispatch("click", { shiftKey: true });
    byId.get("bbc-reset")?.dispatch("click", { shiftKey: false });
    assert.deepEqual(posted.splice(0), [{ command: "reset", shift: true }, { command: "reset", shift: true }, { command: "reset" }]);
});

test("the Atari's keys are ATASCII, its BREAK and console keys are above 127, and Ctrl+F12 turns it off and on", () => {
    const { posted, screen, byId, window, sharpSize } = loadPanel();
    window.dispatch("message", { data: {
        machine: "atari800", model: "Atari 800", rows: [""], cycles: 1, running: false, sound: "speaker",
        media: { disks: [{ drive: 0, mounted: true, cylinder: 3, selected: true }] },
        video: { width: 2, height: 1, pixelFormat: "rgba", pixels: "AAAAAAAAAAA=" }
    } });
    posted.splice(0);
    for (const key of ["Enter", "Escape", "Backspace", "Tab", "Home", "ArrowUp", "ArrowDown", "ArrowLeft", "ArrowRight", "Pause", "a"]) {
        screen.dispatch("keydown", { key, code: "", ctrlKey: false, altKey: false });
    }
    screen.dispatch("keydown", { key: "F12", code: "F12", ctrlKey: true, altKey: false });
    assert.deepEqual(posted.splice(0), [
        { code: 13 }, { code: 27 }, { code: 126 }, { code: 127 }, { code: 125 }, { code: 28 }, { code: 29 }, { code: 30 },
        { code: 31 }, { code: 243 }, { code: 97 }, { command: "reset" }
    ]);
    assert.match((byId.get("hint") as Element).textContent, /START, SELECT, OPTION and SYSTEM RESET/);
    assert.equal((byId.get("disk") as Element).textContent, "D1: cylinder 3 · selected", "the Atari's drives are D1: to D4:");
    assert.deepEqual(JSON.parse(JSON.stringify(sharpSize("atari800", 1600, 1000, 1))), { width: 1504, height: 960, scale: 2 },
        "376 dots by 240 lines, each two by two at 1x");

    const html = webviewHtml("NONCE");
    const bar = html.slice(html.indexOf('<span class="keys" data-machine="atari800">'));
    for (const [code, name] of [[240, "Start"], [241, "Select"], [242, "Option"], [243, "Break"], [244, "System Reset"]] as const) {
        assert.match(bar.slice(0, bar.indexOf("</span>")), new RegExp(`data-code="${code}"[^>]*>${name}<`), name);
    }
    assert.match(html, /data-machine="apple2 apple3 coco pet vic20 bbc atari800"/, "the Atari has the Sound button");
});

test("the panel's keys reach the machine up to code 258, for the BBC Micro's and Atari's keys and the VIC-20's RESTORE", () => {
    for (const code of [0, 13, 127, 0x8B, 0x8F, 0x80, 0x89, 240, 244, 255, 256, 257, 258]) {
        assert.equal(panelKeyCode({ code }), code);
    }

    for (const input of [{ code: 259 }, { code: -1 }, { code: 1.5 }, { code: "A" }, { button: 0 }, null, 13]) {
        assert.equal(panelKeyCode(input), undefined);
    }
});
