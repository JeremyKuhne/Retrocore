// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Debug.Project;
using Retrocore.Machines.Devices;
using Retrocore.Media;

namespace Retrocore.Debug;

internal sealed partial class DebugSession
{
    // The longest a project's image may take to boot and start its program, in the machine's own seconds: a PET's
    // tape of the largest program its RAM holds plays for a few minutes.
    private const int BootImageSeconds = 600;

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

        IDevice drive = ImageDrive(target);
        MediaActions.KeepReplaced(drive, $"the build's {build.Media.ImageKind} took its place");
        string label = $"{target.Project.Name}/{target.Name}: {Path.GetFileName(image)}, as built";
        switch (Target)
        {
            case Apple2DebugTarget apple2:
                apple2.InsertDisk(File.ReadAllBytes(image), label);
                break;
            default:
                throw new ProjectException($"{target.Project.File}: target {target.Name}: {target.Machine.Id} cannot boot the '{target.Environment}' environment's image yet.");
        }

        RunToEntry(build);
    }

    // The drive a target's image goes in: the first drive of the machine's first disk controller.
    private IDevice ImageDrive(ProjectTarget target) =>
        Target.Devices.FirstOrDefault(device => device.Kind == DeviceKind.FloppyDrive && device is IMediumSlot)
            ?? throw new ProjectException($"{target.Project.File}: target {target.Name}: {target.Machine.Id} has no disk drive for the '{target.Environment}' environment's disk.");

    // Runs the machine from power-on until an instruction starts at the program's entry with its bytes in memory.
    private void RunToEntry(TargetBuild build)
    {
        (int start, byte[] bytes) = ProjectBuild.Image(build);
        ForgetBoundaries();
        long limit = (long)BootImageSeconds * Target.ClockHertz;
        for (long cycle = 0; ; cycle++)
        {
            if (Target.IsInstructionBoundary && Target.ProgramCounter == build.Entry && Loaded(start, bytes)) { break; }
            if (cycle == limit)
            {
                ProjectTarget target = build.Target;
                throw new ProjectException(
                    $"{target.Project.File}: target {target.Name}: booted from its {build.Media.ImageKind}, the machine did not start the program at its entry, ${build.Entry:X4}, within {BootImageSeconds} seconds.");
            }

            Target.StepCycle();
        }

        Target.CallStack.Reset();
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
