// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Machines.Chips;

/// <summary>
///  The MOS 6560 (NTSC) and 6561 (PAL) Video Interface Chip of the VIC-20: a text screen of programmable size from a
///  character generator, 16 colours, four sound voices and two paddle inputs.
/// </summary>
/// <remarks>
///  <para>
///   The chip draws four dots each bus cycle and, for each character it shows, fetches its code and colour, then the
///   character's row of dots, two fetches in two cycles. It does so in the half of each cycle the processor does not
///   use, so it never stops the processor. Outside the text window it reads its address <c>$001C</c>. A read that
///   nothing answers, the processor's or the chip's own, sees the byte the chip fetched last, as Marko Mäkelä
///   measured; so do the top four bits of a read of colour RAM. MAME differs here: its bus also keeps the processor's
///   accesses and has no read of <c>$001C</c>, and the chip's own reads keep only the bits its last colour fetch
///   had. A frame drawn from the registers as they are now, rather than scanned, reads such bytes as the chip's last
///   fetch is when it is drawn.
///  </para>
///  <para>
///   The registers, at <c>$9000-$900F</c> on the VIC-20. 0: bit 7 interlace (6560 only), bits 0-6 the text window's
///   left edge in 4-dot steps. 1: the window's top line in 2-line steps. 2: bit 7 the screen's and colour RAM's address
///   bit 9, bits 0-6 the columns. 3: bit 7 the raster line's bit 0 (read), bits 1-6 the rows, bit 0 8 × 16 characters.
///   4: the raster line's bits 8-1 (read). 5: bits 4-7 the screen's address bits 13-10, bits 0-3 the characters'. 6 and
///   7: the light pen's X and Y, which read 0, since no pen is connected. 8 and 9: the paddles. 10-13: bass, alto,
///   soprano and noise, bit 7 on and bits 0-6 the frequency. 14: bits 4-7 the auxiliary colour, bits 0-3 the volume.
///   15: bits 4-7 the background, bit 3 clear for reversed characters, bits 0-2 the border.
///  </para>
///  <para>
///   A character's colour nybble picks its colour from the first eight in bits 0-2; bit 3 makes it multicolour, where
///   each pair of dots is the background (00), the border (01), the character's colour (10) or the auxiliary colour
///   (11).
///  </para>
///  <para>
///   Timing and register meanings are from Marko Mäkelä's 6560/6561 documentation (measured on the 6560-101 and
///   6561-101) and the VIC-20 Programmer's Reference Guide. Interlace is kept as a register bit but not drawn.
///  </para>
///  <para>
///   The window's columns are taken at each line's second cycle, and its rows at the frame's first line, as MAME's
///   6560 takes them; its origin and the screen's and characters' addresses are read at the cycle they are used.
///   Where MAME differs, this does not follow it yet: a row's screen address is the row times the line's columns,
///   not a count carried from the row before, and the 6560's raster registers read the line being drawn, not the
///   count 37 cycles ahead that MAME gives.
///  </para>
///  <para>
///   The voices' periods and the noise are MAME's, but a tone takes up a frequency written within its half wave only
///   at the next half, and the mix is in proportion to the volume where MAME's follows the chip's DAC.
///  </para>
/// </remarks>
public sealed class Vic6560 : IVideoSource
{
    /// <summary>
    ///  The NTSC VIC-20's bus clock in hertz: the 14.318 MHz crystal divided by 14.
    /// </summary>
    public const double NtscCpuHertz = 14_318_181.0 / 14;

    /// <summary>
    ///  The PAL VIC-20's bus clock in hertz: the 4.434 MHz crystal divided by 4.
    /// </summary>
    public const double PalCpuHertz = 4_433_618.0 / 4;

    // The 6561's 16 colours as RGB, MAME's approximation of them.
    private static readonly uint[] s_palPalette =
    [
        0x000000, 0xFFFFFF, 0xB61F21, 0x4DF0FF, 0xB43FFF, 0x44E237, 0x1A34FF, 0xDCD71B,
        0xCA5400, 0xE9B072, 0xE79293, 0x9AF7FD, 0xE09FFF, 0x8FE493, 0x8290FF, 0xE5DE85
    ];

    // The 6560's, which NTSC's colour carrier makes different, also MAME's.
    private static readonly uint[] s_ntscPalette =
    [
        0x000000, 0xFFFFFF, 0xF91137, 0x35F9F6, 0xFF3CC6, 0x3CEDA9, 0x0F57F7, 0xFEE963,
        0xFB6244, 0xFBBFDE, 0xF3ACE5, 0xA8EADD, 0xE6B8F7, 0xABDDA4, 0x6AB3E7, 0xF7DAA5
    ];

    // The cycles between ticks of each voice's counter: bass, alto, soprano and noise.
    private static readonly int[] s_prescale = [128, 64, 32, 2];

    private const int SampleBufferLength = 512;

    private readonly IVicMemory _memory;
    private readonly byte[] _registers = new byte[16];
    private readonly byte[] _frame;
    private readonly int _firstLine;
    private readonly int _firstDot;
    private readonly int _maximumColumns;
    private readonly uint[] _palette;

    private readonly int[] _prescale = new int[4];
    private readonly int[] _divider = new int[4];
    private readonly bool[] _voiceHigh = new bool[4];
    private readonly float[] _samples = new float[SampleBufferLength];
    private readonly double _cyclesPerSample;
    private readonly float _highPass;
    private IAudioSink? _sink;
    private int _sampleCount;
    private double _samplePhase;
    private double _sampleIntegral;
    private float _previousSample;
    private float _filteredSample;
    private ushort _noise;
    private bool _noiseBit0;
    private byte _noiseShift;
    private int _textColumns;
    private int _textRows;

    private int _line;
    private int _cycle;
    private byte _lastFetch;
    private bool _fetchedInWindow;

    /// <summary>
    ///  Creates the chip at the start of a frame.
    /// </summary>
    /// <param name="memory">What the chip reads.</param>
    /// <param name="standard">NTSC for the 6560, PAL for the 6561.</param>
    /// <param name="sampleRate">The sound's sample rate in hertz.</param>
    public Vic6560(IVicMemory memory, VicVideoStandard standard, int sampleRate = 48000)
    {
        ArgumentNullException.ThrowIfNull(memory);
        ArgumentOutOfRangeException.ThrowIfNegativeOrZero(sampleRate);
        _memory = memory;
        Standard = standard;
        if (standard == VicVideoStandard.Ntsc)
        {
            CyclesPerLine = 65;
            LinesPerFrame = 261;
            CpuHertz = NtscCpuHertz;
            Width = 200;
            Height = 248;
            _firstDot = 8;
            _firstLine = 12;
            _maximumColumns = 31;
            _palette = s_ntscPalette;
        }
        else
        {
            CyclesPerLine = 71;
            LinesPerFrame = 312;
            CpuHertz = PalCpuHertz;
            Width = 224;
            Height = 296;
            _firstDot = 24;
            _firstLine = 14;
            _maximumColumns = 32;
            _palette = s_palPalette;
        }

        _frame = new byte[Width * Height];
        SampleRate = sampleRate;
        _cyclesPerSample = CpuHertz / sampleRate;
        _highPass = MathF.Exp(-2 * MathF.PI * 20 / sampleRate);
    }

    /// <summary>
    ///  Gets the video standard.
    /// </summary>
    public VicVideoStandard Standard { get; }

    /// <summary>
    ///  Gets the bus clock in hertz.
    /// </summary>
    public double CpuHertz { get; }

    /// <summary>
    ///  Gets the bus cycles in a line: 65 on the 6560, 71 on the 6561.
    /// </summary>
    public int CyclesPerLine { get; }

    /// <summary>
    ///  Gets the lines in a frame: 261 on the 6560, 312 on the 6561.
    /// </summary>
    public int LinesPerFrame { get; }

    /// <inheritdoc/>
    public int Width { get; }

    /// <inheritdoc/>
    public int Height { get; }

    /// <inheritdoc/>
    public int CyclesPerFrame => CyclesPerLine * LinesPerFrame;

    /// <summary>
    ///  Gets the raster line the beam is on.
    /// </summary>
    public int Line => _line;

    /// <summary>
    ///  Gets the cycle within the line.
    /// </summary>
    public int Cycle => _cycle;

    /// <summary>
    ///  Gets the byte the chip fetched last, which a processor read of unconnected addresses sees.
    /// </summary>
    public byte LastFetch => _fetchedInWindow ? _lastFetch : _memory.FetchVideo(0x001C);

    /// <summary>
    ///  Gets or sets the X paddle's reading, 0-255; with none connected it reads <c>$FF</c>.
    /// </summary>
    public byte PaddleX { get; set; } = 0xFF;

    /// <summary>
    ///  Gets or sets the Y paddle's reading, 0-255; with none connected it reads <c>$FF</c>.
    /// </summary>
    public byte PaddleY { get; set; } = 0xFF;

    /// <summary>
    ///  Gets the sound's sample rate in hertz.
    /// </summary>
    public int SampleRate { get; }

    /// <summary>
    ///  Gets or sets where the sound's stereo samples go; null turns sound off.
    /// </summary>
    public IAudioSink? AudioSink
    {
        get => _sink;
        set
        {
            if (ReferenceEquals(_sink, value)) { return; }
            _sink = value;
            _sampleCount = 0;
            _samplePhase = 0;
            _sampleIntegral = 0;
            _previousSample = 0;
            _filteredSample = 0;
        }
    }

    /// <summary>
    ///  Gets the screen's address in the chip's space: register 5's bits 4-7 and register 2's bit 7.
    /// </summary>
    public int ScreenAddress => ((_registers[5] & 0xF0) << 6) | ((_registers[2] & 0x80) << 2);

    /// <summary>
    ///  Gets the character generator's address in the chip's space: register 5's bits 0-3.
    /// </summary>
    public int CharacterAddress => (_registers[5] & 0x0F) << 10;

    /// <summary>
    ///  Gets the text window's columns.
    /// </summary>
    public int Columns => Math.Min(_registers[2] & 0x7F, _maximumColumns);

    /// <summary>
    ///  Gets the text window's rows.
    /// </summary>
    public int Rows => (_registers[3] >> 1) & 0x3F;

    /// <summary>
    ///  Gets whether characters are 8 × 16 dots rather than 8 × 8.
    /// </summary>
    public bool TallCharacters => (_registers[3] & 1) != 0;

    /// <summary>
    ///  Reads a register.
    /// </summary>
    /// <param name="register">The register, 0-15.</param>
    /// <returns>Its value.</returns>
    public byte Read(int register) => (register & 15) switch
    {
        3 => (byte)((_registers[3] & 0x7F) | ((_line & 1) << 7)),
        4 => (byte)(_line >> 1),
        6 or 7 => 0,
        8 => PaddleX,
        9 => PaddleY,
        int other => _registers[other]
    };

    /// <summary>
    ///  Writes a register.
    /// </summary>
    /// <param name="register">The register, 0-15.</param>
    /// <param name="value">The value.</param>
    public void Write(int register, byte value) => _registers[register & 15] = value;

    /// <summary>
    ///  Advances the chip one bus cycle: draws its four dots, runs the sound and moves the beam.
    /// </summary>
    public void Tick()
    {
        if (_cycle == 1) { _textColumns = Columns; }
        else if (_cycle == 2 && _line == 0) { _textRows = Rows; }

        DrawCycle(_line, _cycle, _frame, fetch: true);
        if (_sink is not null) { TickSound(); }
        if (++_cycle == CyclesPerLine)
        {
            _cycle = 0;
            if (++_line == LinesPerFrame) { _line = 0; }
        }
    }

    /// <summary>
    ///  Sends buffered samples to the sink.
    /// </summary>
    public void FlushAudio()
    {
        int count = _sampleCount;
        _sampleCount = 0;
        if (count != 0) { _sink?.WriteSamples(_samples.AsSpan(0, count)); }
    }

    /// <inheritdoc/>
    public void Render(Span<byte> pixels, bool scanned)
    {
        if (pixels.Length != Width * Height * 4)
        {
            throw new ArgumentException($"Pixels must be {Width}×{Height} RGBA.", nameof(pixels));
        }

        byte[] source = _frame;
        if (!scanned)
        {
            source = new byte[_frame.Length];
            for (int line = _firstLine; line < _firstLine + Height; line++)
            {
                for (int cycle = 0; cycle < CyclesPerLine; cycle++) { DrawCycle(line, cycle, source, fetch: false); }
            }
        }

        for (int index = 0; index < source.Length; index++)
        {
            uint rgb = _palette[source[index] & 15];
            int offset = index * 4;
            pixels[offset] = (byte)(rgb >> 16);
            pixels[offset + 1] = (byte)(rgb >> 8);
            pixels[offset + 2] = (byte)rgb;
            pixels[offset + 3] = 0xFF;
        }
    }

    /// <summary>
    ///  Renders a frame from current memory and registers.
    /// </summary>
    /// <returns><see cref="Width"/> × <see cref="Height"/> RGBA.</returns>
    public byte[] RenderBitmap()
    {
        byte[] pixels = new byte[Width * Height * 4];
        Render(pixels, scanned: false);
        return pixels;
    }

    /// <summary>
    ///  Gets the colour, 0-15, of a dot of the last scanned frame.
    /// </summary>
    /// <param name="x">The dot, from the visible frame's left.</param>
    /// <param name="y">The line, from the visible frame's top.</param>
    /// <returns>The colour.</returns>
    public int ScannedColour(int x, int y) => _frame[(y * Width) + x];

    /// <summary>
    ///  Gets a colour's red, green and blue on this chip.
    /// </summary>
    /// <param name="colour">The colour, 0-15.</param>
    /// <returns>The colour as <c>0xRRGGBB</c>.</returns>
    public uint Rgb(int colour) => _palette[colour & 15];

    // Draws the four dots of a cycle, with the registers as they are now, into a frame of colour numbers.
    private void DrawCycle(int line, int cycle, byte[] target, bool fetch)
    {
        int y = line - _firstLine;
        int x = (cycle * 4) - _firstDot;
        bool visible = y >= 0 && y < Height && x > -4 && x < Width;

        int height = TallCharacters ? 16 : 8;
        int textLine = line - (_registers[1] * 2);
        int textCycle = cycle - (_registers[0] & 0x7F);
        // A frame drawn from the registers as they are now takes their window as it is now too.
        int columns = fetch ? _textColumns : Columns;
        int rows = fetch ? _textRows : Rows;
        byte border = (byte)(_registers[15] & 7);
        if (textLine < 0 || textLine >= rows * height || textCycle < 0 || textCycle >= columns * 2)
        {
            if (fetch) { _fetchedInWindow = false; }
            if (visible) { Fill(target, x, y, border, border, border, border); }
            return;
        }

        int row = TallCharacters ? textLine >> 4 : textLine >> 3;
        int lineInCharacter = textLine & (height - 1);
        int column = textCycle >> 1;
        int screen = (ScreenAddress + (row * columns) + column) & 0x3FFF;
        byte code = _memory.FetchVideo(screen);
        byte colour = (byte)(_memory.FetchColour(screen & 0x3FF) & 0x0F);
        byte dots = _memory.FetchVideo((CharacterAddress + (code * height) + lineInCharacter) & 0x3FFF);
        bool second = (textCycle & 1) != 0;
        if (fetch)
        {
            _fetchedInWindow = true;
            _lastFetch = second ? dots : code;
        }

        if (!visible) { return; }

        byte background = (byte)(_registers[15] >> 4);
        byte foreground = (byte)(colour & 7);
        int half = second ? dots & 0x0F : dots >> 4;
        if ((colour & 8) != 0)
        {
            byte auxiliary = (byte)(_registers[14] >> 4);
            byte first = Multicolour(half >> 2);
            byte next = Multicolour(half & 3);
            Fill(target, x, y, first, first, next, next);

            byte Multicolour(int pair) => pair switch
            {
                0 => background,
                1 => border,
                2 => foreground,
                _ => auxiliary
            };

            return;
        }

        // Register 15's bit 3 clear shows every character reversed.
        if ((_registers[15] & 8) == 0) { (foreground, background) = (background, foreground); }
        Fill(
            target,
            x,
            y,
            (half & 8) != 0 ? foreground : background,
            (half & 4) != 0 ? foreground : background,
            (half & 2) != 0 ? foreground : background,
            (half & 1) != 0 ? foreground : background);
    }

    private void Fill(byte[] target, int x, int y, byte first, byte second, byte third, byte fourth)
    {
        int row = y * Width;
        Put(x, first);
        Put(x + 1, second);
        Put(x + 2, third);
        Put(x + 3, fourth);

        void Put(int dot, byte colour)
        {
            if ((uint)dot < (uint)Width) { target[row + dot] = colour; }
        }
    }

    // Each voice's counter takes a step on each tick of its prescaled clock and from $7F reloads its frequency
    // register plus one, in seven bits, so a register written mid-count takes effect at the next reload. A tone
    // ticks every 128 cycles for bass, 64 for alto and 32 for soprano and toggles its square wave at each reload:
    // MAME's ticks 8 times as often and shifts an 8-bit ring at each reload, which gives the same period, 256 times
    // 128 less the count for bass, but takes up a written register within the half wave. Noise ticks every 2 cycles,
    // each reload steps a 16-bit shift register, and each rise of that register's low bit steps an 8-bit ring whose
    // low bit is the voice, as MAME's has it. A voice turned off holds its waves low. The voices are mixed in
    // proportion to the volume, where MAME looks the level up in a table of the chip's DAC.
    private void TickSound()
    {
        for (int voice = 0; voice < 4; voice++)
        {
            if (++_prescale[voice] < s_prescale[voice]) { continue; }
            _prescale[voice] = 0;
            byte register = _registers[10 + voice];
            if (_divider[voice] != 0x7F)
            {
                _divider[voice]++;
                continue;
            }

            _divider[voice] = (register + 1) & 0x7F;
            bool enabled = (register & 0x80) != 0;
            if (voice < 3)
            {
                _voiceHigh[voice] = enabled && !_voiceHigh[voice];
                continue;
            }

            if ((_noise & 1) != 0 && !_noiseBit0)
            {
                _noiseShift = (byte)((_noiseShift << 1) | ((_noiseShift & 0x80) == 0 && enabled ? 1 : 0));
            }

            int feedback = ((_noise >> 3) ^ (_noise >> 12) ^ (_noise >> 14) ^ (_noise >> 15)) & 1;
            _noiseBit0 = (_noise & 1) != 0;
            _noise = (ushort)((_noise << 1) | (feedback == 0 && enabled ? 0 : 1));
            _voiceHigh[3] = (_noiseShift & 1) != 0;
        }

        int on = 0;
        for (int voice = 0; voice < 4; voice++)
        {
            if ((_registers[10 + voice] & 0x80) != 0 && _voiceHigh[voice]) { on++; }
        }

        float level = on * (_registers[14] & 15) / 60f;
        if (_samplePhase + 1 >= _cyclesPerSample)
        {
            double part = _cyclesPerSample - _samplePhase;
            _sampleIntegral += level * part;
            Emit((float)(_sampleIntegral / _cyclesPerSample));
            _samplePhase = 1 - part;
            _sampleIntegral = level * _samplePhase;
            return;
        }

        _sampleIntegral += level;
        _samplePhase += 1;
    }

    private void Emit(float sample)
    {
        _filteredSample = _highPass * (_filteredSample + (sample - _previousSample));
        _previousSample = sample;
        float value = Math.Clamp(_filteredSample, -1, 1);
        _samples[_sampleCount++] = value;
        _samples[_sampleCount++] = value;
        if (_sampleCount == _samples.Length) { FlushAudio(); }
    }
}
