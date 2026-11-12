// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Debug;
using Retrocore.Machines.Apple2;

// "--sdk-roms <directory>" uses SDK sources other than the copy beside this host, which may itself be a copy made so
// that the build output stays writable while the host runs.
int sdkRoms = Array.IndexOf(args, "--sdk-roms");
if (sdkRoms >= 0 && sdkRoms + 1 < args.Length)
{
    SdkModules.DefaultDirectory = Path.GetFullPath(args[sdkRoms + 1]);
}

if (args.Length > 0 && args[0] == "--language-server")
{
    Retrocore.Debug.Language.LanguageHost.Run().GetAwaiter().GetResult();
    return;
}

if (args.Length > 0 && args[0] == "--assemble")
{
    Environment.ExitCode = AssembleCommand.Run(args[1..]);
    return;
}

if (args.Length > 0 && args[0] == "--basic")
{
    Environment.ExitCode = BasicCommand.Run(args[1..]);
    return;
}

if (args.Length > 0 && args[0] == "--dos")
{
    Environment.ExitCode = DosCommand.Run(args[1..]);
    return;
}

if (args.Length > 0 && args[0] == "--disassemble")
{
    Environment.ExitCode = DisassembleCommand.Run(args[1..]);
    return;
}

if (args.Length > 0 && args[0] is "--boot-probe" or "--boot-state")
{
    if (args.Length != 4)
    {
        throw new ArgumentException("--boot-probe requires rom-directory, disk-image, and original/enhanced.");
    }

    Apple2Model model = args[3] switch
    {
        "original" => Apple2Model.IIe,
        "enhanced" => Apple2Model.IIeEnhanced,
        _ => throw new ArgumentException("The boot model must be original or enhanced.")
    };

    Apple2Machine machine = Apple2Loader.Load(model, Apple2Roms.LoadFromDirectory(model, args[1]), args[2]);
    if (args[0] == "--boot-state")
    {
        machine.Run(cycles: 7);
        byte[] firmware = Enumerable.Range(0, 256).Select(offset => machine.Bus.Peek((ushort)(0xC700 + offset))).ToArray();
        bool reached = false;
        for (int count = 0; count < 5_000_000; count++)
        {
            ushort pc = machine.Processor.Registers.ProgramCounter;
            if (machine.Bus.MainMemory[0xBF00] == 0x4C
                && machine.Bus.Peek(pc) == 0xAD
                && machine.Bus.Peek((ushort)(pc + 1)) == 0
                && machine.Bus.Peek((ushort)(pc + 2)) == 0xC0)
            {
                reached = true;
                break;
            }

            if (machine.StepInstruction().Status != Retrocore.Cpu.ProcessorExecutionStatus.InstructionComplete)
            {
                throw new InvalidOperationException("CPU halted during ProDOS boot.");
            }
        }

        if (!reached)
        {
            throw new InvalidOperationException("ProDOS did not reach its initialized keyboard checkpoint.");
        }

        var r = machine.Processor.Registers;
        byte[] main = new byte[65536];
        byte[] auxiliary = new byte[65536];
        machine.Bus.CopyPhysicalRam(auxiliary: false, main);
        machine.Bus.CopyPhysicalRam(auxiliary: true, auxiliary);
        Console.WriteLine(new System.Text.Json.Nodes.JsonObject
        {
            ["pc"] = r.ProgramCounter, ["a"] = r.Accumulator, ["x"] = r.X, ["y"] = r.Y, ["s"] = r.StackPointer, ["p"] = (byte)r.Status,
            ["firmware"] = Convert.ToBase64String(firmware),
            ["main"] = Convert.ToBase64String(main),
            ["auxiliary"] = Convert.ToBase64String(auxiliary)
        }.ToJsonString());

        return;
    }

    machine.Run(cycles: 2_000_000);
    Console.WriteLine(
        $"PC={machine.Processor.Registers.ProgramCounter:X4} S={machine.Processor.Registers.StackPointer:X2} P={(byte)machine.Processor.Registers.Status:X2}");

    for (int row = 0; row < 24; row++)
    {
        Console.WriteLine(string.Concat(Enumerable.Range(0, 40).Select(column =>
        {
            int code = machine.Bus.TextByte(row, column) & 127;
            return (char)(code < 32 ? code + 64 : code);
        })));
    }

    Console.WriteLine(
        $"LC read={machine.Bus.LanguageCardRead} write={machine.Bus.LanguageCardWrite} bank2={machine.Bus.LanguageCardBank2} switches={machine.Bus.Switches}");

    return;
}

// The debugger: the Debug Adapter Protocol on standard input and output, until VS Code disconnects or closes the pipe.
DebugSession session = new();
DapTransport transport = new(Console.OpenStandardInput(), Console.OpenStandardOutput());
session.Register(transport, transport.Stop);
transport.Run();
