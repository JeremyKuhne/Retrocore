// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using System.Diagnostics;
using System.Runtime.InteropServices;
using System.Security.Cryptography;
using Retrocore.Perf;

/// <summary>
///  Measures the same public CPU path in JIT, ReadyToRun, and native-published validation hosts.
/// </summary>
internal static class CpuThroughput
{
    /// <summary>
    ///  Runs the validated mixed workload, or an external 64 KiB benchmark image starting at $0300.
    /// </summary>
    /// <param name="args">An optional memory image, variant, warmup cycles, and timed cycles.</param>
    /// <returns>Zero after all samples validate.</returns>
    internal static int Run(string[] args)
    {
        if (args.Length > 4)
        {
            Console.Error.WriteLine("Usage: --benchmark-cpu [memory-image [variant [warmup-cycles [timed-cycles]]]]");
            return 1;
        }

        ProcessorVariant[] variants = args.Length >= 2
            ? [Enum.Parse<ProcessorVariant>(args[1], ignoreCase: true)]
            : Enum.GetValues<ProcessorVariant>();

        byte[]? image = args.Length == 0 ? null : File.ReadAllBytes(args[0]);
        if (image is not null && image.Length != 65536)
        {
            Console.Error.WriteLine("The external benchmark image must contain exactly 65536 bytes.");
            return 1;
        }

        Console.WriteLine($"runtime: {RuntimeInformation.FrameworkDescription}; {RuntimeInformation.ProcessArchitecture}");
        Console.WriteLine($"image: {(image is null ? "CpuWorkload" : Convert.ToHexString(SHA256.HashData(image)))}");
        foreach (ProcessorVariant variant in variants)
        {
            for (int sample = 0; sample < 3; sample++)
            {
                RamBus bus;
                Processor<RamBus> cpu;
                ulong warmup;
                ulong cycles;
                if (image is null)
                {
                    cpu = CpuWorkload.Create(variant, out bus);
                    warmup = CpuWorkload.CyclesPerLoop * 100_000;
                    cycles = CpuWorkload.CyclesPerLoop * 10_000_000;
                }
                else
                {
                    bus = new((byte[])image.Clone());
                    cpu = new(bus, variant);
                    ProcessorRegisters registers = cpu.Registers;
                    registers.ProgramCounter = 0x300;
                    registers.StackPointer = 0xFF;
                    cpu.Registers = registers;
                    warmup = args.Length >= 3 ? ulong.Parse(args[2]) : 10_000_000;
                    cycles = args.Length >= 4 ? ulong.Parse(args[3]) : 1_000_000_000;
                    ArgumentOutOfRangeException.ThrowIfZero(cycles);
                }

                cpu.Run(warmup);
                ulong from = cpu.CycleCount;
                long started = Stopwatch.GetTimestamp();
                cpu.Run(cycles);
                double seconds = Stopwatch.GetElapsedTime(started).TotalSeconds;
                ulong executed = cpu.CycleCount - from;
                if (executed != cycles || cpu.Status != ProcessorExecutionStatus.Running)
                {
                    throw new InvalidOperationException("The CPU did not execute the complete cycle budget.");
                }

                if (image is null)
                {
                    CpuWorkload.Validate(cpu, bus);
                }
                else if (cpu.Registers.ProgramCounter is < 0x300 or >= 0x400)
                {
                    throw new InvalidOperationException("The external benchmark left its expected code range.");
                }

                ProcessorRegisters final = cpu.Registers;
                Console.WriteLine($"{variant} sample {sample + 1}: {executed / seconds / 1e6:0.000} MHz; "
                    + $"{executed} cycles; {seconds:0.000000} s; PC ${cpu.Registers.ProgramCounter:X4}; "
                    + $"A ${final.Accumulator:X2} X ${final.X:X2} Y ${final.Y:X2} S ${final.StackPointer:X2} P ${(byte)final.Status:X2}; "
                    + $"RAM {Convert.ToHexString(SHA256.HashData(bus.Memory))}");
            }
        }

        return 0;
    }
}
