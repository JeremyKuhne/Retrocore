// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Assembler;

internal sealed partial class AssemblyPreprocessor
{
    // Binary includes lower to .byte lines of this many values, keeping each statement small.
    private const int BinaryBytesPerLine = 16;

    private const string ByteDirective = ".byte ";

    private const string HexDigits = "0123456789ABCDEF";

    private bool Include(string operand, Line line, int includeDepth, int macroDepth)
    {
        ReadOnlySpan<char> text = operand;
        text = text.Trim();
        if (text.Length < 2 || text[0] is not ('"' or '<'))
        {
            Error(".include requires a quoted path or an SDK path in angle brackets.", line.Location);
            return false;
        }

        bool sdk = text[0] == '<';
        int closing = text[1..].IndexOf(sdk ? '>' : '"');
        if (closing < 0)
        {
            Error("Unterminated include path.", line.Location);
            return false;
        }

        string request = text.Slice(1, closing).ToString();
        ReadOnlySpan<char> suffix = text[(closing + 2)..].Trim();
        AssemblyDialect? selected = null;
        if (!suffix.IsEmpty)
        {
            if (!suffix.StartsWith("dialect=", StringComparison.OrdinalIgnoreCase)
                || !Enum.TryParse(suffix["dialect=".Length..].ToString(), ignoreCase: true, out AssemblyDialect dialect)
                || !Enum.IsDefined(dialect))
            {
                Error("Invalid include dialect override.", line.Location);
                return false;
            }

            selected = dialect;
        }

        if (request.Length == 0)
        {
            Error("Include paths cannot be empty.", line.Location);
            return false;
        }

        if (_options.SourceResolver is not { } resolver)
        {
            Error("An include source resolver must be configured.", line.Location);
            return false;
        }

        AssemblySource? resolved = null;
        try
        {
            foreach ((string from, string candidate) in Candidates(request, sdk, line))
            {
                if (resolver.TryResolve(from, candidate, out resolved)) { break; }
            }
        }
        catch (Exception error) when (ReportResolution(error, line))
        {
            return false;
        }

        if (resolved is null)
        {
            Error($"Include source '{request}' was not found.", line.Location);
            return false;
        }

        return ProcessSource(resolved, line.Dialect, line.Location, selected, includeDepth + 1, macroDepth);
    }

    private void IncludeBinary(string operand, Line line)
    {
        List<string> arguments = Arguments(operand);
        string path = arguments.Count != 0 ? arguments[0] : "";
        if (arguments.Count is < 1 or > 3 || path.Length < 2 || path[0] != '"' || path[^1] != '"')
        {
            Error(".incbin requires a quoted path, an optional start and an optional size.", line.Location);
            return;
        }

        if (_options.SourceResolver is not IAssemblyBinaryResolver resolver)
        {
            Error("Binary includes (.incbin) are not supported by this source resolver.", line.Location);
            return;
        }

        string request = path[1..^1];
        long start = 0;
        long size = -1;
        if (arguments.Count > 1 && !Constant(arguments[1], line.Location, out start, ".incbin start")) { return; }
        if (arguments.Count > 2 && !Constant(arguments[2], line.Location, out size, ".incbin size")) { return; }
        byte[]? data = null;
        try
        {
            foreach ((string from, string candidate) in Candidates(request, sdk: false, line))
            {
                if (resolver.TryResolveBinary(from, candidate, out data)) { break; }
            }
        }
        catch (Exception error) when (ReportResolution(error, line))
        {
            return;
        }

        if (data is null)
        {
            Error($"Binary include '{request}' was not found.", line.Location);
            return;
        }

        if (size < 0) { size = data.Length - start; }
        if (start < 0 || start > data.Length || size < 0 || size > data.Length - start)
        {
            Error(".incbin start and size must lie within the file.", line.Location);
            return;
        }

        // ".byte " then "$XX" per value, comma separated.
        char[] text = new char[ByteDirective.Length + (BinaryBytesPerLine * 4)];
        ByteDirective.CopyTo(0, text, 0, ByteDirective.Length);
        for (long offset = start; offset < start + size; offset += BinaryBytesPerLine)
        {
            int length = ByteDirective.Length;
            long end = Math.Min(start + size, offset + BinaryBytesPerLine);
            for (long index = offset; index < end; index++)
            {
                if (index != offset) { text[length++] = ','; }
                text[length++] = '$';
                text[length++] = HexDigits[data[index] >> 4];
                text[length++] = HexDigits[data[index] & 0xF];
            }

            Emit(line, new string(text, 0, length));
        }
    }

    private IEnumerable<(string From, string Request)> Candidates(string request, bool sdk, Line line)
    {
        // Quoted requests try the including document's directory before the configured search paths.
        if (!sdk) { yield return (line.Location.Path, request); }
        foreach (string path in sdk ? _options.SdkPaths : _options.IncludePaths)
        {
            string candidate = AssemblySourcePaths.Combine(path, request);
            yield return sdk && !AssemblySourcePaths.IsWithin(path, candidate)
                ? throw new AssemblyError(line.Location.Line, "An SDK include must stay within a configured SDK directory.")
                : ("", candidate);
        }
    }

    private bool ReportResolution(Exception error, Line line)
    {
        string? message = error switch
        {
            IOException => $"Include could not be read: {error.Message}",
            AssemblyError => error.Message,
            UnauthorizedAccessException => $"Include access was denied: {error.Message}",
            ArgumentException => $"Invalid include path: {error.Message}",
            _ => null
        };

        if (message is not null) { Error(message, line.Location); }
        return message is not null;
    }
}
