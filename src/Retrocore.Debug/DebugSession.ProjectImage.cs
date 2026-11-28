// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Debug.Project;
using Retrocore.Media;
using Retrocore.Machines.Commodore;
using Retrocore.Media.Acorn;
using Retrocore.Media.Commodore;
using Retrocore.Media.Floppy;

namespace Retrocore.Debug;

internal sealed partial class DebugSession
{
    /// <summary>
    ///  Puts a project target's image in its drive and boots the machine from it, as a user would, until its
    ///  program's bytes are in memory and the CPU is at its entry.
    /// </summary>
    /// <remarks>
    ///  <para>
    ///   The image is built fresh by the launch, so it goes in after the saved machine's media and the recovery
    ///   journal's disks: the program the launch debugs is the one it built. A changed disk it takes the place of is
    ///   kept, as one the machine ejects is, so its changes can still be saved. The image is in memory, from no file,
    ///   so nothing the run writes to it reaches the build's output.
    ///  </para>
    ///  <para>
    ///   The machine runs with nothing tracked, one cycle at a time, until an instruction starts at the entry with the
    ///   program's bytes all in place, so the launch stops there, or the program starts there, as a <c>bare</c> one
    ///   does.
    ///  </para>
    /// </remarks>
    /// <param name="build">The build, whose environment boots an image.</param>
    /// <exception cref="ProjectException">
    ///  The machine has no drive for the image, or does not reach the program's entry with its bytes loaded.
    /// </exception>
    private void BootImage(TargetBuild build)
    {
        ProjectTarget target = build.Target;
        string image = build.Media.Image ?? throw new ProjectException(
            $"{target.Project.File}: target {target.Name}: the '{target.Environment}' environment boots its image, so its image cannot be false to launch it.");

        string label = $"{target.Project.Name}/{target.Name}: {Path.GetFileName(image)}, as built";
        byte[] bytes = File.ReadAllBytes(image);
        switch (Target)
        {
            case Apple2DebugTarget apple2:
                // Slot 6's drive 1, which the Disk II's firmware boots; the dos33 and prodos launches fit the Disk II. The image is
                // converted to a disk before the one there is kept, so an image that is not a disk leaves the drive and
                // the kept disks as they were.
                // A prodos disk is in ProDOS's block order, a dos33 disk in DOS's.
                bool proDos = target.Environment == "prodos";
                WozDisk disk = SectorDiskConverter.Convert(bytes, proDosOrder: proDos);
                MediaActions.KeepReplaced(apple2.BootDrive, $"the build's {build.Media.ImageKind} took its place");
                apple2.BootDrive.Insert(disk, label, proDos ? "PO" : "DSK");
                break;
            case BbcDebugTarget bbc:
                // Drive 0, which SHIFT-BREAK boots.
                FloppyDisk floppy = AcornDfsDisk.Read(bytes).ToDisk();
                MediaActions.KeepReplaced(bbc.BootDrive, $"the build's {build.Media.ImageKind} took its place");
                bbc.BootDrive.Insert(floppy, label, "SSD");
                break;
            case Apple3DebugTarget apple3:
                // The built-in drive, .D1, which the boot ROM boots.
                WozDisk sos = SectorDiskConverter.Convert(bytes, proDosOrder: false);
                MediaActions.KeepReplaced(apple3.BootDrive, $"the build's {build.Media.ImageKind} took its place");
                apple3.BootDrive.Insert(sos, label, "DSK");
                break;
            case PetDebugTarget pet:
                BootPet(build, pet, bytes, label);
                return;
            case Trs80DebugTarget model1:
                BootLevel2(build, model1.BootDeck, model3: false, bytes, label);
                return;
            case Trs80Model3DebugTarget { BootDeck: { } deck }:
                BootLevel2(build, deck, model3: true, bytes, label);
                return;
            default:
                throw new ProjectException($"{target.Project.File}: target {target.Name}: {target.Machine.Id} cannot boot the '{target.Environment}' environment's image yet.");
        }

        RunToEntry(build);
    }

    // Boots a PET from a basic target's tape, in cassette 1 with PLAY down, or its disk, in unit 8: at BASIC's prompt
    // the launch types LOAD, or LOAD"<NAME>",8, then RUN once the program is in memory and the tape or the drive has
    // stopped, so the keys are not typed while the load has the keyboard's interrupt.
    private void BootPet(TargetBuild build, PetDebugTarget pet, byte[] bytes, string label)
    {
        ProjectTarget target = build.Target;
        string name = BasicEnvironment.ProgramName(target);
        Machines.Devices.IDevice drive;
        string load;
        if (target.ImageBoot == "disk")
        {
            CommodoreDisk disk = CbmDosDisk.FromD64(bytes).ToDisk();
            CommodoreFloppyDrive floppy = pet.BootDiskDrive;
            MediaActions.KeepReplaced(floppy, $"the build's {build.Media.ImageKind} took its place");
            floppy.Insert(disk, label, "D64");
            drive = floppy;
            load = $"LOAD\"{name}\",8\r";
        }
        else
        {
            (CommodoreTape tape, _) = CommodoreTapeCodec.Load(bytes);
            CommodoreDatasette deck = pet.BootDeck;
            MediaActions.KeepReplaced(deck, $"the build's {build.Media.ImageKind} took its place");
            deck.Insert(tape, label, "TAP");
            deck.Play();
            drive = deck;
            load = "LOAD\r";
        }

        (int start, byte[] program) = ProjectBuild.Image(build);
        ForgetBoundaries();
        long limit = (long)(target.Built?.BootSeconds ?? 0) * Target.ClockHertz;
        long used = 0;
        RunUntil(build, () => pet.ShowsReady, "BASIC's READY prompt", limit, ref used);
        foreach (char key in load) { pet.Key(key); }
        RunUntil(build, () => drive.Activity == Machines.Devices.DeviceActivity.Idle && Loaded(start, program), "the program loaded", limit, ref used);
        foreach (char key in "RUN\r") { pet.Key(key); }
        RunToEntry(build, limit - used);
    }

    // Boots a TRS-80 from a level2 target's SYSTEM tape in its cassette recorder, as a user would: the Model III's Cass?
    // answered L, for the tape's 500 baud, MEMORY SIZE? (or MEM SIZE?) with Return, SYSTEM at BASIC's READY, the tape's name at the *?
    // prompt, and once the program is in memory and the prompt is back, a bare /, which jumps to the tape's entry.
    private void BootLevel2(TargetBuild build, Machines.Trs80.Trs80CassetteDrive deck, bool model3, byte[] bytes, string label)
    {
        ProjectTarget target = build.Target;
        MediaActions.KeepReplaced(deck, $"the build's {build.Media.ImageKind} took its place");
        deck.Play(new Media.Trs80.CassetteImage(bytes), label);

        (int start, byte[] program) = ProjectBuild.Image(build);
        ForgetBoundaries();
        long limit = (long)(target.Built?.BootSeconds ?? 0) * Target.ClockHertz;
        long used = 0;
        void Type(string keys)
        {
            foreach (char key in keys) { Target.Key(key); }
        }

        if (model3)
        {
            RunUntil(build, () => Trs80ScreenShows("Cass?"), "the Model III's Cass? question", limit, ref used);
            Type("L");
        }

        // Level II 1.2 asks MEMORY SIZE?, 1.3 MEM SIZE?, and the Model III Memory Size?.
        RunUntil(build, () => Trs80ScreenShows(model3 ? "Size?" : "SIZE?"), "the MEMORY SIZE? question", limit, ref used);
        Type("\r");
        RunUntil(build, () => Trs80ScreenShows("READY"), "BASIC's READY prompt", limit, ref used);
        Type("SYSTEM\r");
        RunUntil(build, () => Trs80ScreenCount("*?") == 1, "SYSTEM's *? prompt", limit, ref used);
        Type($"{Level2Environment.ProgramName(target)}\r");
        RunUntil(
            build,
            () => Loaded(start, program) && deck.Activity == Machines.Devices.DeviceActivity.Idle && Trs80ScreenCount("*?") == 2,
            "the program loaded and SYSTEM's *? prompt again",
            limit,
            ref used);

        Type("/\r");
        RunToEntry(build, limit - used);
    }

    // Whether the TRS-80's screen, 64 columns by 16 rows from $3C00, shows text.
    private bool Trs80ScreenShows(string text) => Trs80ScreenCount(text) != 0;

    // How many times the TRS-80's screen shows text. Each byte is a character in its low 7 bits; the Model I's video
    // RAM has no bit 6 without the lowercase modification, so a byte below $20 is the capital or symbol 64 above it.
    private int Trs80ScreenCount(string text)
    {
        const int Video = 0x3C00;
        const int Size = 64 * 16;
        char[] screen = new char[Size];
        for (int index = 0; index < Size; index++)
        {
            int value = Target.Peek((ushort)(Video + index)) & 0x7F;
            screen[index] = (char)(value < 0x20 ? value + 0x40 : value);
        }

        int count = 0;
        for (int at = new string(screen).IndexOf(text, StringComparison.Ordinal); at >= 0; at = new string(screen).IndexOf(text, at + 1, StringComparison.Ordinal))
        {
            count++;
        }

        return count;
    }

    // Runs the machine one cycle at a time until a condition holds at an instruction's start, counting the cycles it
    // takes against the boot's limit. The condition, which may read the screen or the program's bytes, is tested every
    // 4,096 cycles, about 4 ms of a 1 MHz machine's time, not at every instruction.
    private void RunUntil(TargetBuild build, Func<bool> done, string what, long limit, ref long used)
    {
        const int Interval = 4096;
        for (long tested = used - Interval; ; used++)
        {
            if (used - tested >= Interval && Target.IsInstructionBoundary)
            {
                tested = used;
                if (done()) { return; }
            }

            if (used >= limit)
            {
                ProjectTarget target = build.Target;
                throw new ProjectException(
                    $"{target.Project.File}: target {target.Name}: booted from its {build.Media.ImageKind}, the machine did not reach {what} within {target.Built?.BootSeconds} seconds.");
            }

            Target.StepCycle();
        }
    }

    // Runs the machine until an instruction starts at the program's entry with its bytes in memory: from power-on, for
    // as long as the environment takes to boot, or, after a boot's earlier steps, for the cycles they left it.
    private void RunToEntry(TargetBuild build, long? cycles = null)
    {
        (int start, byte[] bytes) = ProjectBuild.Image(build);
        if (cycles is null) { ForgetBoundaries(); }
        long limit = cycles ?? ((long)(build.Target.Built?.BootSeconds ?? 0) * Target.ClockHertz);
        long seconds = (limit + Target.ClockHertz - 1) / Target.ClockHertz;
        for (long cycle = 0; ; cycle++)
        {
            if (Target.IsInstructionBoundary && Target.ProgramCounter == build.Entry && Loaded(start, bytes)) { break; }
            if (cycle == limit)
            {
                ProjectTarget target = build.Target;
                throw new ProjectException(
                    $"{target.Project.File}: target {target.Name}: booted from its {build.Media.ImageKind}, the machine did not start the program at its entry, ${build.Entry:X4}, within the {seconds} seconds its boot had left.");
            }

            Target.StepCycle();
        }

        Target.CallStack.Reset();
    }

    // The memory areas a booted program's bytes are in as the CPU reads them, each once, in the segments' order.
    private List<Enum> ProgramAreas(TargetBuild build)
    {
        List<Enum> areas = [];
        foreach ((int address, ReadOnlyMemory<byte> bytes) in build.Segments)
        {
            for (int at = address; at < address + bytes.Length; at += 0x100)
            {
                Enum area = Target.ReadArea((ushort)at);
                if (!areas.Contains(area)) { areas.Add(area); }
            }

            Enum last = Target.ReadArea((ushort)(address + bytes.Length - 1));
            if (!areas.Contains(last)) { areas.Add(last); }
        }

        return areas;
    }

    // Whether memory holds a program's bytes from its start.
    private bool Loaded(int start, byte[] bytes)
    {
        for (int index = 0; index < bytes.Length; index++)
        {
            if (Target.Peek((ushort)(start + index)) != bytes[index]) { return false; }
        }

        return true;
    }
}
