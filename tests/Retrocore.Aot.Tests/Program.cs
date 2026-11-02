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
