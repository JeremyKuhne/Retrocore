// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using System.Diagnostics;
using System.Security.Cryptography;
using Retrocore.Machines.Apple2;

/// <summary>
///  Runs an external RAM/ROM image through the real IIe cycle path or an isolated CPU/device diagnostic.
/// </summary>
internal static class MachineThroughput
{
    /// <summary>
    ///  Starts an enhanced IIe at $0300 with the external reference's initial CPU registers.
    /// </summary>
    /// <param name="args">Image path, component, warmup cycles, and timed cycles.</param>
    /// <returns>Zero after all samples execute their complete cycle budgets.</returns>
    internal static int Run(string[] args)
    {
        if (args.Length is < 1 or > 4)
        {
            Console.Error.WriteLine("Usage: --benchmark-machine image [machine|cpu|devices [warmup-cycles [timed-cycles]]]");
            return 1;
        }

        string component = args.Length >= 2 ? args[1] : "machine";
        if (component is not ("machine" or "cpu" or "devices"))
        {
            Console.Error.WriteLine($"Unknown benchmark component: {component}.");
            return 1;
        }

        byte[] image = File.ReadAllBytes(args[0]);
        if (image.Length != 65536)
        {
            Console.Error.WriteLine("The external image must contain exactly 65536 bytes.");
            return 1;
        }

        ulong warmup = args.Length >= 3 ? ulong.Parse(args[2]) : 10_000_001;
        ulong cycles = args.Length >= 4 ? ulong.Parse(args[3]) : 1_000_000_001;
        ArgumentOutOfRangeException.ThrowIfZero(cycles);
        Console.WriteLine($"component: {component}; image: {Convert.ToHexString(SHA256.HashData(image))}");
        for (int sample = 0; sample < 3; sample++)
        {
            Apple2Machine machine = new(Apple2Model.IIeEnhanced, new Apple2Roms(image.AsSpan(0xC000).ToArray(), new byte[4096]));
            for (int address = 0; address < 0xC000; address++)
            {
                machine.Bus.SetRam(auxiliary: false, (ushort)address, image[address]);
            }

            Processor<Apple2Bus> initial = new(machine.Bus, ProcessorVariant.Rockwell65C02);
            ProcessorRegisters registers = initial.Registers;
            registers.ProgramCounter = 0x300;
            registers.StackPointer = 0xFF;
            initial.Registers = registers;
            machine.Processor.RestoreState(initial.CaptureState());
            machine.Bus.Read(0xC050);
            machine.Bus.Read(0xC057);
            Advance(machine, component, warmup);
            ulong from = component == "cpu" ? machine.Processor.CycleCount : machine.Bus.CycleCount;
            long started = Stopwatch.GetTimestamp();
            Advance(machine, component, cycles);
            double seconds = Stopwatch.GetElapsedTime(started).TotalSeconds;
            ulong executed = (component == "cpu" ? machine.Processor.CycleCount : machine.Bus.CycleCount) - from;
            if (executed != cycles || machine.Processor.Status != ProcessorExecutionStatus.Running)
            {
                throw new InvalidOperationException("The machine did not execute its complete cycle budget.");
            }

            byte[] finalMemory = (byte[])image.Clone();
            machine.Bus.MainMemory[..0xC000].CopyTo(finalMemory);
            ProcessorRegisters final = machine.Processor.Registers;
            Console.WriteLine($"sample {sample + 1}: {executed / seconds / 1e6:0.000} MHz; {executed} cycles; {seconds:0.000000} s; "
                + $"PC ${final.ProgramCounter:X4}; A ${final.Accumulator:X2} X ${final.X:X2} Y ${final.Y:X2} "
                + $"S ${final.StackPointer:X2} P ${(byte)final.Status:X2}; RAM {Convert.ToHexString(SHA256.HashData(finalMemory))}");
        }

        return 0;
    }

    private static void Advance(Apple2Machine machine, string component, ulong cycles)
    {
        switch (component)
        {
            case "machine":
                machine.Run(cycles);
                break;
            case "cpu":
                machine.Processor.Run(cycles);
                break;
            case "devices":
                for (ulong cycle = 0; cycle < cycles; cycle++) { machine.Bus.Tick(); }
                break;
        }
    }
}
