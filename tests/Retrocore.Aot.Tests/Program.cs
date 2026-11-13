// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Assembler;
using Retrocore.Machines.Apple2;
using Retrocore.Perf;
using NativeAssembler = Retrocore.Assembler.Assembler;

foreach (ProcessorVariant variant in Enum.GetValues<ProcessorVariant>())
{
    Processor<RamBus> cpu = CpuWorkload.Create(variant, out RamBus bus);
    for (int encoding = 0; encoding < 256; encoding++)
    {
        OpCode opcode = cpu.GetOpCode((byte)encoding);
        if (opcode.Code != encoding || opcode.Instruction.Summary.Length == 0 || opcode.AddressMode.Mnemonic.Length == 0)
        {
            throw new InvalidOperationException($"Invalid AOT opcode metadata: {variant} ${encoding:X2}.");
        }

    }

    cpu.Run(cycleBudget: CpuWorkload.CyclesPerLoop * 10000);
    CpuWorkload.Validate(cpu, bus);
    cpu.Run(cycleBudget: 17);
    ProcessorSnapshot snapshot = cpu.CaptureState();
    byte[] memory = (byte[])bus.Memory.Clone();
    cpu.Run(cycleBudget: CpuWorkload.CyclesPerLoop - 17);
    CpuWorkload.Validate(cpu, bus);
    memory.CopyTo(bus.Memory, index: 0);
    cpu.RestoreState(snapshot);
    cpu.Run(cycleBudget: CpuWorkload.CyclesPerLoop - 17);
    CpuWorkload.Validate(cpu, bus);
    Console.WriteLine($"{variant}: opcode metadata, representative execution, and mid-instruction restore passed.");
}

byte[] system = new byte[16384];
foreach (ProcessorVariant variant in Enum.GetValues<ProcessorVariant>())
{
    NativeAssembler assembler = new();
    AssemblyResult image = assembler.Assemble(
        new AssemblySource("lda #$A5\nsta $42\nrts"),
        new(variant, origin: 0, imageSize: 8));

    if (!image.Success || image.Sections[0].Bytes.Span[0] != 0xA9 || image.Sections[0].Bytes.Span[1] != 0xA5)
    {
        throw new InvalidOperationException("Native AOT public assembler failed.");
    }

    Console.WriteLine($"{variant}: Native AOT public assembler passed.");
    DisassemblyResult disassembly = Disassembler.Disassemble(image.Sections[0].Bytes.Span, origin: 0, variant);
    AssemblyResult roundTrip = assembler.Assemble(disassembly.ToAssemblyProject(), disassembly.Options);
    if (!disassembly.Success
        || !roundTrip.Success
        || !roundTrip.Sections[0].Bytes.Span.SequenceEqual(image.Sections[0].Bytes.Span))
    {
        throw new InvalidOperationException("Native AOT disassembly/model round trip failed.");
    }

    Console.WriteLine($"{variant}: Native AOT disassembly, native source export and model round trip passed.");
}

system[0x3FFC] = 0x00;
system[0x3FFD] = 0x20;
// Both IIe models: their auxiliary memory, text and double hi-res.
foreach (Apple2Model model in Enum.GetValues<Apple2Model>().Where(model => model.IsIIe()))
{
    Apple2Machine machine = new(model, new Apple2Roms(system, new byte[4096]));
    machine.Run(cycles: 7);
    machine.Bus.Write(0xC003, value: 0);
    machine.Bus.SetRam(auxiliary: true, address: 0x2000, value: 0x5A);
    if (machine.Bus.Read(0x2000) != 0x5A || machine.Bus.RenderTextBitmap().Length != 280 * 192)
    {
        throw new InvalidOperationException("Native AOT IIe banking or text rendering failed.");
    }

    machine.Bus.Read(0xC050);
    machine.Bus.Read(0xC057);
    machine.Bus.Read(0xC05E);
    machine.Bus.Write(0xC00D, value: 0);
    machine.Bus.SetRam(auxiliary: true, address: 0x2000, value: 0);
    machine.Bus.SetRam(auxiliary: false, address: 0x2000, value: 1);
    byte[] video = machine.Bus.Video.RenderBitmap();
    machine.Run(Apple2Video.CyclesPerFrame);
    if (video.Length != 560 * 192 * 4
        || video[16] != 221
        || !MemoryExtensions.SequenceEqual(machine.Bus.Video.RenderScannedBitmap(), video)
        || machine.Bus.Video.Beam.CycleInFrame != 7)
    {
        throw new InvalidOperationException("Native AOT IIe DHGR or video scanning failed.");
    }

    Console.WriteLine($"{model}: Native AOT IIe memory, text, DHGR and beam passed.");
}

// The Z80: its description, a T-state run with a mid-instruction restore, and assembly with disassembly.
byte[] z80Memory = new byte[0x10000];
byte[] z80Program = [0x06, 0x10, 0xDD, 0x21, 0x00, 0x30, 0xDD, 0x34, 0x02, 0x10, 0xFB, 0x76];
z80Program.CopyTo(z80Memory, 0);
Z80Processor<Z80RamBus> z80 = new(new Z80RamBus(z80Memory));
for (int index = 0; index < 40; index++) { z80.StepCycle(); }
Z80Snapshot z80Snapshot = z80.CaptureState();
while (!z80.IsHalted) { z80.StepCycle(); }
ulong z80Cycles = z80.CycleCount;
z80Memory[0x3002] = 0;
z80.RestoreState(z80Snapshot);
while (!z80.IsHalted) { z80.StepCycle(); }
if (z80Memory[0x3002] != 0x10 || z80.CycleCount != z80Cycles || z80.Registers.B != 0)
{
    throw new InvalidOperationException("Native AOT Z80 execution or restore failed.");
}

AssemblyResult z80Image = new NativeAssembler().Assemble(
    new AssemblySource(".cpu Z80\nLD A,[IX+5]\nSET 3,[IY-2]\nEX AF,AF'\nHere: JR Here"),
    new(Z80Isa.Name, origin: 0x4000, imageSize: 10));

DisassemblyResult z80Disassembly = Disassembler.Disassemble(z80Image.Sections[0].Bytes.Span, 0x4000, Z80Isa.InstructionSet);
AssemblyResult z80RoundTrip = new NativeAssembler().Assemble(
    new AssemblySource(z80Disassembly.ExportSource()),
    z80Disassembly.Options);

if (!z80Image.Success
    || !z80RoundTrip.Success
    || !z80RoundTrip.Sections[0].Bytes.Span.SequenceEqual(z80Image.Sections[0].Bytes.Span)
    || z80Image.Sections[0].Bytes.Span[0] != 0xDD)
{
    throw new InvalidOperationException("Native AOT Z80 assembly or disassembly failed.");
}

Console.WriteLine("Z80: Native AOT T-state execution, mid-instruction restore, assembly and disassembly passed.");

// The 8080 and 8085: native assembly, state-stepped execution with mid-instruction restore, and disassembly.
foreach (I8080Variant variant in Enum.GetValues<I8080Variant>())
{
    Retrocore.Isa.InstructionSet intelSet = I8080Isa.Get(variant);
    AssemblyResult intelImage = new NativeAssembler().Assemble(
        new AssemblySource(
            $"""
            .cpu {intelSet.Name}
                    MVI B,$10
                    LXI H,$3000
            Loop:   INR M
                    PUSH PSW
                    POP PSW
                    DCR B
                    JNZ Loop
                    HLT
            """),
        new(intelSet.Name, origin: 0, imageSize: 13));

    byte[] intelMemory = new byte[0x10000];
    intelImage.Sections[0].Bytes.Span.CopyTo(intelMemory);
    I8080Processor<Z80RamBus> intel = new(new Z80RamBus(intelMemory), variant);
    for (int index = 0; index < 40; index++) { intel.StepCycle(); }
    I8080Snapshot intelSnapshot = intel.CaptureState();
    while (!intel.IsHalted) { intel.StepCycle(); }
    ulong intelCycles = intel.CycleCount;
    intelMemory[0x3000] = 1;
    intel.RestoreState(intelSnapshot);
    while (!intel.IsHalted) { intel.StepCycle(); }
    DisassemblyResult intelDisassembly = Disassembler.Disassemble(intelImage.Sections[0].Bytes.Span, 0, intelSet);
    AssemblyResult intelRoundTrip = new NativeAssembler().Assemble(
        new AssemblySource(intelDisassembly.ExportSource()),
        intelDisassembly.Options);

    if (!intelImage.Success
        || intelMemory[0x3000] != 0x10
        || intel.CycleCount != intelCycles
        || intel.Registers.B != 0
        || !intelRoundTrip.Success
        || !intelRoundTrip.Sections[0].Bytes.Span.SequenceEqual(intelImage.Sections[0].Bytes.Span))
    {
        throw new InvalidOperationException($"Native AOT {variant} execution, restore, assembly or disassembly failed.");
    }
}

Console.WriteLine("8080 and 8085: Native AOT state execution, mid-instruction restore, assembly and disassembly passed.");

// The MC6809: native assembly, cycle-stepped execution with mid-instruction restore, and 5-byte round-trip disassembly.
AssemblyResult m6809Image = new NativeAssembler().Assemble(
    new AssemblySource(
        """
        .cpu M6809
                .org $0200
                LDS #$2000
                LDB #$10
                LDX #$3000
        Loop:   INC 2,X
                CMPD [$1234,X]
                PSHS A,B,X
                PULS A,B,X
                DECB
                BNE Loop
                SYNC
        """),
    new(M6809Isa.Name, origin: 0x0200, imageSize: 32));

if (!m6809Image.Success)
{
    throw new InvalidOperationException("Native AOT M6809 assembly failed.");
}

byte[] m6809Memory = new byte[0x10000];
m6809Image.Sections[0].Bytes.Span.CopyTo(m6809Memory.AsSpan(0x0200));
M6809Processor<RamBus> m6809 = new(new RamBus(m6809Memory));
m6809.Registers = m6809.Registers with { PC = 0x0200 };
for (int index = 0; index < 45; index++) { m6809.StepCycle(); }
M6809Snapshot m6809Snapshot = m6809.CaptureState();
byte savedCell = m6809Memory[0x3002];
while (!m6809.IsWaiting) { m6809.StepCycle(); }
ulong m6809Cycles = m6809.CycleCount;
m6809Memory[0x3002] = savedCell;
m6809.RestoreState(m6809Snapshot);
while (!m6809.IsWaiting) { m6809.StepCycle(); }
if (m6809Memory[0x3002] != 0x10 || m6809.CycleCount != m6809Cycles || m6809.Registers.B != 0 || !m6809.Registers.NmiArmed)
{
    throw new InvalidOperationException("Native AOT M6809 execution or restore failed.");
}

DisassemblyResult m6809Disassembly = Disassembler.Disassemble(m6809Image.Sections[0].Bytes.Span, 0x0200, M6809Isa.InstructionSet);
AssemblyResult m6809RoundTrip = new NativeAssembler().Assemble(
    new AssemblySource(m6809Disassembly.ExportSource()),
    m6809Disassembly.Options);

if (!m6809Disassembly.Success
    || !m6809RoundTrip.Success
    || !m6809RoundTrip.Sections[0].Bytes.Span.SequenceEqual(m6809Image.Sections[0].Bytes.Span))
{
    throw new InvalidOperationException("Native AOT M6809 disassembly round trip failed.");
}

Console.WriteLine("M6809: Native AOT execution, mid-instruction restore, assembly and disassembly passed.");

// The TRS-80 Model I: a tiny ROM from the native assembler writes to video RAM and halts.
AssemblyResult modelOneRom = new NativeAssembler().Assemble(
    new AssemblySource(".cpu Z80\nLD HL,$3C00\nLD [HL],'O'\nINC HL\nLD [HL],'K'\nHALT"),
    new(Z80Isa.Name, origin: 0, imageSize: 0x3000));

Retrocore.Machines.Trs80.Trs80Machine modelOne = new(
    new() { RamKilobytes = 16, ExpansionInterface = false },
    new(modelOneRom.Sections[0].Bytes.Span, new byte[Retrocore.Machines.Trs80.Trs80Roms.CharacterGeneratorSize]));

modelOne.Run(1000);
byte[] modelOneScreen = new byte[modelOne.Bus.Video.Width * modelOne.Bus.Video.Height * 4];
modelOne.Bus.Video.Render(modelOneScreen, scanned: false);
if (!modelOne.Processor.IsHalted || modelOne.Bus.Video.Read(0) != 'O' || modelOne.Bus.Video.Read(1) != 'K')
{
    throw new InvalidOperationException("Native AOT Model I execution failed.");
}

Console.WriteLine("Model I: Native AOT machine, video RAM and rendering passed.");

// The Color Computer: a tiny Color BASIC ROM from the native assembler writes OK to the text screen and loops.
AssemblyResult cocoCode = new NativeAssembler().Assemble(
    new AssemblySource(".cpu M6809\nLDA #$0F\nSTA $0400\nLDA #$0B\nSTA $0401\nLOOP: BRA LOOP"),
    new(M6809Isa.Name, origin: 0xA000, imageSize: 0x20));

byte[] colorBasic = new byte[Retrocore.Machines.Coco.CocoRoms.BasicSize];
cocoCode.Sections[0].Bytes.Span.CopyTo(colorBasic);
colorBasic[^2] = 0xA0;
colorBasic[^1] = 0x00;
Retrocore.Machines.Coco.CocoMachine coco = new(
    new() { Model = Retrocore.Machines.Coco.CocoModel.Coco2, RamKilobytes = 16 },
    Retrocore.Machines.Coco.CocoRoms.ForCoco12(colorBasic, []));

coco.Run(1000);
coco.StepInstruction();
Retrocore.Machines.IVideoSource cocoVideo = coco.Bus.VideoOutput;
byte[] cocoScreen = new byte[cocoVideo.Width * cocoVideo.Height * 4];
cocoVideo.Render(cocoScreen, scanned: false);
if (coco.Bus.Peek(0x0400) != 0x0F || coco.Bus.Peek(0x0401) != 0x0B || coco.Processor.Registers.PC != 0xA00A)
{
    throw new InvalidOperationException("Native AOT Color Computer execution failed.");
}

Console.WriteLine("Color Computer: Native AOT machine, SAM, VDG and rendering passed.");
