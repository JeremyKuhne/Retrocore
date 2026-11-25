// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using System.Text;

namespace Retrocore.Tests;

/// <summary>
///  Runs the BASIC 4 disk statements' helpers (Basic.md, F) in the shipped PET BASIC 4 build and checks what their
///  documentation says they take, return and keep. PetBasic4ExtensionTests runs the parser, <c>RECORD</c> and the
///  filenames.
/// </summary>
[TestClass]
public sealed class BasicDiskRoutineTests
{
    // Where a test puts the filenames and the disk-status buffer, clear of the workspace.
    private const int FirstName = 0x0700;
    private const int SecondName = 0x0720;
    private const int StatusBuffer = 0x0740;

    // The values a routine that keeps a register must hand back.
    private const int KeptX = 0x5A;
    private const int KeptY = 0x6B;

    // The bits of ParsedParameters, as the parser sets them.
    private const int FirstNameBit = 0x01;
    private const int SecondNameBit = 0x02;
    private const int FileBit = 0x04;
    private const int UnitBit = 0x08;
    private const int FirstDriveBit = 0x10;
    private const int SecondDriveBit = 0x20;
    private const int RecordBit = 0x40;
    private const int ReplaceBit = 0x80;

    /// <summary>
    ///  Each parameter check rejects the parameters its statements do not take, and the missing names or file number
    ///  they need, with SYNTAX ERROR; otherwise it returns A as documented: <c>ParsedParameters</c>, or 0 for
    ///  <c>CheckDriveOnly</c>.
    /// </summary>
    /// <param name="check">The check.</param>
    /// <param name="flags">The parsed parameters.</param>
    /// <param name="accepted">Whether the check returns.</param>
    [TestMethod]
    [DataRow("Disk::CheckSingleName", FirstNameBit | FirstDriveBit | UnitBit, true)]
    [DataRow("Disk::CheckSingleName", FirstNameBit | SecondNameBit, false)]
    [DataRow("Disk::CheckSingleName", FirstNameBit | ReplaceBit, false)]
    [DataRow("Disk::CheckSingleName", FirstDriveBit, false)]
    [DataRow("Disk::RequireFirstName", FirstNameBit | RecordBit, true)]
    [DataRow("Disk::RequireFirstName", SecondNameBit, false)]
    [DataRow("Disk::CheckDriveOnly", FirstDriveBit | UnitBit, true)]
    [DataRow("Disk::CheckDriveOnly", FirstDriveBit | FirstNameBit, false)]
    [DataRow("Disk::CheckDriveOnly", SecondDriveBit, false)]
    [DataRow("Disk::CheckTwoNames", FirstNameBit | SecondNameBit | FirstDriveBit | SecondDriveBit, true)]
    [DataRow("Disk::CheckTwoNames", FirstNameBit | SecondNameBit | FileBit, false)]
    [DataRow("Disk::CheckTwoNames", FirstNameBit, false)]
    [DataRow("Disk::RequireTwoNames", FirstNameBit | SecondNameBit | ReplaceBit, true)]
    [DataRow("Disk::RequireTwoNames", SecondNameBit, false)]
    [DataRow("Disk::RequireNameAndFile", FirstNameBit | FileBit | RecordBit, true)]
    [DataRow("Disk::RequireNameAndFile", FirstNameBit, false)]
    public void ChecksRejectWithSyntaxErrorOrReturnTheParameters(string check, int flags, bool accepted)
    {
        BasicMathMachine machine = new(apple: false);
        machine.Memory[machine.Address("ParsedParameters")] = (byte)flags;
        int syntaxError = machine.Address("SyntaxError");

        int reached = machine.CallUntil(check, [syntaxError], a: flags);

        (reached != syntaxError).Should().Be(accepted, $"{check} with ${flags:X2}");
        if (accepted)
        {
            machine.Cpu.Registers.Accumulator.Should().Be(check == "Disk::CheckDriveOnly" ? (byte)0 : (byte)flags);
        }
    }

    /// <summary>
    ///  <c>Disk::BuildCommand</c> expands a template into <c>DiskCommandBuffer</c>: the drives as digits, the second
    ///  name before the first, an empty name with its separator removed, the file's type and record length, and the
    ///  disk ID; then it makes the command the kernal's filename.
    /// </summary>
    /// <param name="template">The template's offset constant.</param>
    /// <param name="length">The template's length constant, or a length less two for a shorter form.</param>
    /// <param name="firstName">The first filename.</param>
    /// <param name="secondName">The second filename.</param>
    /// <param name="recordLength">The record length, 0 for none.</param>
    /// <param name="expected">The command.</param>
    [TestMethod]
    [DataRow("TEMPLATE_COPY", "TEMPLATE_COPY_LENGTH", "SRC", "DST", 0, "C1:DST=0:SRC")]
    [DataRow("TEMPLATE_COPY", "TEMPLATE_COPY_LENGTH", "", "", 0, "C1=0")]
    [DataRow("TEMPLATE_CONCAT", "TEMPLATE_CONCAT_LENGTH", "A", "B", 0, "C1:B=1:B,0:A")]
    [DataRow("TEMPLATE_RENAME", "TEMPLATE_RENAME_LENGTH", "OLD", "NEW", 0, "R0:NEW=0:OLD")]
    [DataRow("TEMPLATE_OPEN", "TEMPLATE_OPEN_LENGTH", "SEQ", "", 0, "0:SEQ,W,S")]
    [DataRow("TEMPLATE_OPEN", "TEMPLATE_OPEN_LENGTH", "REL", "", 0x40, "0:REL,L,@")]
    [DataRow("TEMPLATE_HEADER", "TEMPLATE_HEADER_LENGTH", "DISK", "", 0, "N0:DISK,ID")]
    public void BuildCommandExpandsTheTemplate(
        string template,
        string length,
        string firstName,
        string secondName,
        int recordLength,
        string expected)
    {
        BasicMathMachine machine = new(apple: false);
        Encoding.ASCII.GetBytes(firstName).CopyTo(machine.Memory, FirstName);
        Encoding.ASCII.GetBytes(secondName).CopyTo(machine.Memory, SecondName);
        machine.Memory[machine.Address("FilenameLength")] = (byte)firstName.Length;
        SetPointer(machine, "FilenamePointer", FirstName);
        machine.Memory[machine.Address("SecondFilenameLength")] = (byte)secondName.Length;
        SetPointer(machine, "SecondFilenamePointer", SecondName);
        machine.Memory[machine.Address("FirstDrive")] = 0;
        machine.Memory[machine.Address("SecondDrive")] = 1;
        machine.Memory[machine.Address("RecordLength")] = (byte)recordLength;
        Encoding.ASCII.GetBytes("ID").CopyTo(machine.Memory, machine.Address("DiskId"));
        machine.Memory[machine.Address("DiskStatusDescriptor")] = 0;

        machine.Call("Disk::BuildCommand", a: machine.Address(length), y: machine.Address(template));

        int buffer = machine.Address("DiskCommandBuffer");
        machine.Memory.AsSpan(buffer, expected.Length).ToArray().Should().Equal(Encoding.ASCII.GetBytes(expected));
        machine.Memory[machine.Address("FilenameLength")].Should().Be((byte)expected.Length);
        Pointer(machine, "FilenamePointer").Should().Be(buffer);
        machine.Cpu.Registers.X.Should().Be((byte)expected.Length);
    }

    /// <summary>
    ///  <c>Disk::AppendSecondName</c> appends the second filename at X, or removes the separator before an empty
    ///  one, and returns A = Y = the template's offset with carry set, keeping Y.
    /// </summary>
    /// <param name="name">The second filename.</param>
    [TestMethod]
    [DataRow("AB")]
    [DataRow("")]
    public void AppendSecondNameKeepsY(string name)
    {
        BasicMathMachine machine = new(apple: false);
        Encoding.ASCII.GetBytes(name).CopyTo(machine.Memory, SecondName);
        machine.Memory[machine.Address("SecondFilenameLength")] = (byte)name.Length;
        SetPointer(machine, "SecondFilenamePointer", SecondName);

        machine.Call("Disk::AppendSecondName", x: 3, y: KeptY);

        int buffer = machine.Address("DiskCommandBuffer");
        machine.Memory.AsSpan(buffer + 3, name.Length).ToArray().Should().Equal(Encoding.ASCII.GetBytes(name));
        machine.Cpu.Registers.X.Should().Be((byte)(name.Length == 0 ? 2 : 3 + name.Length));
        machine.Cpu.Registers.Y.Should().Be(KeptY);
        machine.Cpu.Registers.Accumulator.Should().Be(KeptY);
        machine.Cpu.Registers.Status.HasFlag(StatusRegister.Carry).Should().BeTrue();
    }

    /// <summary>
    ///  <c>Disk::AppendDiskId</c> appends the ID's two characters at X and returns A = X, keeping Y.
    /// </summary>
    [TestMethod]
    public void AppendDiskIdKeepsY()
    {
        BasicMathMachine machine = new(apple: false);
        Encoding.ASCII.GetBytes("XY").CopyTo(machine.Memory, machine.Address("DiskId"));

        machine.Call("Disk::AppendDiskId", x: 4, y: KeptY);

        int buffer = machine.Address("DiskCommandBuffer");
        machine.Memory.AsSpan(buffer + 4, 2).ToArray().Should().Equal("XY"u8.ToArray());
        machine.Cpu.Registers.X.Should().Be(6);
        machine.Cpu.Registers.Accumulator.Should().Be(6);
        machine.Cpu.Registers.Y.Should().Be(KeptY);
    }

    /// <summary>
    ///  <c>Disk::SetCommandName</c> makes the X bytes of <c>DiskCommandBuffer</c> the kernal's filename, keeping X
    ///  and Y.
    /// </summary>
    [TestMethod]
    public void SetCommandNameKeepsXAndY()
    {
        BasicMathMachine machine = new(apple: false);

        machine.Call("Disk::SetCommandName", x: KeptX, y: KeptY);

        machine.Memory[machine.Address("FilenameLength")].Should().Be(KeptX);
        Pointer(machine, "FilenamePointer").Should().Be(machine.Address("DiskCommandBuffer"));
        machine.Cpu.Registers.X.Should().Be(KeptX);
        machine.Cpu.Registers.Y.Should().Be(KeptY);
    }

    /// <summary>
    ///  <c>Disk::ChooseFileType</c> returns <c>L</c> with a record length, and otherwise <c>W</c>, leaving <c>S</c>
    ///  as the record length; zero is clear, and X and Y are kept.
    /// </summary>
    /// <param name="recordLength">The record length.</param>
    [TestMethod]
    [DataRow(0)]
    [DataRow(0x40)]
    public void ChooseFileTypeKeepsXAndY(int recordLength)
    {
        BasicMathMachine machine = new(apple: false);
        int length = machine.Address("RecordLength");
        machine.Memory[length] = (byte)recordLength;

        machine.Call("Disk::ChooseFileType", x: KeptX, y: KeptY);

        machine.Cpu.Registers.Accumulator.Should().Be(recordLength == 0 ? (byte)'W' : (byte)'L');
        machine.Memory[length].Should().Be(recordLength == 0 ? (byte)'S' : (byte)recordLength);
        machine.Cpu.Registers.Status.HasFlag(StatusRegister.Zero).Should().BeFalse();
        machine.Cpu.Registers.X.Should().Be(KeptX);
        machine.Cpu.Registers.Y.Should().Be(KeptY);
    }

    /// <summary>
    ///  <c>Disk::TestDirect</c> sets zero only while <c>TextPointer</c> is in the input buffer's page, keeping X and
    ///  Y.
    /// </summary>
    /// <param name="page">The text pointer's page.</param>
    [TestMethod]
    [DataRow(0x02)]
    [DataRow(0x04)]
    public void TestDirectKeepsXAndY(int page)
    {
        BasicMathMachine machine = new(apple: false);
        machine.Memory[machine.Address("TextPointer") + 1] = (byte)page;

        machine.Call("Disk::TestDirect", x: KeptX, y: KeptY);

        machine.Cpu.Registers.Status.HasFlag(StatusRegister.Zero).Should().Be(page == 0x02);
        machine.Cpu.Registers.X.Should().Be(KeptX);
        machine.Cpu.Registers.Y.Should().Be(KeptY);
    }

    /// <summary>
    ///  In a program, <c>Disk::Confirm</c> accepts at once, with carry clear.
    /// </summary>
    [TestMethod]
    public void ConfirmAcceptsInAProgram()
    {
        BasicMathMachine machine = new(apple: false);
        machine.Memory[machine.Address("TextPointer") + 1] = 0x04;

        machine.Call("Disk::Confirm", carry: true);

        machine.Cpu.Registers.Status.HasFlag(StatusRegister.Carry).Should().BeFalse();
    }

    /// <summary>
    ///  <c>Disk::StoreStatusLink</c> stores A in <c>IoStatus</c> and in the status buffer at Y, and steps Y down,
    ///  keeping A and X.
    /// </summary>
    [TestMethod]
    public void StoreStatusLinkKeepsAAndX()
    {
        BasicMathMachine machine = new(apple: false);
        SetPointer(machine, "DiskStatusDescriptor", StatusBuffer, offset: 1);
        const byte Value = 0x3C;

        machine.Call("Disk::StoreStatusLink", a: Value, x: KeptX, y: 41);

        machine.Memory[machine.Address("IoStatus")].Should().Be(Value);
        machine.Memory[StatusBuffer + 41].Should().Be(Value);
        machine.Cpu.Registers.Y.Should().Be(40);
        machine.Cpu.Registers.Accumulator.Should().Be(Value);
        machine.Cpu.Registers.X.Should().Be(KeptX);
    }

    /// <summary>
    ///  <c>ForgetDiskStatus</c> marks a status buffer as garbage, its back-link becoming its length and $FF, and
    ///  clears the status's length and <c>IoStatus</c>, returning A = Y and keeping X and Y; with no status, it marks
    ///  nothing.
    /// </summary>
    /// <param name="held">Whether a status is held.</param>
    [TestMethod]
    [DataRow(data: true)]
    [DataRow(data: false)]
    public void ForgetDiskStatusKeepsXAndY(bool held)
    {
        BasicMathMachine machine = new(apple: false);
        int descriptor = machine.Address("DiskStatusDescriptor");
        machine.Memory[descriptor] = held ? (byte)40 : (byte)0;
        SetPointer(machine, "DiskStatusDescriptor", StatusBuffer, offset: 1);
        machine.Memory[StatusBuffer + 40] = 0x0D;
        machine.Memory[StatusBuffer + 41] = 0x00;
        machine.Memory[machine.Address("IoStatus")] = 0x42;

        machine.Call("ForgetDiskStatus", a: 0x99, x: KeptX, y: KeptY);

        machine.Memory[descriptor].Should().Be(0);
        machine.Memory[machine.Address("IoStatus")].Should().Be(0);
        machine.Memory[StatusBuffer + 40].Should().Be(held ? (byte)40 : (byte)0x0D);
        machine.Memory[StatusBuffer + 41].Should().Be(held ? (byte)0xFF : (byte)0x00);
        machine.Cpu.Registers.Accumulator.Should().Be(KeptY);
        machine.Cpu.Registers.X.Should().Be(KeptX);
        machine.Cpu.Registers.Y.Should().Be(KeptY);
    }

    private static void SetPointer(BasicMathMachine machine, string name, int address, int offset = 0)
    {
        int at = machine.Address(name) + offset;
        machine.Memory[at] = (byte)address;
        machine.Memory[at + 1] = (byte)(address >> 8);
    }

    private static int Pointer(BasicMathMachine machine, string name)
    {
        int at = machine.Address(name);
        return machine.Memory[at] | (machine.Memory[at + 1] << 8);
    }
}
