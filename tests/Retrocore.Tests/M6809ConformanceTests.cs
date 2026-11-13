// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using System.Globalization;
using Retrocore.Cpu.M6809;

namespace Retrocore.Tests;

/// <summary>
///  The MC6809 against the externally pinned functional and cycle-count programs.
/// </summary>
[TestClass]
public class M6809ConformanceTests
{
    private const ulong MaximumCycles = 5_000_000;

    /// <summary>
    ///  Every documented instruction and addressing mode passes its functional checks.
    /// </summary>
    [TestMethod]
    [TestCategory("Conformance")]
    [Timeout(120_000)]
    public void FunctionalProgramPasses()
    {
        RunProgram("bin/6809_functional_test.s19");
    }

    /// <summary>
    ///  Instruction cycle counts match the suite's data-sheet checks.
    /// </summary>
    [TestMethod]
    [TestCategory("Conformance")]
    [Timeout(120_000)]
    public void CycleProgramPasses()
    {
        RunProgram("bin/6809_cycle_test.s19");
    }

    /// <summary>
    ///  IRQ, FIRQ, NMI, SYNC, CWAI, and interrupt masks match the device-driven program.
    /// </summary>
    [TestMethod]
    [TestCategory("Conformance")]
    [Timeout(120_000)]
    public void InterruptProgramPasses()
    {
        RunProgram("bin/6809_interrupt_test.s19");
    }

    private static void RunProgram(string fixture)
    {
        string fixtureRoot = Path.Join(ExternalTestData.Cache, ExternalTestData.M6809Pin);
        if (!File.Exists(Path.Join(fixtureRoot, "manifest.json")))
        {
            Assert.Inconclusive("MC6809 fixtures are missing. Run tools\\Fetch-M6809Tests.ps1 with PowerShell 7.");
        }

        M6809TestBus bus = new();
        LoadSRecord(ExternalTestData.Read(ExternalTestData.M6809Pin, fixture), bus.Memory);
        M6809Processor<M6809TestBus> cpu = new(bus);
        bus.CycleCount = () => cpu.CycleCount;
        bus.SetSignals = signals => cpu.Signals = signals;
        cpu.Reset();

        while (!bus.Exited && cpu.CycleCount < MaximumCycles)
        {
            bus.AdvanceTo(cpu.CycleCount);
            cpu.StepCycle();
        }

        if (cpu.CycleCount >= MaximumCycles)
        {
            M6809Registers registers = cpu.Registers;
            byte testCase = bus.Memory[0x0100];
            string message = $"{fixture} stuck at ${registers.PC:X4}, A=${registers.A:X2}, CC=${registers.CC:X2}, test ${testCase:X2}.";
            Assert.Fail(message);
        }

        bus.ExitCode.Should().Be((byte)0, $"{fixture}; test case ${bus.Memory[0x0100]:X2}.");
    }

    private static void LoadSRecord(ReadOnlySpan<byte> file, byte[] memory)
    {
        string text = System.Text.Encoding.ASCII.GetString(file);
        using StringReader reader = new(text);
        while (reader.ReadLine() is { } line)
        {
            if (line.Length < 4 || line[0] != 'S')
            {
                throw new InvalidDataException("Malformed S-record.");
            }

            int type = line[1] - '0';
            int count = ByteAt(line, 2);
            if (line.Length != 4 + 2 * count)
            {
                throw new InvalidDataException("Invalid S-record length.");
            }

            int checksum = count;
            for (int offset = 4; offset < line.Length; offset += 2)
            {
                checksum += ByteAt(line, offset);
            }

            if ((checksum & 0xFF) != 0xFF)
            {
                throw new InvalidDataException("Invalid S-record checksum.");
            }

            int addressBytes;
            switch (type)
            {
                case 0:
                case 1:
                case 5:
                case 9:
                    addressBytes = 2;
                    break;
                case 2:
                case 6:
                case 8:
                    addressBytes = 3;
                    break;
                case 3:
                case 7:
                    addressBytes = 4;
                    break;
                default:
                    throw new InvalidDataException($"Unsupported S-record type S{type}.");
            }

            if (type is not (1 or 2 or 3))
            {
                continue;
            }

            int address = 0;
            for (int index = 0; index < addressBytes; index++)
            {
                address = (address << 8) | ByteAt(line, 4 + index * 2);
            }

            int dataStart = 4 + addressBytes * 2;
            int dataLength = count - addressBytes - 1;
            for (int index = 0; index < dataLength; index++)
            {
                memory[(address + index) & 0xFFFF] = (byte)ByteAt(line, dataStart + index * 2);
            }
        }
    }

    private static int ByteAt(string text, int offset) =>
        int.Parse(text.AsSpan(offset, 2), NumberStyles.HexNumber, CultureInfo.InvariantCulture);
}
