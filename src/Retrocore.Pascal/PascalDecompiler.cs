// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Media;

namespace Retrocore.Pascal;

/// <summary>
///  Decompiles a code file Apple Pascal's Compiler wrote back to Pascal source, written so that the same Compiler
///  compiles it to the same p-code.
/// </summary>
/// <remarks>
///  <para>
///   Apple Pascal's Compiler (UCSD Pascal II.1) translates statement by statement, without optimizing, so its code
///   shows the source's shape: each IF, WHILE, REPEAT, FOR and CASE has its own pattern of jumps, and the stack holds
///   each expression's tree. What the code does not keep is chosen to compile the same way: names are made up from
///   offsets, a variable's type is inferred from how it is used, and where a use disagrees with the type chosen,
///   <c>ORD</c>, <c>CHR</c> and <c>ODD</c>, which compile to nothing, convert it.
///  </para>
///  <para>
///   Variables are declared one to a line, in the order of their offsets, as the Compiler allocates them; words the
///   code never uses are declared as padding, so the words after them stay where they were. A procedure's code
///   follows its nested procedures', so the order of the code gives each procedure's parent, and where a procedure
///   is numbered before one whose code comes earlier, it was declared <c>FORWARD</c>.
///  </para>
///  <para>
///   A unit's procedures are named from its interface text in the library: <c>SYSTEM.LIBRARY</c>, which holds
///   TURTLEGRAPHICS and APPLESTUFF. Without the library, their calls are named by number and the source does not
///   compile.
///  </para>
/// </remarks>
public sealed partial class PascalDecompiler
{
    private readonly PascalCodeFile _file;
    private readonly PascalLibrary? _library;
    private readonly List<string> _warnings = [];
    private readonly List<Procedure> _procedures = [];
    private readonly Frame _system = new(owner: null, level: -1, parameterWords: 0, dataWords: 0);
    private readonly SortedSet<int> _units = [];
    private readonly List<int> _unitOrder = [];
    private PascalSegment? _main;
    private Procedure? _program;

    private PascalDecompiler(PascalCodeFile file, PascalLibrary? library)
    {
        _file = file;
        _library = library;
    }

    /// <summary>
    ///  Decompiles a program's code file.
    /// </summary>
    /// <param name="file">The code file.</param>
    /// <param name="library">The library its units are in, such as <c>SYSTEM.LIBRARY</c>; null without one.</param>
    /// <returns>The source, and what could not be decompiled.</returns>
    /// <exception cref="InvalidDataException">The code file holds no p-code program.</exception>
    public static PascalDecompilation Decompile(PascalCodeFile file, PascalLibrary? library = null)
    {
        ArgumentNullException.ThrowIfNull(file);
        PascalDecompiler decompiler = new(file, library);
        decompiler.LoadProcedures();
        decompiler.DecodeAll();
        decompiler.Withs();
        decompiler.Absorb();
        decompiler.Infer();
        decompiler.Layout();
        string source = decompiler.Write();
        return new PascalDecompilation(source, decompiler._warnings);
    }

    private void Warn(string warning) => _warnings.Add(warning);

    // Finds the program's segment and its segment procedures, and each procedure's parent and frame.
    private void LoadProcedures()
    {
        _main = _file.Segments.FirstOrDefault(IsProgram)
            ?? throw new InvalidDataException("The code file holds no p-code program.");

        foreach (PascalSegment segment in _file.Segments)
        {
            if (segment.Code.Length == 0 || segment.Kind == PascalSegmentKind.Data) { continue; }
            if (segment != _main && segment.Procedure(1) is not { LexicalLevel: >= 1 })
            {
                Warn($"The segment {segment.Name} is not the program's or a segment procedure's, and is left out.");
                continue;
            }

            List<Procedure> procedures = [.. segment.Procedures.Select(code => new Procedure(segment, code))];
            foreach (Procedure procedure in procedures)
            {
                if (procedure.Code.IsNative)
                {
                    Warn($"{procedure} is assembled code, which a Pascal source cannot hold; it is declared EXTERNAL.");
                }

                // A procedure's code ends before its parent's, which is the next of the level above it.
                procedure.Parent = procedures
                    .Where(other => other.Level == procedure.Level - 1 && other.Code.Attributes > procedure.Code.Attributes)
                    .OrderBy(other => other.Code.Attributes)
                    .FirstOrDefault();
            }

            _procedures.AddRange(procedures);
        }

        _program = _procedures.First(procedure => procedure.Segment == _main && procedure.Number == 1);
        foreach (Procedure procedure in _procedures)
        {
            // A segment procedure's parent is the program.
            if (procedure.Parent is null && procedure != _program) { procedure.Parent = _program; }
            procedure.Parent?.Children.Add(procedure);

            PascalProcedure code = procedure.Code;
            procedure.Frame = new Frame(procedure, procedure.Level, code.ParameterSize / 2, code.DataSize / 2);
        }

        foreach (Procedure procedure in _procedures)
        {
            procedure.Children.Sort((first, second) => first.Number.CompareTo(second.Number));
            if (procedure.Code.IsNative) { continue; }

            try
            {
                procedure.Instructions = PcodeDisassembler.Disassemble(procedure.Segment, procedure.Code);
            }
            catch (InvalidDataException exception)
            {
                Warn($"{procedure} does not decode: {exception.Message}");
                procedure.Failed = true;
                continue;
            }

            // A function returns its result's words.
            PcodeInstruction? exit = procedure.Instructions.FirstOrDefault(instruction => instruction.Offset == procedure.Code.Exit);
            if (exit is { Opcode.Code: Pcode.Rnp or Pcode.Rbp } && exit.Operands[0] > 0)
            {
                procedure.ResultWords = exit.Operands[0];
                if (procedure.ResultWords == 2) { procedure.ResultType.Find().Kind = TypeKind.Real; }

                // A function's result is its first words, which its name stands for.
                Variable result = procedure.Frame.At(1);
                result.Kind = VariableKind.Result;
                TypeNode.Unify(result.Type, procedure.ResultType);
            }
        }
    }

    // Whether a segment holds the program: p-code, with a procedure 1 at the outer level.
    private static bool IsProgram(PascalSegment segment) => segment.Code.Length > 0
        && segment.MachineType is PascalMachineType.PcodeLeastFirst or PascalMachineType.PcodeMostFirst or PascalMachineType.Unknown
        && segment.Procedures.Any(procedure => procedure.Index == 1 && procedure.LexicalLevel <= 0 && procedure.Number != 0);

    // The program's segment, once the procedures are loaded.
    private PascalSegment Main => _main ?? throw new InvalidOperationException("The procedures are not loaded.");

    // The program, once the procedures are loaded.
    private Procedure Program => _program ?? throw new InvalidOperationException("The procedures are not loaded.");

    // The frame a level difference reaches from a procedure: its own, an enclosing procedure's, or the system's.
    private Frame Enclosing(Procedure procedure, int levels)
    {
        Procedure? frame = procedure;
        for (int level = 0; level < levels && frame is not null; level++) { frame = frame.Parent; }
        return frame?.Frame ?? _system;
    }

    // The program's globals, which LDO and SRO reach.
    private Frame Globals => Program.Frame;

    private Procedure? Find(PascalSegment segment, int number) =>
        _procedures.FirstOrDefault(procedure => procedure.Segment == segment && procedure.Number == number);

    private Procedure? FindSegment(int segment, int number) =>
        _procedures.FirstOrDefault(procedure => procedure.Segment.Number == segment && procedure.Number == number);

    private void DecodeAll()
    {
        foreach (Procedure procedure in _procedures)
        {
            if (procedure.Failed || procedure.Code.IsNative) { continue; }

            try
            {
                new Decoder(this, procedure).Decode();
            }
            catch (InvalidDataException exception)
            {
                Warn($"{procedure} could not be decompiled: {exception.Message}");
                procedure.Failed = true;
                procedure.Body = [new Unsupported($"{procedure} could not be decompiled: {exception.Message}")];
            }
        }
    }
}
