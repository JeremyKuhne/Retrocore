// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Basic;
using Retrocore.Machines.Apple3;
using Retrocore.Media;

namespace Retrocore.Tests;

/// <summary>
///  SOS 1.3 on the Apple III, from Apple's disks: the System Utilities boot, format and copy, and Business BASIC runs
///  and saves a program.
/// </summary>
/// <remarks>
///  <para>
///   The disks are in <c>RETROCORE_APPLE3_DISKS</c> or <c>%USERPROFILE%\Retrocore\apple3-disks</c>; the tests are
///   inconclusive without them or the ROM. Each waits for text on the screen rather than for a time.
///  </para>
/// </remarks>
[TestClass]
public class Apple3SosTests
{
    private const string Utilities = "Apple3SOS1.3SysUtils.dsk";
    private const string BusinessBasic = "Apple3BusBasic1.23.dsk";

    private static string Disks => Environment.GetEnvironmentVariable("RETROCORE_APPLE3_DISKS")
        ?? Path.Join(ExternalTestData.Root, "apple3-disks");

    /// <summary>
    ///  The System Utilities format a blank disk in .D2, copy the boot disk onto it, and the copy boots to their menu.
    /// </summary>
    [TestMethod]
    public void UtilitiesFormatAndCopyADiskThatBoots()
    {
        Apple3Machine machine = Boot(Utilities);
        machine.Drives[1].Insert(WozDisk.CreateBlank(), "blank", "WOZ");
        RunUntil(machine, "Please select a command", seconds: 90);

        Type(machine, "D");
        RunUntil(machine, "Device Handling Commands Menu", seconds: 10);
        Type(machine, "F");
        RunUntil(machine, "with the new volume name", seconds: 10);
        Type(machine, "\r");
        machine.Run(TimeSpan.FromSeconds(1));
        Type(machine, "TEST\r");
        RunUntil(machine, "Formatting successful", seconds: 60);

        Type(machine, "\u001B");
        RunUntil(machine, "Device Handling Commands Menu", seconds: 10);
        Type(machine, "C");
        RunUntil(machine, "With the new volume name", seconds: 10);
        Type(machine, ".D1\r");
        machine.Run(TimeSpan.FromSeconds(1));
        Type(machine, ".D2\r");
        machine.Run(TimeSpan.FromSeconds(1));
        Type(machine, "\r");
        RunUntil(machine, "Destroy old /TEST", seconds: 20);
        Type(machine, "Y");
        RunUntil(machine, "Copy successful", seconds: 120);

        WozDisk copy = machine.Drives[1].Eject() ?? throw new InvalidOperationException("The copy left the drive.");
        Apple3Machine second = Apple3MachineTests.Machine();
        second.Drives[0].Insert(WozDisk.Load(copy.Export()), "copy", "WOZ");
        RunUntil(second, "Please select a command", seconds: 90);
        Screen(second).Should().Contain("Apple /// Utilities");
    }

    /// <summary>
    ///  Business BASIC runs a typed program, with shifted symbols, and saves it where an unlocked and deleted file
    ///  was.
    /// </summary>
    [TestMethod]
    public void BusinessBasicRunsAndSavesAProgram()
    {
        Apple3Machine machine = Boot(BusinessBasic);
        RunUntil(machine, "TOTAL BLOCKS", seconds: 90);
        machine.Run(TimeSpan.FromSeconds(2));

        Type(machine, "HOME\r10 PRINT 6*7;\"!\"\rRUN\r");
        RunUntil(machine, "42!", seconds: 10);

        // HELLO ends with NEW, so the program in memory, read through BASIC's banked pointers, is the typed line.
        BasicProgram typed = BasicProgram.Read(BasicDialect.BusinessBasic, new Apple3BasicMemory(machine.Bus));
        typed.ToText().Should().Be("10 PRINT 6*7;\"!\"\n");

        Type(machine, "UNLOCK RENUMBER.DOC\rDELETE RENUMBER.DOC\rSAVE SIX\rCATALOG\r");
        RunUntil(machine, "BLOCKS FREE", seconds: 30);
        Screen(machine).Should().Contain(" SIX ");
    }

    /// <summary>
    ///  The variables a program sets read back from banked memory: each kind, an array element, and a string set
    ///  from outside, which BASIC then prints.
    /// </summary>
    [TestMethod]
    public void BusinessBasicVariablesReadAndWrite()
    {
        Apple3Machine machine = Boot(BusinessBasic);
        RunUntil(machine, "TOTAL BLOCKS", seconds: 90);
        machine.Run(TimeSpan.FromSeconds(2));
        Type(machine, "HOME\r10 A=1.5:B%=-7:C&=1234567890123:N$=\"HELLO\":DIM X(2,3):X(1,2)=9\rRUN\r");
        RunUntil(machine, ")RUN", seconds: 10);
        machine.Run(TimeSpan.FromSeconds(1));

        BasicVariables variables = new(BasicDialect.BusinessBasic, new Apple3BasicMemory(machine.Bus));
        variables.Simple().Select(variable => variable.Name).Should().Equal("A", "B%", "C&", "N$");
        BasicValue Read(string name)
        {
            BasicVariable variable = variables.Find(name) ?? throw new AssertFailedException($"{name} is missing");
            return variables.Read(variable.Kind, variable.ValueAddress);
        }

        Read("A").Number.Should().Be(1.5);
        Read("B%").Number.Should().Be(-7);
        Read("C&").Long.Should().Be(1234567890123);
        Read("N$").Text.Should().Equal("HELLO"u8.ToArray());

        BasicArray array = variables.FindArray("X").Should().NotBeNull().And.Subject.As<BasicArray>();
        array.Dimensions.Should().Equal(3, 4);
        variables.Read(array.Kind, array.ElementAddress([1, 2])).Number.Should().Be(9);

        // Expressions read the variables, with long integers exact, and numbers format as BASIC prints them.
        BasicEvaluator evaluator = new(BasicDialect.BusinessBasic, new Apple3BasicMemory(machine.Bus));
        string Evaluate(string expression) => evaluator.Format(evaluator.Evaluate(expression));
        Evaluate("A*2+B%").Should().Be("-4");
        Evaluate("C&+1").Should().Be("1234567890124");
        Evaluate("C& DIV 1000").Should().Be("1234567890");
        Evaluate("X(1,2)*2").Should().Be("18");
        Evaluate("N$+\"!\"").Should().Be("\"HELLO!\"");
        Evaluate("LEN(N$)=5 AND NOT A=0").Should().Be("1", "NOT takes one value: (NOT A)=0");
        Evaluate("MID$(N$,2,3)").Should().Be("\"ELL\"");
        Evaluate("UNSET").Should().Be("0");
        Action mixed = () => evaluator.Evaluate("C&+0.5");
        mixed.Should().Throw<FormatException>().WithMessage("?TYPE MISMATCH*");
        Type(machine, "PRINT 1/3;\"/\";2^31;\"/\"\r");
        RunUntil(machine, "/", seconds: 10);
        machine.Run(TimeSpan.FromSeconds(1));
        string printed = Screen(machine).Split('\n').Last(row => row.Contains('/', StringComparison.Ordinal)).Trim();
        printed.Should().Be($"{Evaluate("1/3")}/{Evaluate("2^31")}/");

        // A string set from outside goes into string space, where BASIC finds it.
        BasicVariable n = variables.Find("N$") ?? throw new AssertFailedException("N$ is missing");
        variables.Write(n.Kind, n.ValueAddress, BasicValue.Of("CHANGED"u8.ToArray()));
        Type(machine, "PRINT N$;LEN(N$)\r");
        RunUntil(machine, "CHANGED7", seconds: 10);
    }

    private static Apple3Machine Boot(string disk)
    {
        string path = Path.Join(Disks, disk);
        if (!File.Exists(path)) { Assert.Inconclusive($"Set RETROCORE_APPLE3_DISKS to a folder with {disk}."); }
        Apple3Machine machine = Apple3MachineTests.Machine();

        // A converted image is read-only; a writable copy takes the tests' writes.
        WozDisk media = SectorDiskConverter.Convert(File.ReadAllBytes(path), proDosOrder: false);
        machine.Drives[0].Insert(WozDisk.Load(media.Export(), writable: true), disk, "DSK");
        return machine;
    }

    private static void Type(Apple3Machine machine, string keys)
    {
        foreach (char key in keys) { machine.Bus.QueueKey((byte)key); }
    }

    private static string Screen(Apple3Machine machine) => string.Join('\n', machine.ReadTextScreen());

    private static void RunUntil(Apple3Machine machine, string text, int seconds)
    {
        for (int tenth = 0; tenth < seconds * 10; tenth++)
        {
            if (Screen(machine).Contains(text, StringComparison.Ordinal)) { return; }
            machine.Run(TimeSpan.FromSeconds(0.1));
        }

        Screen(machine).Should().Contain(text);
    }
}
