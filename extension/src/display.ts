// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

// The machine's display panel. Its script is a template string: a backslash escape meant for the script must be
// written doubled, or it becomes the character itself; display.test.ts checks that the script parses.

/**
 * The key code in a message from the display panel, or undefined for another message: a whole number from 0 to 258,
 * since the BBC Micro's COPY, cursor and function keys and the Atari's START, SELECT, OPTION, BREAK and SYSTEM RESET
 * have codes above 127, and the VIC-20's RESTORE, RUN/STOP with RESTORE, and SHIFT with the Commodore key are 256-258.
 * The debug host refuses a code above its machine's own largest.
 */
export function panelKeyCode(input: unknown): number | undefined {
    return typeof input === "object" && input !== null && "code" in input && typeof input.code === "number"
        && Number.isInteger(input.code) && input.code >= 0 && input.code <= 258 ? input.code : undefined;
}

/**
 * The display panel's page, with its script allowed by the nonce. With focusOnLoad, the page gives its screen the
 * keyboard as it loads, which in a webview also takes VS Code's focus; without it, the panel opens behind whatever has
 * the focus, as a stopped machine's must. Either way the screen takes the keyboard when it is clicked, and when the
 * panel gains VS Code's focus, as a click on its tab gives it, unless a control in the page has it.
 */
export function webviewHtml(nonce: string, focusOnLoad = true): string {
    return `<!doctype html><html><head>
<meta charset="utf-8">
<meta http-equiv="Content-Security-Policy" content="default-src 'none'; style-src 'unsafe-inline'; script-src 'nonce-${nonce}'">
<style>
[hidden]{display:none!important}
body{margin:0;padding:12px;background:var(--vscode-editor-background);color:var(--vscode-foreground);font-family:var(--vscode-font-family);font-size:var(--vscode-font-size)}
.bezel{position:relative;background:#0a0d0a;border:1px solid var(--vscode-contrastBorder,var(--vscode-panel-border,#3c3c3c));border-radius:6px;padding:10px}
.bezel:focus-within{border-color:var(--vscode-focusBorder)}
.display{aspect-ratio:280/192;width:100%;margin:0 auto}canvas{display:block;image-rendering:pixelated;width:100%;height:100%;outline:none}pre{display:none}
.keys{display:flex;flex-wrap:wrap;gap:4px;align-items:center}
#keybar{margin-top:10px;padding-top:8px;border-top:1px solid var(--vscode-panel-border)}
.end{margin-left:auto}
button{font-family:inherit;font-size:12px;line-height:18px;padding:2px 8px;border-radius:2px;cursor:pointer;border:1px solid var(--vscode-button-border,transparent);background:var(--vscode-button-secondaryBackground);color:var(--vscode-button-secondaryForeground)}
button:hover{background:var(--vscode-button-secondaryHoverBackground)}
button:focus-visible{outline:1px solid var(--vscode-focusBorder);outline-offset:1px}
button[aria-pressed=true]{background:var(--vscode-button-background);color:var(--vscode-button-foreground)}
button[aria-pressed=true]:hover{background:var(--vscode-button-hoverBackground)}
.strip{display:flex;justify-content:space-between;align-items:flex-start;gap:8px;margin-top:8px;padding-top:6px;border-top:1px solid var(--vscode-panel-border);color:var(--vscode-descriptionForeground);font-family:var(--vscode-editor-font-family);font-size:12px}
.tools{display:flex;gap:8px;align-items:center}
.strip label{display:flex;gap:4px;align-items:center;white-space:nowrap;font-family:var(--vscode-font-family)}
select{font-family:inherit;font-size:12px;padding:1px 4px;border-radius:2px;background:var(--vscode-dropdown-background);color:var(--vscode-dropdown-foreground);border:1px solid var(--vscode-dropdown-border,transparent)}
.speed{display:flex;gap:4px;align-items:center;font-size:12px}
.volume{display:flex;gap:4px;align-items:center;font-size:12px}.volume input{width:80px;accent-color:var(--vscode-button-background)}
.off{position:absolute;inset:0;display:flex;flex-direction:column;align-items:center;justify-content:center;gap:8px;border-radius:6px;background:rgba(0,0,0,0.72);color:#e0e0e0;text-align:center}
.off .title{font-size:16px;font-weight:600}
.off .name{font-size:12px;color:#b0b0b0}
.hint{margin-top:4px;font-size:11px;color:var(--vscode-descriptionForeground)}
.bezel.captured{border-color:var(--vscode-focusBorder);box-shadow:0 0 0 1px var(--vscode-focusBorder)}
.mouse{margin-top:6px;padding:3px 8px;border-radius:2px;font-size:12px;border:1px solid var(--vscode-panel-border);color:var(--vscode-descriptionForeground)}
.mouse.captured{background:var(--vscode-button-background);color:var(--vscode-button-foreground);border-color:var(--vscode-focusBorder)}
</style></head>
<body><div class="bezel" id="bezel"><div class="display" id="display"><canvas id="screen" tabindex="0" aria-label="The machine's display" data-vscode-context='{"webviewSection":"screen","preventDefaultContextMenuItems":true}'></canvas></div>
<div class="off" id="off" hidden role="status"><div class="title">Machine off</div><div class="name" id="offName"></div>
<div class="keys"><button id="restart" title="Starts the same launch again, with the cards and disks it last had">Restart</button>
<button id="startMachine" title="Picks a machine and what it runs: Retrocore: Start Machine">Start Machine…</button>
<button id="close" title="Closes this panel">Close</button></div></div></div>
<div class="mouse" id="mouseState" role="status" hidden></div>
<div class="keys" id="keybar">
<span class="keys" data-machine="apple2 apple3">
<button id="ctrl" aria-pressed="false" title="Makes the next letter a control character, as holding CONTROL does (or hold Ctrl)">Ctrl</button>
<button data-code="3" title="CONTROL-C: stops a BASIC program (or Ctrl+C)">Ctrl-C</button>
<button id="reset" title="CONTROL-RESET (or Ctrl+F12 or Ctrl+Break); with Open Apple down it restarts the machine">Ctrl-Reset</button>
<button data-code="27" title="ESC (or Esc)">Esc</button>
<button data-button="0" aria-pressed="false" title="Open Apple: stays down until clicked again (or hold the left Alt key)">Open Apple</button>
<button data-button="1" aria-pressed="false" title="Closed Apple: stays down until clicked again (or hold the right Alt key)">Closed Apple</button>
</span>
<span class="keys" data-machine="trs80-model1">
<button data-code="1" title="BREAK (or Esc)">Break</button>
<button data-code="31" title="CLEAR (or Home)">Clear</button>
<button id="trs80-reset" title="The reset button (or Ctrl+F12 or Ctrl+Break): boots a disk, or restarts BASIC with the program kept">Reset</button>
</span>
<span class="keys" data-machine="trs80-model3">
<button data-code="1" title="BREAK (or Esc)">Break</button>
<button data-code="31" title="CLEAR (or Home)">Clear</button>
<button id="model3-reset" title="The reset button (or Ctrl+F12 or Ctrl+Break): the ROM starts again">Reset</button>
</span>
<span class="keys" data-machine="trs80-model2">
<button data-code="3" title="BREAK (or Esc)">Break</button>
<button data-code="0" title="HOLD">Hold</button>
<button data-code="1" title="F1">F1</button>
<button data-code="2" title="F2">F2</button>
<button id="model2-reset" title="The reset switch (or Ctrl+F12 or Ctrl+Break): the boot ROM starts again">Reset</button>
</span>
<span class="keys" data-machine="trs80-model100">
<button data-code="128" title="F1">F1</button><button data-code="129" title="F2">F2</button><button data-code="130" title="F3">F3</button><button data-code="131" title="F4">F4</button><button data-code="132" title="F5">F5</button><button data-code="133" title="F6">F6</button><button data-code="134" title="F7">F7</button><button data-code="135" title="F8">F8</button>
<button data-code="136" title="LABEL: shows the function keys' labels">Label</button>
<button data-code="137" title="PRINT: prints the screen">Print</button>
<button data-code="138" title="PASTE: types the paste buffer">Paste</button>
<button data-code="139" title="PAUSE (or Pause): the PAUSE/BREAK key, which pauses a listing or program">Pause</button>
<button data-code="140" title="BREAK: PAUSE/BREAK with SHIFT, which stops a BASIC program">Break</button>
<button id="model100-reset" title="The RESET button (or Ctrl+F12 or Ctrl+Break): the 80C85 starts again, keeping RAM, and turns the machine on after POWER OFF">Reset</button>
</span>
<span class="keys" data-machine="kaypro2">
<button data-code="27" title="ESC (or Esc)">Esc</button>
<button id="kaypro-reset" title="The reset button (or Ctrl+F12 or Ctrl+Break): the monitor ROM boots CP/M from drive A again">Reset</button>
</span>
<span class="keys" data-machine="apple1">
<button data-code="27" title="ESC (or Esc): drops the line being typed">Esc</button>
<button id="apple1-reset" title="RESET (or Ctrl+F12 or Ctrl+Break): restarts the Monitor, keeping memory and the screen">Reset</button>
<button id="apple1-clear" title="CLEAR SCREEN: blanks the screen and puts the cursor at the top left">Clear Screen</button>
</span>
<span class="keys" data-machine="altair">
<button data-code="27" title="ESC (or Esc)">Esc</button>
<button id="altair-reset" title="The front panel's RESET (or Ctrl+F12 or Ctrl+Break): the 8080 starts again at $0000, keeping memory">Reset</button>
<button id="altair-clear" title="The terminal's CLEAR: blanks the screen and homes the cursor, as ^Z does">Clear Screen</button>
</span>
<span class="keys" data-machine="bbc">
<button data-code="27" title="ESCAPE (or Esc)">Escape</button>
<button data-code="135" title="COPY (or End): copies the character under the copy cursor">Copy</button>
<button data-code="140" title="SHIFT LOCK (or Scroll Lock): every key shifted until it is pressed again">Shift Lock</button>
<button data-code="240" title="f0">f0</button><button data-code="241" title="f1">f1</button><button data-code="242" title="f2">f2</button><button data-code="243" title="f3">f3</button><button data-code="244" title="f4">f4</button><button data-code="245" title="f5">f5</button><button data-code="246" title="f6">f6</button><button data-code="247" title="f7">f7</button><button data-code="248" title="f8">f8</button><button data-code="249" title="f9">f9</button>
<button id="bbc-reset" title="BREAK (or Ctrl+F12 or Ctrl+Break): the MOS starts again, keeping the program; OLD brings it back. With Shift, SHIFT-BREAK boots the disk in drive 0">Break</button>
</span>
<span class="keys" data-machine="atari800">
<button data-code="240" title="START: held for a tenth of a second">Start</button>
<button data-code="241" title="SELECT: held for a tenth of a second">Select</button>
<button data-code="242" title="OPTION: held for a tenth of a second">Option</button>
<button data-code="243" title="BREAK (or Pause)">Break</button>
<button data-code="244" title="SYSTEM RESET: the OS starts again warm, keeping the program; Ctrl+F12 or Ctrl+Break turns the machine off and on">System Reset</button>
</span>
<span class="keys" data-machine="coco">
<button data-code="1" title="BREAK (or Esc)">Break</button>
<button data-code="31" title="CLEAR (or Home)">Clear</button>
<button id="coco-reset" title="The RESET button (or Ctrl+F12 or Ctrl+Break): BASIC starts again with the program kept">Reset</button>
</span>
<span class="keys" data-machine="pet">
<button data-code="3" title="STOP (or Esc)">Stop</button>
<button data-code="147" title="CLR, the shifted HOME: clears the screen and homes the cursor">Clr</button>
<button id="pet-reset" title="A reset switch (or Ctrl+F12 or Ctrl+Break): the 6502, PIAs and VIA reset, keeping memory; the PET has no RESET key">Reset</button>
</span>
<span class="keys" data-machine="vic20">
<button data-code="3" title="RUN/STOP (or Esc)">Run/Stop</button>
<button data-code="256" title="RESTORE: the NMI, which does nothing unless a program asks it to, or RUN/STOP is down">Restore</button>
<button data-code="257" title="RUN/STOP and RESTORE together: the kernal's warm start, back to READY. with the program kept">Stop+Restore</button>
<button data-code="147" title="CLR, the shifted CLR/HOME: clears the screen and homes the cursor">Clr</button>
<button data-code="19" title="HOME (or Home)">Home</button>
<button data-code="258" title="SHIFT and the Commodore key: switches between the upper-case and graphics characters and the lower-case ones">C= Shift</button>
<button data-code="133" title="f1">f1</button><button data-code="137" title="f2, the shifted f1">f2</button>
<button data-code="134" title="f3">f3</button><button data-code="138" title="f4, the shifted f3">f4</button>
<button data-code="135" title="f5">f5</button><button data-code="139" title="f6, the shifted f5">f6</button>
<button data-code="136" title="f7">f7</button><button data-code="140" title="f8, the shifted f7">f8</button>
<button id="vic20-reset" title="A reset switch on the expansion port (or Ctrl+F12 or Ctrl+Break): the 6502, the VIAs and the drives reset, keeping memory; the VIC-20 has no RESET key">Reset</button>
</span>
<span class="keys end">
<button id="basic" hidden title="Opens the BASIC program in the machine's memory in an editor; saving puts it back">BASIC program</button>
<label class="speed" title="How fast the machine runs, as a multiple of its clock. Sound plays only at 1x.">Speed <select id="speed" aria-label="Speed">
<option value="1">1×</option><option value="2">2×</option><option value="4">4×</option><option value="8">8×</option><option value="max">Max</option>
</select></label>
</span>
<span class="keys" data-machine="apple2 apple3 coco pet vic20 bbc atari800">
<button id="sound" title="What you hear while the machine runs at its real speed: off, the speaker, or, with the Mockingboard in slot 4, the speaker and the Mockingboard (which slows emulation by about a quarter)">Sound: speaker</button>
<label class="volume" title="The sound's volume">Volume <input id="volume" type="range" min="0" max="100" step="1" value="50" aria-label="Volume"></label>
</span>
</div>
<div class="strip"><div><div id="status"></div><div id="disk"></div></div>
<span class="tools">
<button id="scale" title="Sharp: each dot a whole number of screen pixels, as large as fits. Fit: fills the panel's width.">Scale: sharp</button>
<label class="speed" id="screenChoice" hidden title="The monitor: color, a IIe's RGB card and monitor (Color RGB: solid colors without fringing), or a monochrome monitor of the time; on an Apple II it shows every dot sharply, as double hi-res desktops need">Screen <select id="screenType" aria-label="Screen">
<option value="color">Color</option><option value="rgb">Color RGB</option><option value="white">Black and white</option><option value="green">Green</option><option value="amber">Amber</option>
</select></label>
<label class="speed" id="tapeSpeedChoice" hidden title="Skip supported tape operations. Other operations run at Fast speed.">Tape speed <select id="tapeSpeed" aria-label="Tape speed">
<option value="normal">Normal</option><option value="fast">Fast</option><option value="skip">Skip</option>
</select></label>
<label class="speed" id="diskSpeedChoice" hidden title="Skip supported disk operations. Other operations run at Fast speed.">Disk speed <select id="diskSpeed" aria-label="Disk speed">
<option value="normal">Normal</option><option value="fast">Fast</option><option value="skip">Skip</option>
</select></label>
<button id="mediaSpeedHelp" hidden title="See the documentation for supported machines, images and operations">Media speed help</button>
<label id="details" title="While stopped, marks where the video beam is drawing"><input id="overlay" type="checkbox"> Beam overlay</label>
</span></div>
<div class="hint" id="hint"></div>
<pre id="text"></pre>
<script nonce="${nonce}">
const api=acquireVsCodeApi();
window.addEventListener('error',event=>api.postMessage({error:event.message}));
const screen=document.getElementById('screen');
let lastFrame;
// The IIe's 560 dots span its 280-dot-wide picture; the Model I's 384x192 and the Color Computer's picture, with its
// border, fill a 4:3 screen. The PET's 320x200 dots are square, and the Atari's 376 dots by 240
// lines fill 4:3, as the VIC-20's 200 dots by 248 lines (224 by 296 on PAL) do.
const aspect={'vic20':'4/3','apple2':'280/192','apple3':'280/192','trs80-model1':'4/3','trs80-model3':'4/3','trs80-model2':'4/3','kaypro2':'4/3','trs80-model100':'240/64','apple1':'280/192','coco':'4/3','altair':'4/3','pet':'320/200','bbc':'704/576','atari800':'4/3'};
// The picture is kept between frames: a running frame whose picture has not changed carries no pixels. The pixels
// decode straight into the kept ImageData, and the canvas is resized only when the picture's size changes.
let image;
let imageBytes;
let paintedOverlay=false;
// Speed: the setting the debug host keeps to, and while running what it measures, such as 1.00× · 1.02 MHz.
const speedSelect=document.getElementById('speed');
speedSelect.addEventListener('change',()=>{
    api.postMessage({command:'speed',speed:speedSelect.value==='max'?'max':Number(speedSelect.value)});
    screen.focus();
});
function speedText(frame){
    const speed=frame.speed;
    if(!speed||typeof speed.actual!=='number')return [];
    // Accelerated is the Model I's, Apple-1's, Color Computer's, PET's, VIC-20's or Atari's fast cassette or the IIe's
    // fast disk, running flat out while the media moves.
    const tapes=['trs80-model1','trs80-model3','apple1','coco','pet','vic20','bbc','atari800'];
    const fast=speed.accelerated===true?[frame.mediaSpeed?(frame.mediaSpeed.tape!==null&&frame.mediaSpeed.disk!==null?'Fast media':frame.mediaSpeed.tape!==null?'Fast tape':'Fast disk'):tapes.includes(frame.machine)?'Fast tape':'Fast disk']:[];
    return [...(speed.setting==='max'?['Max']:[]),...fast,speed.actual.toFixed(2)+'×',(speed.hertz/1e6).toFixed(2)+' MHz'];
}
const mediaSpeedKinds=['tape','disk'];
for(const kind of mediaSpeedKinds){
    const select=document.getElementById(kind+'Speed');
    select.addEventListener('change',()=>{api.postMessage({command:'mediaSpeed',kind,mode:select.value});screen.focus();});
}
const mediaSpeedHelp=document.getElementById('mediaSpeedHelp');
mediaSpeedHelp.addEventListener('click',()=>api.postMessage({command:'mediaSpeedHelp'}));
function mediaSpeedText(frame){
    const media=frame.mediaSpeed;
    if(!media)return [];
    const boot=media.boot;
    const parts=mediaSpeedKinds.filter(kind=>media[kind+'Fallback']).map(kind=>(kind==='tape'?'Tape':'Disk')+': Fast (Skip not supported)');
    if(!frame.running&&boot?.requested==='skip'){
        const label=boot.kind==='tape'?'Tape':'Disk';
        const result=boot.effective==='skip'?'Skip':'Fast (Skip not supported)';
        const text=label+': '+result;
        if(!parts.includes(text))parts.push(text);
    }
    return parts;
}
function draw(frame){
    const video=frame.video;
    if(frame.speed&&document.activeElement!==speedSelect)speedSelect.value=String(frame.speed.setting);
    let hasMediaSpeed=false;
    for(const kind of mediaSpeedKinds){
        const select=document.getElementById(kind+'Speed');
        const value=frame.mediaSpeed?.[kind];
        const supported=typeof value==='string';
        document.getElementById(kind+'SpeedChoice').hidden=!supported;
        if(!supported)continue;
        hasMediaSpeed=true;
        if(document.activeElement!==select)select.value=value;
    }
    mediaSpeedHelp.hidden=!hasMediaSpeed;
    if(!video||video.pixelFormat!=='rgba'||!(video.width>0)||!(video.height>0)){
        api.postMessage({error:'The display needs an updated debug host and an RGBA frame.'});return;
    }
    const iie=frame.machine==='apple2';
    const running=frame.running===true;
    document.getElementById('display').style.aspectRatio=aspect[frame.machine]??aspect['apple2'];
    document.getElementById('text').textContent=frame.rows.join('\\n');
    const ctx=screen.getContext('2d');
    const sized=image!==undefined&&image.width===video.width&&image.height===video.height;
    if(typeof video.pixels==='string'){
        if(!sized){
            screen.width=video.width;screen.height=video.height;
            image=ctx.createImageData(video.width,video.height);
            imageBytes=new Uint8Array(image.data.buffer,image.data.byteOffset,image.data.byteLength);
        }
        const {written}=imageBytes.setFromBase64(video.pixels);
        if(written!==imageBytes.length){api.postMessage({error:'Incorrect RGBA frame size from the debug host.'});return;}
    }else if(!sized){
        return;
    }
    const beamOverlay=iie&&!running&&document.getElementById('overlay').checked;
    if(typeof video.pixels==='string'||paintedOverlay||beamOverlay)ctx.putImageData(image,0,0);
    paintedOverlay=false;
    // While running, positions change every frame; they matter once stopped.
    document.getElementById('details').hidden=!iie;
    if(frame.machine==='apple3'){
        const drives=frame.disk?frame.disk.drives.filter(drive=>drive.mounted||drive.motor).map(drive=>'.D'+drive.drive
            +' track '+drive.track.toFixed(0)+(drive.motor?' · motor on':'')):[];
        document.getElementById('status').textContent=[running?'Running':frame.cycles+' cycles'].concat(running?speedText(frame):[],mediaSpeedText(frame)).join(' · ');
        document.getElementById('disk').textContent=drives.join(' | ');
        return;
    }
    if(!iie){
        const media=frame.media;
        // The Apple-1 has a cassette and no disks; the VIC-20's one Datasette has keys, as the PET's have.
        const cassette=media?.cassette;
        const state=cassette?.recording?'recording':cassette?.mode===undefined||cassette.mode==='playing'?'playing':'stopped';
        const tape=cassette?.path?['Tape '+state+(cassette.motor?' · motor on':'')]:[];
        // The PET's two Datasettes, each with its keys: stopped, playing or recording.
        for(const port of [1,2]){
            const deck=media?.['cassette'+port];
            if(!deck?.path)continue;
            tape.push('Tape '+port+' '+(deck.recording?'recording':deck.mode==='playing'?'playing':'stopped')+(deck.motor?' · motor on':''));
        }
        // The Atari's drives are D1: to D4:, numbered from 0 like the others'.
        const drive=disk=>frame.machine==='atari800'?'D'+(disk.drive+1)+':':'D'+disk.drive;
        // The TRS-80s name a drive and its cylinder; the PET's 4040 and 2040 name a unit's drive, as disk8-0, and a track,
        // and the VIC-20's 1541 and 1540 their device, as disk8.
        const diskLabel=disk=>typeof disk.device==='string'
            ?disk.device.replace(/^disk(\\d+)-(\\d)$/,'Unit $1 drive $2').replace(/^disk(\\d+)$/,'Device $1')+' track '+(Number.isInteger(disk.track)?disk.track:disk.track.toFixed(1))+(disk.motor?' · motor on':'')
            :drive(disk)+' cylinder '+disk.cylinder+(disk.selected?' · selected':'');
        const disks=media?.disks?media.disks.filter(disk=>disk.mounted).map(diskLabel):[];
        document.getElementById('status').textContent=[running?'Running':frame.cycles+' cycles'].concat(running?speedText(frame):[],mediaSpeedText(frame),tape).join(' · ');
        document.getElementById('disk').textContent=disks.join(' | ');
        return;
    }
    const beam=video.beam;
    if(running){
        const motors=frame.disk?frame.disk.drives.filter(drive=>drive.motor).map(drive=>'D'+drive.drive+' track '+drive.track.toFixed(0)):[];
        document.getElementById('status').textContent=['Running'].concat(speedText(frame),mediaSpeedText(frame),motors).join(' · ');
        document.getElementById('disk').textContent='';
        return;
    }
    if(beamOverlay){drawBeam(ctx,beam);paintedOverlay=true;}
    document.getElementById('status').textContent=frame.cycles+' cycles · line '+beam.scanline+' · column '+beam.column
        +' · frame cycle '+beam.cycleInFrame+(beam.verticalBlank?' · VBL':beam.horizontalBlank?' · HBL':'')
        +mediaSpeedText(frame).map(text=>' · '+text).join('');
    if(frame.disk){
        document.getElementById('disk').textContent=frame.disk.drives.map(drive=>'D'+drive.drive
            +': track '+drive.track.toFixed(2)+' · bit '+drive.bitPosition+'/'+drive.bitCount
            +' · motor '+(drive.motor?'on':'off')+(drive.writeProtected?' · locked':' · unlocked')
            +(drive.dirty?' · changed':'')).join(' | ');
    }
}
// A red cross where the beam is drawing. In blanking the beam is off the picture, so a dimmer marker points in
// from the edge it waits beside: the left of its line in horizontal blanking (columns 0-24 come before the line's
// picture), the bottom in vertical blanking (lines 192-261 come after the picture's last).
function drawBeam(ctx,beam){
    const x=(beam.column-25)*14+7;
    ctx.beginPath();
    if(!beam.horizontalBlank&&!beam.verticalBlank){
        ctx.strokeStyle='#ff4040';
        ctx.moveTo(x-7,beam.scanline);ctx.lineTo(x+7,beam.scanline);
        ctx.moveTo(x,beam.scanline-3);ctx.lineTo(x,beam.scanline+3);
    }else if(!beam.verticalBlank){
        ctx.strokeStyle='rgba(255,64,64,0.6)';
        // Kept whole inside the picture, as at line 0 where the power-on stop is.
        const y=beam.scanline+0.5;
        ctx.moveTo(0.5,Math.max(0,y-3));ctx.lineTo(0.5,Math.min(screen.height,y+3));
        ctx.moveTo(0.5,y);ctx.lineTo(8,y);
    }else{
        const bottom=screen.height-0.5;
        const at=beam.horizontalBlank?0.5:x;
        ctx.strokeStyle='rgba(255,64,64,0.6)';
        ctx.moveTo(at-3,bottom);ctx.lineTo(at+3,bottom);
        ctx.moveTo(at,bottom);ctx.lineTo(at,bottom-8);
    }
    ctx.stroke();
}
window.addEventListener('message',event=>{
    if(event.data&&event.data.audio){play(event.data.audio);return;}
    if(event.data&&typeof event.data.basic==='boolean'){document.getElementById('basic').hidden=!event.data.basic;return;}
    if(event.data&&event.data.ended){showOff(event.data.ended);return;}
    off.hidden=true;
    // A VIC-20 that changes standard changes its frame's size too.
    const changed=lastFrame?.machine!==event.data?.machine||lastFrame?.model!==event.data?.model||lastFrame?.standard!==event.data?.standard;
    lastFrame=event.data;draw(lastFrame);
    // A frame without it, as the Apple III's or the Color Computer's, is a machine with no Mockingboard.
    mockingboard=lastFrame?.mockingboard===true;
    if(typeof lastFrame?.sound==='string')showSound(lastFrame.sound);
    syncScreen(lastFrame);
    showMouse();
    if(changed)showKeys();
});
// The monitor: the panel's choice, kept with its state, wins over the launch's, and is sent again to each new session
// whose machine has that monitor. The menu offers the machine's own monitors, so no color on a monochrome machine.
const screenSelect=document.getElementById('screenType');
const screenNames={color:'Color',rgb:'Color RGB',white:'Black and white',green:'Green',amber:'Amber'};
let offeredScreens='';
const chosenScreen=()=>api.getState?.()?.screen;
if(typeof chosenScreen()==='string')screenSelect.value=chosenScreen();
let sentScreen;
screenSelect.addEventListener('change',()=>{
    api.setState?.({...(api.getState?.()??{}),screen:screenSelect.value});
    sentScreen=screenSelect.value;
    api.postMessage({command:'screen',screen:screenSelect.value});
    screen.focus();
});
function syncScreen(frame){
    const choice=document.getElementById('screenChoice');
    choice.hidden=typeof frame?.screen!=='string';
    if(choice.hidden)return;
    const screens=Array.isArray(frame.screens)?frame.screens.filter(name=>name in screenNames):[frame.screen];
    if(screens.join()!==offeredScreens){
        offeredScreens=screens.join();
        screenSelect.replaceChildren(...screens.map(name=>new Option(screenNames[name],name)));
        screenSelect.value=frame.screen;
    }
    const wanted=chosenScreen();
    if(typeof wanted==='string'&&wanted!==frame.screen&&screens.includes(wanted)){
        if(sentScreen!==wanted){sentScreen=wanted;api.postMessage({command:'screen',screen:wanted});}
        return;
    }
    sentScreen=undefined;
    if(document.activeElement!==screenSelect)screenSelect.value=frame.screen;
}
// Sound plays through Web Audio, which only starts after a click or key in the panel. Chunks are queued back to
// back a little ahead of the clock; one that would queue too far ahead, as when running faster than real time, is
// dropped rather than letting the delay grow.
const soundModes=['off','speaker','mockingboard'];
// Whether the Mockingboard is in slot 4: without it, the Sound button offers only off and the speaker.
let mockingboard=false;
const availableSounds=()=>mockingboard?soundModes:soundModes.filter(mode=>mode!=='mockingboard');
const soundLabels={off:'Sound: off',speaker:'Sound: speaker',mockingboard:'Sound: speaker + Mockingboard'};
let soundMode='speaker';
let audio;
let gain;
let audioTime=0;
// The volume, 0 to 1, kept with the panel's state so it survives the panel being hidden and shown.
const saved=api.getState?.();
let volume=typeof saved?.volume==='number'?saved.volume:0.5;
const volumeInput=document.getElementById('volume');
volumeInput.value=String(Math.round(volume*100));
volumeInput.addEventListener('input',()=>{
    volume=Number(volumeInput.value)/100;
    if(gain)gain.gain.value=volume;
    api.setState?.({...(api.getState?.()??{}),volume});
});
function showSound(mode){
    soundMode=mode;
    const button=document.getElementById('sound');
    button.textContent=soundLabels[mode]+(mode!=='off'&&audio?.state!=='running'?' (click the screen to hear it)':'');
}
function startAudio(){
    const Context=window.AudioContext;
    if(!Context)return;
    if(!audio){
        // A context made during a click or key starts out running; one made earlier starts suspended and runs
        // once a click or key resumes it. Either way the Sound button's hint follows its state.
        audio=new Context();
        audio.onstatechange=()=>showSound(soundMode);
        gain=audio.createGain();gain.gain.value=volume;gain.connect(audio.destination);
    }
    if(audio.state==='suspended')audio.resume().catch(()=>{});
    showSound(soundMode);
}
function play(chunk){
    if(!window.AudioContext)return;
    if(!audio)startAudio();
    if(!audio||audio.state!=='running')return;
    const bytes=atob(chunk.samples);
    const frames=Math.floor(bytes.length/(2*chunk.channels));
    if(frames===0)return;
    const buffer=audio.createBuffer(chunk.channels,frames,chunk.rate);
    for(let channel=0;channel<chunk.channels;channel++){
        const data=buffer.getChannelData(channel);
        for(let i=0;i<frames;i++){
            const at=(i*chunk.channels+channel)*2;
            const value=bytes.charCodeAt(at)|(bytes.charCodeAt(at+1)<<8);
            data[i]=(value>=32768?value-65536:value)/32768;
        }
    }
    const now=audio.currentTime;
    if(audioTime<now+0.02)audioTime=now+0.06;
    if(audioTime>now+0.3)return;
    const source=audio.createBufferSource();
    source.buffer=buffer;source.connect(gain??audio.destination);source.start(audioTime);
    audioTime+=buffer.duration;
}
document.getElementById('sound').addEventListener('click',()=>{
    startAudio();
    const modes=availableSounds();
    const mode=modes[(modes.indexOf(soundMode)+1)%modes.length];
    showSound(mode);
    api.postMessage({command:'sound',mode});
});
screen.addEventListener('pointerdown',()=>{if(soundMode!=='off')startAudio();});
// Beam overlay is off until ticked, and kept with the panel's state like the volume.
const overlay=document.getElementById('overlay');
overlay.checked=saved?.overlay===true;
overlay.addEventListener('change',()=>{
    api.setState?.({...(api.getState?.()??{}),overlay:overlay.checked});
    if(lastFrame)draw(lastFrame);
});
// Each machine's codes for its special keys: the Model I and Color Computer have arrows, CLEAR (Home) and BREAK
// (Escape).
const keys={
    'apple2':{Enter:13,Backspace:8,ArrowLeft:8,ArrowRight:21,ArrowUp:11,ArrowDown:10,Escape:27,Tab:9,Delete:127},
    'apple3':{Enter:13,Backspace:8,ArrowLeft:8,ArrowRight:21,ArrowUp:11,ArrowDown:10,Escape:27,Tab:9,Delete:127},
    'trs80-model1':{Enter:13,Backspace:8,ArrowLeft:8,ArrowRight:9,ArrowUp:11,ArrowDown:10,Home:31,Escape:1},
    'trs80-model3':{Enter:13,Backspace:8,ArrowLeft:8,ArrowRight:9,ArrowUp:11,ArrowDown:10,Home:31,Escape:1},
    // The Model II's keyboard sends ASCII, with its arrows as $1C-$1F and BREAK as $03.
    'trs80-model2':{Enter:13,Backspace:8,Tab:9,ArrowLeft:28,ArrowRight:29,ArrowUp:30,ArrowDown:31,Escape:3},
    // The Model 100's keys are ASCII, with its arrows as the codes its ROM gives them, $1C-$1F (right, left, up,
    // down), and PAUSE/BREAK as 139 (with SHIFT, BREAK, 140); its function keys are the buttons, as F1-F11 stay
    // with VS Code.
    'trs80-model100':{Enter:13,Backspace:8,Tab:9,Escape:27,ArrowRight:28,ArrowLeft:29,ArrowUp:30,ArrowDown:31,Pause:139},
    // The Kaypro II's keyboard sends ASCII, with its arrows as $F1-$F4; it has no BREAK.
    'kaypro2':{Enter:13,Backspace:8,Tab:9,Escape:27,Delete:127,ArrowUp:0xF1,ArrowDown:0xF2,ArrowLeft:0xF3,ArrowRight:0xF4},
    // The Apple-1's back arrow is the underscore, which the Monitor takes as a backspace.
    'apple1':{Enter:13,Backspace:95,ArrowLeft:95,Escape:27},
    'coco':{Enter:13,Backspace:8,ArrowLeft:8,ArrowRight:9,ArrowUp:11,ArrowDown:10,Home:31,Escape:1},
    // The BBC Micro's DELETE is 127, and its cursor keys and COPY are the MOS's codes &88-&8B and &87.
    // SHIFT LOCK is the keyboard's &8C, and £ its own key, SHIFT with _, whose code &60 the BBC shows as £.
    'bbc':{Enter:13,Backspace:127,Delete:127,Tab:9,Escape:27,End:135,ArrowLeft:136,ArrowRight:137,ArrowDown:138,ArrowUp:139,ScrollLock:140,'£':96},
    // The Atari types ATASCII: BACK S is $7E, TAB $7F, CLEAR $7D and the cursor keys $1C-$1F; BREAK, above 127, is
    // held rather than typed.
    'atari800':{Enter:13,Escape:27,Backspace:126,Tab:127,Home:125,ArrowUp:28,ArrowDown:29,ArrowLeft:30,ArrowRight:31,Pause:243},
    // The Altair's ADM-3A sends ASCII, with its arrows as ^H, ^L, ^K and ^J.
    'altair':{Enter:13,Backspace:8,Tab:9,Escape:27,Delete:127,ArrowLeft:8,ArrowRight:12,ArrowUp:11,ArrowDown:10},
    // The PET's keys are PETSCII: DEL 20, INST 148, the cursor keys 157, 29, 145 and 17, HOME 19 and STOP 3; Tab is
    // the business keyboard's TAB, which the graphics keyboard lacks.
    'pet':{Enter:13,Backspace:20,Delete:20,Insert:148,ArrowLeft:157,ArrowRight:29,ArrowUp:145,ArrowDown:17,Home:19,Escape:3,Tab:9},
    // The VIC-20's are PETSCII too, as the PET's are; it has no TAB.
    'vic20':{Enter:13,Backspace:20,Delete:20,Insert:148,ArrowLeft:157,ArrowRight:29,ArrowUp:145,ArrowDown:17,Home:19,Escape:3}
};
const hints={
    'apple2':'Ctrl+letter: control character · Ctrl+F12: CONTROL-RESET · left/right Alt: Open/Closed Apple',
    'trs80-model1':'Esc: BREAK · Home: CLEAR · arrows: the arrow keys · Ctrl+F12: reset',
    'trs80-model3':'Esc: BREAK · Home: CLEAR · arrows: the arrow keys · Ctrl+F12: reset',
    'trs80-model2':'Esc: BREAK · Ctrl+letter: control character · arrows: the arrow keys · Ctrl+F12: reset',
    'kaypro2':'Ctrl+letter: control character · Esc: ESC · arrows: the arrow keys · Ctrl+F12: reset',
    'trs80-model100':'Ctrl+letter: CTRL (but Ctrl+H, I and M: DEL, TAB, ENTER) · Esc: ESC · arrows: the arrow keys · Pause: PAUSE · the buttons: F1-F8, LABEL, PRINT, PASTE, PAUSE, BREAK · Ctrl+F12: RESET',
    'apple3':'Ctrl+letter: control character · arrows and Esc: the arrow and ESCAPE keys · Ctrl+F12: CONTROL-RESET · left/right Alt: Open/Solid Apple',
    'apple1':'Backspace: the back arrow (_) · Esc: ESC · Ctrl+F12: RESET · letters arrive as capitals',
    'coco':'Esc: BREAK · Home: CLEAR · arrows: the arrow keys · Ctrl+F12: RESET',
    'bbc':'Esc: ESCAPE · End: COPY · Scroll Lock: SHIFT LOCK · arrows: the cursor keys · the buttons: f0-f9 · Ctrl+F12: BREAK · Ctrl+Shift+F12: SHIFT-BREAK',
    'altair':'Ctrl+letter: control character · arrows: ^H ^J ^K ^L, as the ADM-3A sends them · Ctrl+F12: RESET',
    'pet':'Esc: STOP · Home: HOME · arrows: the cursor keys · Backspace: DEL · Insert: INST · Tab: TAB (business keyboard) · Ctrl+F12: reset',
    'vic20':'Esc: RUN/STOP · Home: HOME · arrows: the cursor keys · Backspace: DEL · Insert: INST · the buttons: RESTORE, CLR, the Commodore key and f1-f8 · Ctrl+F12: reset',
    'atari800':'Esc: ESC · Backspace: BACK S · Home: CLEAR · arrows: the cursor keys · Pause: BREAK · the buttons: START, SELECT, OPTION and SYSTEM RESET · Ctrl+F12: off and on',
};
// The II and II Plus have no Apple keys: the same buttons are the game port's push buttons 0 and 1, and the keyboard
// types only capitals.
const boardHint='Ctrl+letter: control character · Ctrl+F12: RESET · left/right Alt: game-port buttons 0 and 1 · letters arrive as capitals';
const machine=()=>lastFrame?.machine??'apple2';
const board=()=>machine()==='apple2'&&typeof lastFrame?.model==='string'&&!lastFrame.model.includes('IIe');
const ctrl=document.getElementById('ctrl');
// Sharp scaling: each dot a whole number of physical pixels across and down, keeping the screen's shape. The IIe's
// rows are twice as tall as its dots are wide (560x384 at 1x); the Model I's dots are 2 wide by 3 tall on its 4:3
// screen (768x576); the CoCo 1 and 2's 320x240 frame doubles to 640x480, and the CoCo 3's 704 dots by 249 lines
// show its lines twice over, about 4:3; the PET's 320x200 doubles to 640x400, and the
// Atari's 376 dots by 240 lines to 752x480, a little wider than 4:3. The VIC-20's dots are three wide by two tall,
// 600x496 on NTSC and 672x592 on PAL, a little narrower than its 4:3 TV. Sizes are in CSS pixels for the
// display's scaling, ratio physical pixels to each.
const sharpBase={'vic20':[600,496],'vic20pal':[672,592],'apple2':[560,384],'apple3':[560,384],'trs80-model1':[768,576],'trs80-model3':[640,480],'trs80-model2':[640,576],'kaypro2':[560,480],'trs80-model100':[720,192],'apple1':[560,384],'coco':[640,480],'coco3':[704,498],'altair':[640,480],'pet':[640,400],'bbc':[704,576],'atari800':[752,480]};
function sharpSize(machine,width,height,ratio){
    const key=machine==='coco'&&typeof lastFrame?.model==='string'&&lastFrame.model.endsWith('3')?'coco3'
        :machine==='vic20'&&lastFrame?.standard==='pal'?'vic20pal':machine;
    const [w,h]=sharpBase[key]??sharpBase['apple2'];
    const scale=Math.floor(Math.min(width*ratio/w,height*ratio/h));
    return scale>=1?{width:w*scale/ratio,height:h*scale/ratio,scale}:null;
}
// Sharp is the default and kept with the panel's state. Too small a panel for even 1x falls back to filling it.
let scaleMode=saved?.scale==='fit'?'fit':'sharp';
function layout(){
    const display=document.getElementById('display');
    const bezel=document.getElementById('bezel');
    const others=document.body.offsetHeight-display.offsetHeight;
    const size=scaleMode==='sharp'
        ?sharpSize(machine(),bezel.clientWidth-20,window.innerHeight-others,window.devicePixelRatio||1)
        :null;
    display.style.width=size?size.width+'px':'';
    display.style.height=size?size.height+'px':'';
    const button=document.getElementById('scale');
    button.textContent=scaleMode==='sharp'?'Scale: sharp'+(size?' ('+size.scale+'x)':' (too small, fits)'):'Scale: fit';
}
document.getElementById('scale').addEventListener('click',()=>{
    scaleMode=scaleMode==='sharp'?'fit':'sharp';
    api.setState?.({...(api.getState?.()??{}),scale:scaleMode});
    layout();screen.focus();
});
window.addEventListener('resize',layout);
// Moving to a monitor with other display scaling changes the physical pixels per CSS pixel.
function watchRatio(){
    if(!window.matchMedia)return;
    window.matchMedia('(resolution: '+(window.devicePixelRatio||1)+'dppx)').addEventListener('change',()=>{layout();watchRatio();},{once:true});
}
watchRatio();
function showKeys(){
    layout();
    for(const group of document.querySelectorAll('[data-machine]'))group.hidden=!group.dataset.machine.split(' ').includes(machine());
    const hint=board()?boardHint:(hints[machine()]??'');
    document.getElementById('hint').textContent=hint+' · right-click or Shift+Insert: paste · F1-F11 and Ctrl+Shift+P stay with VS Code';
    // The Apple keys' buttons name what they are on this model: the Apple III's second is Solid Apple, and its
    // CONTROL-RESET has no Open Apple variant, nor its sound a Mockingboard.
    const three=machine()==='apple3';
    const names=board()?['Button 0','Button 1']:three?['Open Apple','Solid Apple']:['Open Apple','Closed Apple'];
    document.getElementById('reset').title=three?'CONTROL-RESET (or Ctrl+F12 or Ctrl+Break)'
        :'CONTROL-RESET (or Ctrl+F12 or Ctrl+Break); with Open Apple down it restarts the machine';
    document.getElementById('sound').title=three?'What you hear while the machine runs at its real speed: off, or the speaker and the DAC'
        :machine()==='pet'?'What you hear while the machine runs at its real speed: off, or the speaker on the user port, which the VIA drives'
        :machine()==='vic20'?'What you hear while the machine runs at its real speed: off, or the three tones and noise of the VIC, through the TV'
        :'What you hear while the machine runs at its real speed: off, the speaker, or, with the Mockingboard in slot 4, the speaker and the Mockingboard (which slows emulation by about a quarter)';
    for(const button of [0,1]){
        const element=document.querySelector('[data-button="'+button+'"]');
        if(!element)continue;
        element.textContent=names[button];
        element.title=names[button]+': stays down until clicked again (or hold the '+(button===0?'left':'right')+' Alt key)';
    }
}
// Open and Closed Apple are buttons the IIe reads while they are down: held by Alt, or latched by their buttons.
const apple={0:{held:false,latched:false},1:{held:false,latched:false}};
function setApple(button){
    const state=apple[button];
    document.querySelector('[data-button="'+button+'"]').setAttribute('aria-pressed',String(state.held||state.latched));
    api.postMessage({button:Number(button),pressed:state.held||state.latched});
}
function send(code){
    if(ctrl.getAttribute('aria-pressed')==='true'){
        if(code>=97&&code<=122)code-=32;
        if(code>=64&&code<=95)code&=31;
        ctrl.setAttribute('aria-pressed','false');
    }
    api.postMessage({code});
}
// VS Code acts on every key that bubbles up to the panel's window, so the screen stops the keys the machine takes
// there. Function keys (the debugger's) and Ctrl+Shift+P still go to VS Code, as does Cmd on a Mac.
function forVsCode(event){
    if(event.metaKey)return true;
    if(/^F\\d+$/.test(event.key))return !(event.ctrlKey&&event.key==='F12');
    return event.ctrlKey&&event.shiftKey&&event.key.toUpperCase()==='P';
}
screen.addEventListener('keydown',event=>{
    if(forVsCode(event))return;
    event.stopPropagation();
    if(soundMode!=='off')startAudio();
    if(machine()==='apple2'||machine()==='apple3'){
        if(event.code==='AltLeft'||event.code==='AltRight'){
            const button=event.code==='AltLeft'?0:1;
            if(!apple[button].held){apple[button].held=true;setApple(button);}
            event.preventDefault();return;
        }
    }
    // Ctrl+F12 for keyboards without Break, which some laptops lack or hide behind Fn.
    // With Shift, the BBC Micro's SHIFT-BREAK.
    if(event.key==='Cancel'||(event.ctrlKey&&(event.key==='Pause'||event.key==='F12'))){
        api.postMessage(event.shiftKey?{command:'reset',shift:true}:{command:'reset'});event.preventDefault();return;
    }
    // Shift+Insert pastes, as the screen's Paste menu item does: the extension types the clipboard's text. Ctrl+V is
    // CONTROL-V, like any other Ctrl letter.
    if(event.shiftKey&&event.key==='Insert'){
        api.postMessage({command:'paste'});event.preventDefault();return;
    }
    // CONTROL with @, a letter or [ \\ ] ^ _ is that character less 64.
    if(event.ctrlKey&&!event.altKey&&event.key.length===1){
        const upper=event.key.toUpperCase().charCodeAt(0);
        if(upper>=64&&upper<=95){api.postMessage({code:upper&31});event.preventDefault();}
        return;
    }
    const special=keys[machine()]??keys['apple2'];
    // A typed character is ASCII; a special key's code can be above it, as the Kaypro II's arrows and the BBC's COPY,
    // cursor and function keys are, so a character such as ñ cannot press f1.
    const mapped=event.key in special;
    let code=mapped?special[event.key]:event.key.length===1?event.key.charCodeAt(0):-1;
    if(code>=0&&code<(mapped?256:128)){send(code);event.preventDefault();}
});
screen.addEventListener('keyup',event=>{
    if(forVsCode(event))return;
    event.stopPropagation();
    if(event.code==='AltLeft'||event.code==='AltRight'){
        const button=event.code==='AltLeft'?0:1;
        apple[button].held=false;setApple(button);event.preventDefault();
    }
});
// Text pasted by VS Code, as with Cmd+V on a Mac, is typed through the machine's keyboard,
// a key at a time as the program reads them.
screen.addEventListener('paste',event=>{
    const text=event.clipboardData?.getData('text/plain');
    event.preventDefault();
    if(text)api.postMessage({command:'paste',text});
});
// A key released while the panel lacks focus never sends its keyup, so a held Apple key lets go here.
window.addEventListener('blur',()=>{for(const button of [0,1])if(apple[button].held){apple[button].held=false;setApple(button);}});
for(const button of document.querySelectorAll('[data-button]')){
    button.addEventListener('click',()=>{const state=apple[button.dataset.button];state.latched=!state.latched;setApple(button.dataset.button);screen.focus();});
}
for(const button of document.querySelectorAll('[data-code]')){
    button.addEventListener('click',()=>{api.postMessage({code:Number(button.dataset.code)});screen.focus();});
}
ctrl.addEventListener('click',()=>{ctrl.setAttribute('aria-pressed',String(ctrl.getAttribute('aria-pressed')!=='true'));screen.focus();});
for(const id of ['reset','trs80-reset','model3-reset','model2-reset','model100-reset','kaypro-reset','apple1-reset','coco-reset','pet-reset','vic20-reset','altair-reset','bbc-reset']){
    document.getElementById(id).addEventListener('click',event=>{api.postMessage(event.shiftKey?{command:'reset',shift:true}:{command:'reset'});screen.focus();});
}
for(const id of ['apple1-clear','altair-clear']){
    document.getElementById(id).addEventListener('click',()=>{api.postMessage({command:'clearScreen'});screen.focus();});
}
// The session ended: the last picture stays, dimmed, with ways to go on. The next session's first frame hides it.
const off=document.getElementById('off');
function showOff(ended){
    document.getElementById('offName').textContent=typeof ended.name==='string'?ended.name:'';
    document.getElementById('basic').hidden=true;
    document.getElementById('status').textContent='Stopped';
    off.hidden=false;
    showMouse();
}
for(const id of ['restart','startMachine','close']){
    document.getElementById(id).addEventListener('click',()=>api.postMessage({command:id}));
}
document.getElementById('basic').addEventListener('click',()=>api.postMessage({command:'basic'}));
// The mouse card: a click on the screen locks the pointer to it, so the mouse moves the card's mouse and its left
// button is the card's; Escape lets go. Movement goes at most once a frame, in the picture's 280 by 192 dots.
let mouseX=0,mouseY=0,mouseQueued=false;
// A machine that has ended keeps its last frame, but no longer its mouse card.
const mouseCard=()=>off.hidden&&lastFrame?.machine==='apple2'&&lastFrame?.mouse>0;
const mouseLocked=()=>document.pointerLockElement===screen;
function sendMouse(){
    mouseQueued=false;
    const dx=Math.trunc(mouseX),dy=Math.trunc(mouseY);
    mouseX-=dx;mouseY-=dy;
    if(dx||dy)api.postMessage({mouse:{dx,dy}});
}
screen.addEventListener('mousedown',event=>{
    if(!mouseCard()||event.button!==0)return;
    if(!mouseLocked()){Promise.resolve(screen.requestPointerLock()).catch(()=>{});return;}
    api.postMessage({mouse:{pressed:true}});
});
screen.addEventListener('mouseup',event=>{if(mouseLocked()&&event.button===0)api.postMessage({mouse:{pressed:false}});});
screen.addEventListener('mousemove',event=>{
    if(!mouseLocked()||!mouseCard()||!screen.clientWidth||!screen.clientHeight)return;
    mouseX+=event.movementX*280/screen.clientWidth;
    mouseY+=event.movementY*192/screen.clientHeight;
    if(!mouseQueued){mouseQueued=true;requestAnimationFrame(sendMouse);}
});
document.addEventListener('pointerlockchange',()=>{
    if(!mouseLocked()&&mouseCard())api.postMessage({mouse:{pressed:false}});
    showMouse();
});
// Whether the mouse card has the pointer, and how to give it or take it back: a strip under the screen, and the
// screen's border, which lights while the pointer is captured.
function showMouse(){
    const state=document.getElementById('mouseState');
    const card=mouseCard();
    // Without a card to drive, as when it is taken out or the session ends, the pointer is the user's again.
    if(!card&&mouseLocked()){
        mouseX=mouseY=0;
        document.exitPointerLock?.();
    }

    const captured=card&&mouseLocked();
    state.hidden=!card;
    state.classList.toggle('captured',captured);
    document.getElementById('bezel').classList.toggle('captured',captured);
    if(!card)return;
    const text=captured
        ?'Mouse captured by the mouse card in slot '+lastFrame.mouse+' · press Esc to release it'
        :'Mouse card in slot '+lastFrame.mouse+' · click the screen to capture the mouse';
    if(state.textContent!==text)state.textContent=text;
}
showKeys();
// When VS Code gives the panel its focus, as a click on its tab does, the screen takes the keyboard unless a control in
// the page has it: the keys only reach the machine from the screen.
window.addEventListener('focus',()=>{if(document.activeElement===document.body||document.activeElement===null)screen.focus();});
${focusOnLoad ? "screen.focus();" : ""}
</script></body></html>`;
}
