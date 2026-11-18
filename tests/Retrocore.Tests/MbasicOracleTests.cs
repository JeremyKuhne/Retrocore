// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using System.Text;
using Retrocore.Basic;
using Retrocore.Machines.Kaypro;

namespace Retrocore.Tests;

/// <summary>
///  MBASIC's own CRUNCH as the oracle for the dialect's: the real interpreter, on an emulated Kaypro II, loads the
///  ASCII programs on its disk and crunches lines typed at it, and the dialect must store each line as it did and
///  list it back as the text it came from.
/// </summary>
/// <remarks>
///  <para>
///   The disks are in <c>RETROCORE_KAYPRO</c> or <c>%USERPROFILE%\Retrocore\kaypro</c>; the tests are inconclusive
///   without them.
///  </para>
/// </remarks>
[TestClass]
public sealed class MbasicOracleTests
{
    private const int RecordSize = 128;
    private const int TrackBytes = 10 * 512;
    private const int BlockSize = 1024;

    /// <summary>
    ///  GO with spaces before TO or SUB crunches as MBASIC 5.21's CRUNCH does, as recorded from MBASIC itself: GO
    ///  SUB with one space and GO TO with two or more are GOSUB, the character after TO or UB is skipped, and GO TO
    ///  with one space is GOTO. The lines list as text that crunches back to the same bytes.
    /// </summary>
    /// <param name="line">The line, after its number.</param>
    /// <param name="mbasic">What MBASIC stores, in hex.</param>
    /// <param name="listed">What the dialect lists.</param>
    [TestMethod]
    [DataRow("GO TO 100", "89200E6400", "GOTO 100")]
    [DataRow("GO  TO 100", "8D0E6400", "GO SUB 100")]
    [DataRow("GO SUB 100", "8D0E6400", "GO SUB 100")]
    [DataRow("GO  SUB 100", "474F202053554220313030", "GO  SUB 100")]
    [DataRow("GO  TO100", "8D0E0000", "GO SUB 0")]
    [DataRow("GO  TO  100", "8D200E6400", "GOSUB 100")]
    public void GoWithSpacesCrunchesAsMbasicDoes(string line, string mbasic, string listed)
    {
        byte[] crunched = BasicDialect.Mbasic.Tokenize(line);
        Convert.ToHexString(crunched).Should().Be(mbasic);
        BasicDialect.Mbasic.Detokenize(crunched).Should().Be(listed);
    }

    /// <summary>
    ///  Lines typed at MBASIC: each crunches as the dialect crunches it, and LIST shows what the dialect lists.
    /// </summary>
    [TestMethod]
    public void TypedLinesCrunchAndListAsMbasicDoes()
    {
        string[] lines =
        [
            "PRINT \"HELLO\";A$,B",
            "FOR I=1 TO 10 STEP 2:NEXT I",
            "IF A>5 THEN 100 ELSE 200",
            "GOTO 1000:GOSUB 20",
            "ON X GOTO 10,20,30",
            "A=3.14159:B=1E10:C#=1.5#+12345678901#+1D3:D!=2:E%=3",
            "X=&HFF+&O17+&777",
            "DATA 1,2,\"A:B\",HELLO WORLD:REM AND",
            "? \"QUESTION\":REM a remark",
            "Z=1 ' a comment",
            "a=b+c*d/e^f\\g MOD h",
            "PRINTA:FORX=1TO2",
            "X=FNA(1)+USR(2)+TAB(3)+SPC(4)",
            "Y=LEFT$(A$,1)+MID$(B$,2,3)+CHR$(65)+STRING$(3,42)",
            "Q=SIN(1)+COS(2)+SQR(3)+INT(4.5)+ABS(-6)",
            "WHILE A<10:A=A+1:WEND",
            "N=32767+32768+255+256+9+10+0",
            "M=0.001+.5+100000+1234567+12345678",
            "OPEN \"I\",#1,\"FILE.DAT\":CLOSE #1",
            "RESTORE 50:RESUME NEXT",
            "DEF FNA(X)=X*X",
            "PRINT USING \"##.##\";A",
            "DIM A(10),B$(5,5)",
            "X = 1 2 3",
            "LIST 10-20",
            "PRINT A.B,ITEM.COUNT",
            "GO TO 100",
            "GO  TO 100",
            "GO SUB 100",
            "GO  SUB 100",
            "go   to 100:GO TOTAL",
            "GO  TO100",
            "GO  TO  100",
            "IF A THEN B=1 ELSE B=2",
            "X=1 EQV 2:Y=1E2",
            "X=1.6%+2.5%-1.4%",
            "X=&O1 7+& 17+&H1F"
        ];

        KayproMachine machine = StartMbasic();
        BasicDialect dialect = BasicDialect.Mbasic;
        List<string> failures = [];
        foreach (string line in lines)
        {
            // MBASIC reads and drops what is typed while it works, as it looks for CONTROL-C, so each command waits
            // for the one before it.
            Command(machine, "NEW");
            Command(machine, "10 " + line);
            Command(machine, "LIST");
            byte[] stored = FirstLine(machine);
            byte[] crunched = dialect.Tokenize(line);
            if (!crunched.AsSpan().SequenceEqual(stored))
            {
                failures.Add($"{line}\n  MBASIC: {Convert.ToHexString(stored)}\n  ours:   {Convert.ToHexString(crunched)}");
                continue;
            }

            // The dialect lists what MBASIC's LIST shows, unless that would crunch to other bytes, as LIST writes
            // some singles with too few digits; then it lists what crunches back.
            string listed = dialect.Detokenize(stored);
            string[] screen = KayproTests.Screen(machine).Split('\n');
            int shown = Array.LastIndexOf(screen, "LIST") + 1;
            string theirs = shown > 0 && shown < screen.Length ? dialect.SplitLineNumber(screen[shown], out _) : "";
            bool theirsRoundTrips = dialect.Tokenize(theirs).AsSpan().SequenceEqual(stored);
            if (theirsRoundTrips ? listed != theirs : !dialect.Tokenize(listed).AsSpan().SequenceEqual(stored))
            {
                failures.Add($"{line}\n  listed as {listed}, but MBASIC's LIST shows {theirs}");
            }
        }

        failures.Should().BeEmpty();
    }

    /// <summary>
    ///  The ASCII programs on MBASIC's disk load as the dialect crunches each of their lines.
    /// </summary>
    /// <param name="file">The program's name on the disk.</param>
    [TestMethod]
    [DataRow("BIO.BAS")]
    [DataRow("CHASE.BAS")]
    [DataRow("WUMP.BAS")]
    [DataRow("TRADE.BAS")]
    [DataRow("STRTRK.BAS")]
    public void LoadedProgramsCrunchAsMbasicDoes(string file)
    {
        KayproMachine machine = StartMbasic();
        string text = Encoding.ASCII.GetString(ReadFile(Path.Join(KayproTests.External, "MBasic.img"), file));
        KayproTests.Type(machine, $"LOAD \"B:{file}\"\r");
        machine.Run(KayproTiming.ClockHertz * 2);
        KayproTests.RunUntil(machine, "Ok", seconds: 60);

        Dictionary<int, byte[]> stored = Program(machine);
        BasicDialect dialect = BasicDialect.Mbasic;
        List<string> failures = [];
        int checkedLines = 0;
        foreach (string raw in text.Split('\n'))
        {
            string line = raw.TrimEnd('\r', '\u001A', '\0');
            if (line.Length == 0) { continue; }
            string body = dialect.SplitLineNumber(line, out int number);
            if (number < 0 || !stored.TryGetValue(number, out byte[]? bytes)) { continue; }
            checkedLines++;
            byte[] crunched = dialect.Tokenize(body);
            if (!crunched.AsSpan().SequenceEqual(bytes))
            {
                failures.Add($"{line}\n  MBASIC: {Convert.ToHexString(bytes)}\n  ours:   {Convert.ToHexString(crunched)}");
            }
            else if (dialect.Detokenize(bytes) is var listed && !dialect.Tokenize(listed).AsSpan().SequenceEqual(bytes))
            {
                failures.Add($"{line}\n  lists as {listed}");
            }
        }

        checkedLines.Should().Be(stored.Count, "every stored line should be in the file");
        failures.Should().BeEmpty();
    }

    /// <summary>
    ///  After OPTION BASE 1, an array's elements start at 1: the variables see A(1) to A(3), and A(3) is the value
    ///  MBASIC stored there.
    /// </summary>
    [TestMethod]
    public void OptionBaseSetsTheLowestSubscript()
    {
        KayproMachine machine = StartMbasic();
        Command(machine, "OPTION BASE 1:DIM A(3):A(1)=5:A(3)=7");
        BasicVariables variables = new(BasicDialect.Mbasic, new DelegateBasicMemory(
            address => machine.Bus.PeekRam((ushort)address),
            (address, value) => machine.Bus.PokeRam((ushort)address, value)));

        BasicArray array = variables.Arrays().Single();
        array.LowerBound.Should().Be(1);
        array.Count.Should().Be(3);
        variables.Read(array.Kind, array.ElementAddress([1])).Number.Should().Be(5);
        variables.Read(array.Kind, array.ElementAddress([3])).Number.Should().Be(7);
    }

    private static KayproMachine StartMbasic()
    {
        KayproMachine machine = KayproTests.Boot("cpm22-rom149.img", "MBasic.img");
        KayproTests.RunUntil(machine, "A>", seconds: 10);
        KayproTests.Type(machine, "B:MBASIC\r");
        KayproTests.RunUntil(machine, "Ok", seconds: 20);
        return machine;
    }

    // Types a command and runs until MBASIC has taken it and had time to carry it out.
    private static void Command(KayproMachine machine, string text)
    {
        KayproTests.Type(machine, text + "\r");
        while (machine.Bus.Keyboard.IsTyping) { machine.Run(KayproTiming.ClockHertz / 100); }
        machine.Run(KayproTiming.ClockHertz / 2);
    }

    // The first line's tokens, between its number and its zero.
    private static byte[] FirstLine(KayproMachine machine) =>
        Program(machine).OrderBy(pair => pair.Key).Select(pair => pair.Value).FirstOrDefault() ?? [];

    // The program in memory, each line's tokens by its number.
    private static Dictionary<int, byte[]> Program(KayproMachine machine)
    {
        Dictionary<int, byte[]> lines = [];
        int address = Word(machine, MbasicMemory.TXTTAB);
        while (Word(machine, address) != 0)
        {
            int next = Word(machine, address);
            int number = Word(machine, address + 2);
            int end = address + 4;
            while (machine.Bus.PeekRam((ushort)end) != 0) { end = Skip(machine, end); }
            lines[number] = [.. Enumerable.Range(address + 4, end - address - 4).Select(at => machine.Bus.PeekRam((ushort)at))];
            address = next;
        }

        return lines;
    }

    // The next byte after one in a crunched line, stepping over a constant's bytes, which may be zero.
    private static int Skip(KayproMachine machine, int at) => machine.Bus.PeekRam((ushort)at) switch
    {
        0x0F => at + 2,
        0x0B or 0x0C or 0x0D or 0x0E or 0x1C => at + 3,
        0x1D => at + 5,
        0x1F => at + 9,
        _ => at + 1
    };

    private static int Word(KayproMachine machine, int address) =>
        machine.Bus.PeekRam((ushort)address) | (machine.Bus.PeekRam((ushort)(address + 1)) << 8);

    /// <summary>
    ///  Reads a file on a Kaypro II disk: one system track, 1K blocks and 64 directory entries.
    /// </summary>
    /// <param name="image">The disk image's path.</param>
    /// <param name="name">The file's name, such as <c>MBASIC.COM</c>.</param>
    /// <returns>The file's bytes, in whole 128-byte records.</returns>
    internal static byte[] ReadFile(string image, string name)
    {
        if (!File.Exists(image))
        {
            Assert.Inconclusive($"Set RETROCORE_KAYPRO to the Kaypro disks ({Path.GetFileName(image)}).");
        }

        byte[] disk = File.ReadAllBytes(image);
        List<(int Extent, int Records, byte[] Blocks)> extents = [];
        for (int entry = 0; entry < 64; entry++)
        {
            ReadOnlySpan<byte> directory = disk.AsSpan(TrackBytes + (entry * 32), 32);
            if (directory[0] == 0xE5) { continue; }
            string stem = Encoding.ASCII.GetString([.. directory[1..9].ToArray().Select(value => (byte)(value & 0x7F))]).TrimEnd();
            string type = Encoding.ASCII.GetString([.. directory[9..12].ToArray().Select(value => (byte)(value & 0x7F))]).TrimEnd();
            string file = $"{stem}.{type}";
            if (file != name) { continue; }
            extents.Add((directory[12], directory[15], [.. directory[16..32].ToArray().Where(block => block != 0)]));
        }

        List<byte> bytes = [];
        foreach ((int _, int records, byte[] blocks) in extents.OrderBy(extent => extent.Extent))
        {
            List<byte> extent = [];
            foreach (byte block in blocks)
            {
                extent.AddRange(disk.AsSpan(TrackBytes + (block * BlockSize), BlockSize).ToArray());
            }

            bytes.AddRange(extent.Take(records * RecordSize));
        }

        return [.. bytes];
    }
}
