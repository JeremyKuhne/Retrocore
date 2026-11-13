// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using System.Runtime.InteropServices;

namespace Retrocore.Machines.Trs80;

/// <summary>
///  The Model II family's video: an MC6845 showing 2K of video RAM as 80x24 (or 40x24) characters from a 2K
///  character generator of 8-pixel rows, with bit 7 of a code showing it inverse.
/// </summary>
/// <remarks>
///  <para>
///   Port <c>$FC</c> selects a 6845 register and <c>$FD</c> writes it. The picture follows the registers the
///   display uses: the characters shown per row (R1) and rows (R6), the scanlines per row (R9), the cursor's
///   scanlines and blink (R10, R11), the start address (R12, R13) and the cursor's address (R14, R15). Port
///   <c>$FF</c> bit 4 doubles each character's width for 40 columns, and bit 6 blanks the picture. Each vertical
///   sync toggles the real-time clock, which interrupts every other frame, 30 times a second.
///  </para>
/// </remarks>
public sealed class Trs80Model2Video : IVideoSource
{
    /// <summary>
    ///  The most scanlines a character row is drawn with.
    /// </summary>
    public const int MaximumLinesPerRow = 12;

    /// <summary>
    ///  The most character rows drawn.
    /// </summary>
    public const int MaximumRows = 24;

    private static readonly uint s_on = Rgba(0xF0, 0xF0, 0xF0);
    private static readonly uint s_off = Rgba(0x10, 0x10, 0x10);

    private readonly byte[] _ram = new byte[0x800];
    private readonly byte[] _scanned = new byte[0x800];
    private readonly byte[] _characterGenerator;
    private readonly byte[] _registers = new byte[18];
    private byte[] _scannedRegisters = new byte[18];
    private bool _scannedWide;
    private bool _scannedBlank;
    private int _register;

    /// <summary>
    ///  Creates the video, with the 6845 set up as the boot ROM sets it for 80x24.
    /// </summary>
    /// <param name="characterGenerator">The 2K character generator.</param>
    internal Trs80Model2Video(ReadOnlyMemory<byte> characterGenerator)
    {
        _characterGenerator = characterGenerator.ToArray();
        _registers[1] = 80;
        _registers[6] = 24;
        _registers[9] = 9;
        _registers[10] = 0x20;
        _scannedRegisters = (byte[])_registers.Clone();
    }

    /// <summary>
    ///  Gets or sets whether characters are twice as wide, for 40 columns (port <c>$FF</c> bit 4).
    /// </summary>
    public bool WideCharacters { get; set; }

    /// <summary>
    ///  Gets or sets whether the picture is blanked (port <c>$FF</c> bit 6).
    /// </summary>
    public bool Blanked { get; set; }

    /// <summary>
    ///  Gets the T-state within the frame.
    /// </summary>
    public int CycleInFrame { get; private set; }

    /// <summary>
    ///  Gets the frames completed.
    /// </summary>
    public ulong Frames { get; private set; }

    /// <summary>
    ///  Gets whether the display is in its active area rather than blanking, which port <c>$FF</c> bit 6 reads.
    /// </summary>
    public bool DisplayEnabled
    {
        get
        {
            int line = CycleInFrame / Trs80Model2Timing.CyclesPerLine;
            int column = CycleInFrame % Trs80Model2Timing.CyclesPerLine;
            return line < VerticalSyncLine && column < Trs80Model2Timing.CyclesPerLine * 4 / 5;
        }
    }

    /// <summary>
    ///  Gets the characters per row the 6845 displays.
    /// </summary>
    public int Columns => Math.Clamp((int)_registers[1], 1, 80);

    /// <summary>
    ///  Gets the character rows the 6845 displays.
    /// </summary>
    public int Rows => Math.Clamp(_registers[6] & 0x7F, 1, MaximumRows);

    /// <summary>
    ///  Gets the scanlines per character row.
    /// </summary>
    public int LinesPerRow => Math.Clamp((_registers[9] & 0x1F) + 1, 1, MaximumLinesPerRow);

    /// <summary>
    ///  Gets the display's start address in video RAM.
    /// </summary>
    public int StartAddress => ((_registers[12] & 0x3F) << 8) | _registers[13];

    /// <summary>
    ///  Gets the cursor's address in video RAM.
    /// </summary>
    public int CursorAddress => ((_registers[14] & 0x3F) << 8) | _registers[15];

    // The scanline vertical sync starts on, after the displayed rows, leaving at least 20 lines of blanking.
    private int VerticalSyncLine => Math.Min(Rows * LinesPerRow, Trs80Model2Timing.LinesPerFrame - 20);

    /// <inheritdoc/>
    public int Width => 640;

    /// <inheritdoc/>
    public int Height => MaximumRows * MaximumLinesPerRow;

    /// <inheritdoc/>
    public int CyclesPerFrame => Trs80Model2Timing.CyclesPerFrame;

    /// <summary>
    ///  Reads video RAM.
    /// </summary>
    /// <param name="offset">The offset, 0-2047.</param>
    /// <returns>The byte.</returns>
    public byte Read(int offset) => _ram[offset & 0x7FF];

    /// <summary>
    ///  Writes video RAM.
    /// </summary>
    /// <param name="offset">The offset, 0-2047.</param>
    /// <param name="value">The byte.</param>
    public void Write(int offset, byte value) => _ram[offset & 0x7FF] = value;

    /// <summary>
    ///  Gets the code shown at a character position.
    /// </summary>
    /// <param name="row">The row.</param>
    /// <param name="column">The column.</param>
    /// <returns>The code.</returns>
    public byte Displayed(int row, int column) => Read(StartAddress + (row * Columns) + column);

    /// <summary>
    ///  Reads a 6845 register: only the cursor address (R14, R15) reads back.
    /// </summary>
    /// <returns>The value.</returns>
    internal byte CrtcRead() => _register is 14 or 15 ? _registers[_register] : (byte)0;

    /// <summary>
    ///  Writes the 6845's address register (<paramref name="data"/> false) or the register it selects.
    /// </summary>
    /// <param name="data">Whether the selected register is written.</param>
    /// <param name="value">The value.</param>
    internal void CrtcWrite(bool data, byte value)
    {
        if (!data) { _register = value & 0x1F; }
        else if (_register < _registers.Length) { _registers[_register] = value; }
    }

    /// <summary>
    ///  Advances the beam one T-state.
    /// </summary>
    /// <returns>Whether vertical sync started on this T-state.</returns>
    internal bool Tick()
    {
        if (++CycleInFrame < Trs80Model2Timing.CyclesPerFrame)
        {
            // The picture is latched as the beam leaves the active area, where vertical sync starts.
            if (CycleInFrame != VerticalSyncLine * Trs80Model2Timing.CyclesPerLine) { return false; }
            Array.Copy(_ram, _scanned, _ram.Length);
            _scannedRegisters = (byte[])_registers.Clone();
            _scannedWide = WideCharacters;
            _scannedBlank = Blanked;
            return true;
        }

        CycleInFrame = 0;
        Frames++;
        return false;
    }

    /// <inheritdoc/>
    public void Render(Span<byte> pixels, bool scanned)
    {
        int width = Width;
        if (pixels.Length < width * Height * 4)
        {
            throw new ArgumentException("The pixel buffer is too small.", nameof(pixels));
        }

        Span<uint> output = MemoryMarshal.Cast<byte, uint>(pixels)[..(width * Height)];
        output.Fill(s_off);
        byte[] registers = scanned ? _scannedRegisters : _registers;
        if (scanned ? _scannedBlank : Blanked) { return; }
        byte[] source = scanned ? _scanned : _ram;
        bool wide = scanned ? _scannedWide : WideCharacters;
        int columns = Math.Clamp((int)registers[1], 1, 80);
        int rows = Math.Clamp(registers[6] & 0x7F, 1, MaximumRows);
        int lines = Math.Clamp((registers[9] & 0x1F) + 1, 1, MaximumLinesPerRow);
        int start = ((registers[12] & 0x3F) << 8) | registers[13];
        int cursor = ((registers[14] & 0x3F) << 8) | registers[15];
        int cursorStart = registers[10] & 0x1F;
        int cursorEnd = registers[11] & 0x1F;
        bool cursorShown = (registers[10] & 0x60) switch
        {
            0x00 => true,
            0x20 => false,
            0x40 => (Frames / 8) % 2 == 0,
            _ => (Frames / 16) % 2 == 0
        };

        int characterWidth = wide ? 16 : 8;
        int left = Math.Max(0, (width - (columns * characterWidth)) / 2);
        int top = (Height - (rows * lines)) / 2;
        for (int row = 0; row < rows; row++)
        {
            for (int line = 0; line < lines; line++)
            {
                Span<uint> scan = output.Slice((top + (row * lines) + line) * width, width);
                for (int column = 0; column < columns && left + ((column + 1) * characterWidth) <= width; column++)
                {
                    int address = (start + (row * columns) + column) & 0x7FF;
                    byte code = source[address];
                    int dots = _characterGenerator[((code & 0x7F) << 4) | line];
                    if ((code & 0x80) != 0) { dots ^= 0xFF; }
                    if (cursorShown && address == (cursor & 0x7FF) && line >= cursorStart && line <= cursorEnd)
                    {
                        dots ^= 0xFF;
                    }

                    for (int x = 0; x < characterWidth; x++)
                    {
                        int pixel = wide ? x / 2 : x;
                        scan[left + (column * characterWidth) + x] = (dots & (0x80 >> pixel)) != 0 ? s_on : s_off;
                    }
                }
            }
        }
    }

    private static uint Rgba(byte red, byte green, byte blue) =>
        (uint)(red | (green << 8) | (blue << 16) | (0xFF << 24));
}
