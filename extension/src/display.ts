// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

// The machine's display panel. Its script is a template string: a backslash escape meant for the script must be
// written doubled, or it becomes the character itself; display.test.ts checks that the script parses.

/** The display panel's page, with its script allowed by the nonce. */
export function webviewHtml(nonce: string): string {
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
</style></head>
<body><div class="bezel" id="bezel"><div class="display" id="display"><canvas id="screen" tabindex="0" aria-label="The machine's display"></canvas></div>
<div class="off" id="off" hidden role="status"><div class="title">Machine off</div><div class="name" id="offName"></div>
<div class="keys"><button id="restart" title="Starts the same launch again, with the cards and disks it last had">Restart</button>
<button id="startMachine" title="Picks a machine and what it runs: Retrocore: Start Machine">Start Machine…</button>
<button id="close" title="Closes this panel">Close</button></div></div></div>
<div class="keys" id="keybar">
<span class="keys" data-machine="apple2">
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
<span class="keys end">
<button id="basic" hidden title="Opens the BASIC program in the machine's memory in an editor; saving puts it back">BASIC program</button>
<label class="speed" title="How fast the machine runs, as a multiple of its clock. Sound plays only at 1x.">Speed <select id="speed" aria-label="Speed">
<option value="1">1×</option><option value="2">2×</option><option value="4">4×</option><option value="8">8×</option><option value="max">Max</option>
</select></label>
</span>
<span class="keys" data-machine="apple2">
<button id="sound" title="What you hear while the machine runs at its real speed: off, the speaker, or, with the Mockingboard in slot 4, the speaker and the Mockingboard (which slows emulation by about a quarter)">Sound: speaker</button>
<label class="volume" title="The sound's volume">Volume <input id="volume" type="range" min="0" max="100" step="1" value="50" aria-label="Volume"></label>
</span>
</div>
<div class="strip"><div><div id="status"></div><div id="disk"></div></div>
<span class="tools">
<button id="scale" title="Sharp: each dot a whole number of screen pixels, as large as fits. Fit: fills the panel's width.">Scale: sharp</button>
<label data-machine="apple2" title="Runs as fast as it can while a Disk II drive's motor turns, then back at the chosen speed"><input id="fastDisk" type="checkbox" checked> Fast disk</label>
<label id="details" title="While stopped, marks where the video beam is drawing"><input id="overlay" type="checkbox"> Beam overlay</label>
</span></div>
<div class="hint" id="hint"></div>
<pre id="text"></pre>
<script nonce="${nonce}">
const api=acquireVsCodeApi();
window.addEventListener('error',event=>api.postMessage({error:event.message}));
const screen=document.getElementById('screen');
let lastFrame;
// The IIe's 560 dots span its 280-dot-wide picture; the Model I's 384x192 fills a 4:3 screen.
const aspect={'apple2':'280/192','trs80-model1':'4/3'};
// The picture is kept between frames: a running frame whose picture has not changed carries no pixels. The pixels
// decode straight into the kept ImageData, and the canvas is resized only when the picture's size changes.
let image;
let imageBytes;
// Speed: the setting the debug host keeps to, and while running what it measures, such as 1.00× · 1.02 MHz.
const speedSelect=document.getElementById('speed');
speedSelect.addEventListener('change',()=>{
    api.postMessage({command:'speed',speed:speedSelect.value==='max'?'max':Number(speedSelect.value)});
    screen.focus();
});
function speedText(frame){
    const speed=frame.speed;
    if(!speed||typeof speed.actual!=='number')return [];
    // Accelerated is the Model I's fast cassette or the IIe's fast disk, running flat out while the media moves.
    const fast=speed.accelerated===true?[frame.machine==='trs80-model1'?'Fast tape':'Fast disk']:[];
    return [...(speed.setting==='max'?['Max']:[]),...fast,speed.actual.toFixed(2)+'×',(speed.hertz/1e6).toFixed(2)+' MHz'];
}
const fastDisk=document.getElementById('fastDisk');
fastDisk.addEventListener('change',()=>{api.postMessage({command:'fastDisk',enabled:fastDisk.checked});screen.focus();});
function draw(frame){
    const video=frame.video;
    if(frame.speed&&document.activeElement!==speedSelect)speedSelect.value=String(frame.speed.setting);
    if(typeof frame.fastDisk==='boolean'&&document.activeElement!==fastDisk)fastDisk.checked=frame.fastDisk;
    if(!video||video.pixelFormat!=='rgba'||!(video.width>0)||!(video.height>0)){
        api.postMessage({error:'The display needs an updated debug host and an RGBA frame.'});return;
    }
    const iie=frame.machine!=='trs80-model1';
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
    ctx.putImageData(image,0,0);
    // While running, positions change every frame; they matter once stopped.
    const running=frame.running===true;
    document.getElementById('details').hidden=!iie;
    if(!iie){
        const media=frame.media;
        const tape=media&&media.cassette.path?['Tape '+(media.cassette.recording?'recording':'playing')+(media.cassette.motor?' · motor on':'')]:[];
        const disks=media?media.disks.filter(disk=>disk.mounted).map(disk=>'D'+disk.drive+' cylinder '+disk.cylinder+(disk.selected?' · selected':'')):[];
        document.getElementById('status').textContent=[running?'Running':frame.cycles+' cycles'].concat(running?speedText(frame):[],tape).join(' · ');
        document.getElementById('disk').textContent=disks.join(' | ');
        return;
    }
    const beam=video.beam;
    if(running){
        const motors=frame.disk?frame.disk.drives.filter(drive=>drive.motor).map(drive=>'D'+drive.drive+' track '+drive.track.toFixed(0)):[];
        document.getElementById('status').textContent=['Running'].concat(speedText(frame),motors).join(' · ');
        document.getElementById('disk').textContent='';
        return;
    }
    if(document.getElementById('overlay').checked)drawBeam(ctx,beam);
    document.getElementById('status').textContent=frame.cycles+' cycles · line '+beam.scanline+' · column '+beam.column
        +' · frame cycle '+beam.cycleInFrame+(beam.verticalBlank?' · VBL':beam.horizontalBlank?' · HBL':'');
    if(frame.disk){
        document.getElementById('disk').textContent=frame.disk.drives.map(drive=>'D'+drive.drive
            +': track '+drive.track.toFixed(2)+' · bit '+drive.bitPosition+'/'+drive.bitCount
            +' · motor '+(drive.motor?'on':'off')+(drive.writeProtected?' · protected':'')
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
    const changed=lastFrame?.machine!==event.data?.machine||lastFrame?.model!==event.data?.model;
    lastFrame=event.data;draw(lastFrame);
    if(typeof lastFrame?.mockingboard==='boolean')mockingboard=lastFrame.mockingboard;
    if(typeof lastFrame?.sound==='string')showSound(lastFrame.sound);
    if(changed)showKeys();
});
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
// Each machine's codes for its special keys: the Model I has arrows, CLEAR (Home) and BREAK (Escape).
const keys={
    'apple2':{Enter:13,Backspace:8,ArrowLeft:8,ArrowRight:21,ArrowUp:11,ArrowDown:10,Escape:27,Tab:9,Delete:127},
    'trs80-model1':{Enter:13,Backspace:8,ArrowLeft:8,ArrowRight:9,ArrowUp:11,ArrowDown:10,Home:31,Escape:1}
};
const hints={
    'apple2':'Ctrl+letter: control character · Ctrl+F12: CONTROL-RESET · left/right Alt: Open/Closed Apple',
    'trs80-model1':'Esc: BREAK · Home: CLEAR · arrows: the arrow keys · Ctrl+F12: reset'
};
// The II and II Plus have no Apple keys: the same buttons are the game port's push buttons 0 and 1, and the keyboard
// types only capitals.
const boardHint='Ctrl+letter: control character · Ctrl+F12: RESET · left/right Alt: game-port buttons 0 and 1 · letters arrive as capitals';
const machine=()=>lastFrame?.machine??'apple2';
const board=()=>machine()==='apple2'&&typeof lastFrame?.model==='string'&&!lastFrame.model.includes('IIe');
const ctrl=document.getElementById('ctrl');
// Sharp scaling: each dot a whole number of physical pixels across and down, keeping the screen's shape. The IIe's
// rows are twice as tall as its dots are wide (560x384 at 1x); the Model I's dots are 2 wide by 3 tall on its 4:3
// screen (768x576). Sizes are in CSS pixels for the display's scaling, ratio physical pixels to each.
const sharpBase={'apple2':[560,384],'trs80-model1':[768,576]};
function sharpSize(machine,width,height,ratio){
    const [w,h]=sharpBase[machine]??sharpBase['apple2'];
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
    for(const group of document.querySelectorAll('[data-machine]'))group.hidden=group.dataset.machine!==machine();
    const hint=board()?boardHint:(hints[machine()]??'');
    document.getElementById('hint').textContent=hint+' · F1-F11 and Ctrl+Shift+P stay with VS Code';
    // The Apple keys' buttons name what they are on this model.
    const names=board()?['Button 0','Button 1']:['Open Apple','Closed Apple'];
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
    if(machine()==='apple2'){
        if(event.code==='AltLeft'||event.code==='AltRight'){
            const button=event.code==='AltLeft'?0:1;
            if(!apple[button].held){apple[button].held=true;setApple(button);}
            event.preventDefault();return;
        }
    }
    // Ctrl+F12 for keyboards without Break, which some laptops lack or hide behind Fn.
    if(event.key==='Cancel'||(event.ctrlKey&&(event.key==='Pause'||event.key==='F12'))){
        api.postMessage({command:'reset'});event.preventDefault();return;
    }
    // CONTROL with @, a letter or [ \\ ] ^ _ is that character less 64.
    if(event.ctrlKey&&!event.altKey&&event.key.length===1){
        const upper=event.key.toUpperCase().charCodeAt(0);
        if(upper>=64&&upper<=95){api.postMessage({code:upper&31});event.preventDefault();}
        return;
    }
    const special=keys[machine()]??keys['apple2'];
    let code=event.key in special?special[event.key]:event.key.length===1?event.key.charCodeAt(0):-1;
    if(code>=0&&code<128){send(code);event.preventDefault();}
});
screen.addEventListener('keyup',event=>{
    if(forVsCode(event))return;
    event.stopPropagation();
    if(event.code==='AltLeft'||event.code==='AltRight'){
        const button=event.code==='AltLeft'?0:1;
        apple[button].held=false;setApple(button);event.preventDefault();
    }
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
for(const id of ['reset','trs80-reset']){
    document.getElementById(id).addEventListener('click',()=>{api.postMessage({command:'reset'});screen.focus();});
}
// The session ended: the last picture stays, dimmed, with ways to go on. The next session's first frame hides it.
const off=document.getElementById('off');
function showOff(ended){
    document.getElementById('offName').textContent=typeof ended.name==='string'?ended.name:'';
    document.getElementById('basic').hidden=true;
    document.getElementById('status').textContent='Stopped';
    off.hidden=false;
}
for(const id of ['restart','startMachine','close']){
    document.getElementById(id).addEventListener('click',()=>api.postMessage({command:id}));
}
document.getElementById('basic').addEventListener('click',()=>api.postMessage({command:'basic'}));
showKeys();
screen.focus();
</script></body></html>`;
}
