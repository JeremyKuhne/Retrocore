// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace AppleSharp;

/// <summary>
///  Front-panel operations, in button order.
/// </summary>
internal enum Command : byte
{
    /// <summary>
    ///  Choose external firmware.
    /// </summary>
    Roms,

    /// <summary>
    ///  Mount a raw block image.
    /// </summary>
    Mount,

    /// <summary>
    ///  Eject the current image and reboot.
    /// </summary>
    Eject,

    /// <summary>
    ///  Pause or resume CPU clocks.
    /// </summary>
    Pause,

    /// <summary>
    ///  Reset without clearing RAM.
    /// </summary>
    Reset,

    /// <summary>
    ///  Cold-boot the current configuration.
    /// </summary>
    Boot,

    /// <summary>
    ///  Switch between existing IIe models.
    /// </summary>
    Model,

    /// <summary>
    ///  Change persistent mount write permission.
    /// </summary>
    Writable,

    /// <summary>
    ///  Toggle fullscreen presentation.
    /// </summary>
    Fullscreen,

    /// <summary>
    ///  Choose a caller-supplied P5 boot ROM.
    /// </summary>
    DiskBootRom,

    /// <summary>
    ///  Choose a caller-supplied P6 sequencer PROM.
    /// </summary>
    DiskSequencerRom,

    /// <summary>
    ///  Mount native drive-two media.
    /// </summary>
    Floppy2,

    /// <summary>
    ///  Mute or resume SDL speaker/Mockingboard output.
    /// </summary>
    Mute
}
