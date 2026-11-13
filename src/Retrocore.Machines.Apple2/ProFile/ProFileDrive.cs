// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Machines.Devices;
using Retrocore.Media;

namespace Retrocore.Machines.Apple2;

/// <summary>
///  Apple's ProFile hard disk as its interface card sees it: the Z8 controller's side of the CMD-BSY handshake, its
///  one-block buffer, and the blocks of a ProDOS-order image.
/// </summary>
/// <remarks>
///  <para>
///   The host and the ProFile talk through a data port and two lines: CMD, which the host raises, and BSY, which the
///   ProFile raises. Each exchange is a handshake: the host raises CMD; the ProFile raises BSY with a response byte on
///   the port saying what it is ready for; the host answers $55 to go on (or $AA to refuse) and drops CMD; the ProFile
///   does what it said and drops BSY. A read or write of a block takes these handshakes:
///  </para>
///  <para>
///   Response 1 is ready for a command: the host then writes six bytes into the buffer, the command (0 read, 1
///   write, 2 write and verify), the three-byte block number, the retry count and the sparing threshold. For a read,
///   response 2: the ProFile reads the block, and the buffer holds four status bytes, the 512 bytes of data and the
///   block's 20 tag bytes, which the host reads in that order. For a write, response 3 (4 to verify): the host
///   writes the data and its tags into the buffer; at the next handshake, response 6, the ProFile writes the block,
///   and the buffer holds the four status bytes.
///  </para>
///  <para>
///   Any other command byte, such as the $FF that Apple's SOS driver sends after its last block, ends the exchange
///   with no response. Block $FFFFFF is the ProFile's own identification block: its name, type, firmware revision,
///   size and spares. The status bytes are all zero for success; a block past the end, or a write to a read-only
///   image, sets bit 0 of the first ("operation unsuccessful").
///  </para>
///  <para>
///   The drive answers at once, with no seek or rotation time, and keeps no tags: they read as zeros. With no image
///   it is not connected, which the card reports.
///  </para>
/// </remarks>
public sealed class ProFileDrive : IBlockStorage
{
    /// <summary>
    ///  The response to a handshake while idle: ready for a command.
    /// </summary>
    public const byte ReadyForCommand = 1;

    /// <summary>
    ///  The response to a read command: the block is in the buffer, after the status.
    /// </summary>
    public const byte ReadResponse = 2;

    /// <summary>
    ///  The response to a write command: ready for the data.
    /// </summary>
    public const byte WriteResponse = 3;

    /// <summary>
    ///  The response to a write-and-verify command: ready for the data.
    /// </summary>
    public const byte WriteVerifyResponse = 4;

    /// <summary>
    ///  The response once the data of a write is in: the block is written at the acknowledgement.
    /// </summary>
    public const byte WriteDataResponse = 6;

    /// <summary>
    ///  The host's answer that goes on with a handshake.
    /// </summary>
    public const byte Acknowledge = 0x55;

    /// <summary>
    ///  The ProFile's own identification block.
    /// </summary>
    public const uint IdentificationBlock = 0xFFFFFF;

    /// <summary>
    ///  The largest image a ProFile can hold: its 24-bit block numbers, less the two it keeps for itself.
    /// </summary>
    public const uint MaximumBlocks = 0xFFFFFE;

    private const int StatusLength = 4;
    private const int DataLength = 512;
    private const int TagLength = 20;
    private const int BufferLength = StatusLength + DataLength + TagLength;
    private const byte OperationFailed = 0x01;

    private readonly byte[] _buffer = new byte[BufferLength];
    private readonly Func<long> _clock;
    private readonly long _activityTime;

    private IBlockDevice? _image;
    private string _label = "";
    private string _format = "";
    private bool _changed;
    private ProFilePhase _phase;
    private byte _response;
    private byte _answer;
    private (byte Command, uint Block) _command;
    private int _pointer;
    private uint? _lastBlock;
    private bool _lastWrite;
    private long _lastTime = long.MinValue;

    /// <summary>
    ///  Creates a drive with no image.
    /// </summary>
    /// <param name="id">The device's identifier, such as <c>slot4profile</c>.</param>
    /// <param name="name">The name the machine's documentation uses, such as <c>.PROFILE</c>.</param>
    /// <param name="controller">The card that drives it.</param>
    /// <param name="clock">The machine's time, in any unit, for <see cref="Activity"/>.</param>
    /// <param name="activityTime">How long a block shows as reading or writing, in the clock's unit.</param>
    public ProFileDrive(string id, string name, string controller, Func<long> clock, long activityTime)
    {
        ArgumentNullException.ThrowIfNull(clock);
        Id = id;
        _clock = clock;
        _activityTime = activityTime;
        Info = new()
        {
            Name = name,
            Description = "ProFile 5 MB hard disk",
            Controller = controller,
            Formats = ["po", "hdv"],
            Operations = MediaOperations.Insert | MediaOperations.Eject
        };
    }

    /// <inheritdoc/>
    public string Id { get; }

    /// <inheritdoc/>
    public DeviceKind Kind => DeviceKind.BlockStorage;

    /// <inheritdoc/>
    public DeviceInfo Info { get; }

    /// <inheritdoc/>
    public MediaState? Media => _image is null ? null : new(_label, _format, _image.IsReadOnly, _changed);

    /// <inheritdoc/>
    public DeviceActivity Activity => _lastBlock is null || _clock() - _lastTime > _activityTime
        ? DeviceActivity.Idle
        : _lastWrite ? DeviceActivity.Writing : DeviceActivity.Reading;

    /// <inheritdoc/>
    public long BlockCount => _image?.BlockCount ?? 0;

    /// <inheritdoc/>
    public long? LastBlock => _lastBlock;

    /// <summary>
    ///  Gets the image, or null when there is none.
    /// </summary>
    public IBlockDevice? Image => _image;

    /// <summary>
    ///  Gets whether a ProFile is connected: it is when it has an image.
    /// </summary>
    public bool Connected => _image is not null;

    /// <summary>
    ///  Gets whether BSY is high: the ProFile is in a handshake, its response on the port.
    /// </summary>
    public bool Busy => _phase == ProFilePhase.Responding;

    /// <summary>
    ///  Gets whether CMD is high, as the host last set it.
    /// </summary>
    public bool CommandLine { get; private set; }

    /// <summary>
    ///  Puts an image in the drive, as connecting a ProFile that holds it.
    /// </summary>
    /// <param name="image">The blocks, at most <see cref="MaximumBlocks"/>.</param>
    /// <param name="label">What the host calls the image, such as its path.</param>
    /// <param name="format">The image's format, such as <c>PO</c>.</param>
    /// <exception cref="ArgumentException">The image is too large.</exception>
    public void Insert(IBlockDevice image, string label, string format)
    {
        ArgumentNullException.ThrowIfNull(image);
        if (image.BlockCount > MaximumBlocks)
        {
            throw new ArgumentException($"A ProFile holds at most {MaximumBlocks} blocks.", nameof(image));
        }

        _image = image;
        _label = label ?? "";
        _format = format ?? "";
        _changed = false;
        _lastBlock = null;
        Reset();
    }

    /// <summary>
    ///  Takes the image out, as disconnecting the ProFile.
    /// </summary>
    public void Eject()
    {
        _image = null;
        _label = _format = "";
        _changed = false;
        _lastBlock = null;
        Reset();
    }

    /// <summary>
    ///  Resets the ProFile's controller, as the card's reset line does: it forgets any exchange and drops BSY.
    /// </summary>
    public void Reset()
    {
        _phase = ProFilePhase.Idle;
        _pointer = 0;
        _answer = 0;
    }

    /// <summary>
    ///  Sets CMD. Raising it starts a handshake; dropping it ends one, doing what the response said when the host
    ///  answered <see cref="Acknowledge"/>.
    /// </summary>
    /// <param name="high">Whether CMD is high.</param>
    public void SetCommand(bool high)
    {
        if (high == CommandLine) { return; }
        CommandLine = high;
        if (!Connected) { return; }
        if (high)
        {
            Raise();
        }
        else if (_phase == ProFilePhase.Responding)
        {
            Answer();
        }
    }

    /// <summary>
    ///  Reads the port: the response during a handshake, otherwise the next byte of the buffer.
    /// </summary>
    /// <returns>The byte.</returns>
    public byte ReadData()
    {
        if (_phase == ProFilePhase.Responding) { return _response; }
        if (_pointer >= BufferLength) { return 0; }
        return _buffer[_pointer++];
    }

    /// <summary>
    ///  Writes the port: the host's answer during a handshake, otherwise the next byte of the buffer.
    /// </summary>
    /// <param name="value">The byte.</param>
    public void WriteData(byte value)
    {
        if (_phase == ProFilePhase.Responding)
        {
            _answer = value;
            return;
        }

        if (_pointer < BufferLength) { _buffer[_pointer++] = value; }
    }

    // CMD went up: respond to what the host has given since the last handshake.
    private void Raise()
    {
        byte response;
        switch (_phase)
        {
            case ProFilePhase.Command:
                response = _buffer[0] switch
                {
                    0 => ReadResponse,
                    1 => WriteResponse,
                    2 => WriteVerifyResponse,
                    _ => 0
                };

                if (response == 0)
                {
                    _phase = ProFilePhase.Idle;
                    return;
                }

                // The command bytes stay apart from the buffer, which the block's data fills next.
                _command = (_buffer[0], (uint)((_buffer[1] << 16) | (_buffer[2] << 8) | _buffer[3]));
                break;
            case ProFilePhase.WriteData:
                response = WriteDataResponse;
                break;
            default:
                response = ReadyForCommand;
                break;
        }

        _response = response;
        _answer = 0;
        _phase = ProFilePhase.Responding;
    }

    // CMD went down during a handshake: go on as the response said, or forget the exchange if the host refused.
    private void Answer()
    {
        _pointer = 0;
        if (_answer != Acknowledge)
        {
            _phase = ProFilePhase.Idle;
            return;
        }

        switch (_response)
        {
            case ReadyForCommand:
                _phase = ProFilePhase.Command;
                break;
            case ReadResponse:
                Read(_command.Block);
                _phase = ProFilePhase.Result;
                break;
            case WriteResponse or WriteVerifyResponse:
                _phase = ProFilePhase.WriteData;
                break;
            case WriteDataResponse:
                Write(_command.Block);
                _phase = ProFilePhase.Result;
                break;
        }
    }

    private void Read(uint block)
    {
        Array.Clear(_buffer);
        Span<byte> data = _buffer.AsSpan(StatusLength, DataLength);
        if (block == IdentificationBlock)
        {
            Identify(data);
        }
        else if (_image is { } image && block < image.BlockCount)
        {
            image.ReadBlock(block, data);
            Touch(block, write: false);
        }
        else if (block != IdentificationBlock - 1)
        {
            _buffer[0] = OperationFailed;
        }
    }

    private void Write(uint block)
    {
        bool done = false;
        if (_image is { IsReadOnly: false } image && block < image.BlockCount)
        {
            image.WriteBlock(block, _buffer.AsSpan(0, DataLength));
            _changed = true;
            Touch(block, write: true);
            done = true;
        }

        Array.Clear(_buffer);
        if (!done) { _buffer[0] = OperationFailed; }
    }

    private void Touch(uint block, bool write)
    {
        _lastBlock = block;
        _lastWrite = write;
        _lastTime = _clock();
    }

    // The identification block: the name, the device type (0 for 5 MB, $10 for 10 MB), the firmware revision, the
    // blocks, the bytes in a block with its tags, the spare blocks and those used, and the bad blocks.
    private void Identify(Span<byte> data)
    {
        "PROFILE      "u8.CopyTo(data);
        uint blocks = (uint)BlockCount;
        data[15] = blocks > 0x2600 ? (byte)0x10 : (byte)0x00;
        data[16] = 0x03;
        data[17] = 0x98;
        data[18] = (byte)(blocks >> 16);
        data[19] = (byte)(blocks >> 8);
        data[20] = (byte)blocks;
        data[21] = (DataLength + TagLength) >> 8;
        data[22] = (DataLength + TagLength) & 0xFF;
        data[23] = 0x20;
    }
}
