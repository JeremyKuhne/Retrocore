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
    private readonly PascalDecompilerOptions _options;
    private readonly List<string> _warnings = [];
    private readonly List<Procedure> _procedures = [];

    // How many times a decompile is run again to sign the assembled procedures by all their calls.
    private const int MaximumSigningPasses = 3;

    // The assembled procedures' signatures from a previous decompile's calls, and what this one's calls show.
    private readonly IReadOnlyDictionary<PascalProcedure, NativeSignature> _signatures;
    private readonly Dictionary<PascalProcedure, (int Words, bool Zeros)> _observed = [];

    // The segments that are units of the program's own, linked in.
    private readonly HashSet<PascalSegment> _unitSegments = [];

    // The types of words a constant other than 0 is stored in: a pointer among them is also an integer.
    private readonly List<TypeNode> _constantStores = [];
    private readonly Frame _system = new(owner: null, level: -1, parameterWords: 0, dataWords: 0);
    private readonly SortedSet<int> _units = [];
    private readonly List<int> _unitOrder = [];
    private PascalSegment? _main;

    // Whether the program was compiled as part of the system, (*$U-*): its body does not start as a program's does.
    private bool _systemProgram;

    // The segment of the system's outer block a (*$U-*) program is nested in, which holds no code of the program's.
    private PascalSegment? _shell;
    private Procedure? _program;

    private PascalDecompiler(PascalCodeFile file, PascalDecompilerOptions options, IReadOnlyDictionary<PascalProcedure, NativeSignature> signatures)
    {
        _signatures = signatures;
        _file = file;
        _library = options.Library;
        _options = options;
    }

    /// <summary>
    ///  Decompiles a program's code file.
    /// </summary>
    /// <param name="file">The code file.</param>
    /// <param name="library">The library its units are in, such as <c>SYSTEM.LIBRARY</c>; null without one.</param>
    /// <returns>The source, and what could not be decompiled.</returns>
    /// <exception cref="InvalidDataException">The code file holds no p-code program.</exception>
    public static PascalDecompilation Decompile(PascalCodeFile file, PascalLibrary? library = null) =>
        Decompile(file, new PascalDecompilerOptions { Library = library });

    /// <summary>
    ///  Decompiles a program's code file, with names from its listing and hints.
    /// </summary>
    /// <param name="file">The code file.</param>
    /// <param name="options">The library, listing, names and comments.</param>
    /// <returns>The source, and what could not be decompiled or named.</returns>
    /// <exception cref="InvalidDataException">The code file holds no p-code program.</exception>
    public static PascalDecompilation Decompile(PascalCodeFile file, PascalDecompilerOptions options)
    {
        ArgumentNullException.ThrowIfNull(file);
        ArgumentNullException.ThrowIfNull(options);

        // An assembled procedure is signed by its first call, then by what all its calls have in common, until the two
        // agree.
        IReadOnlyDictionary<PascalProcedure, NativeSignature> signatures = new Dictionary<PascalProcedure, NativeSignature>();
        PascalDecompiler decompiler;
        for (int pass = 0; ; pass++)
        {
            decompiler = new(file, options, signatures);
            decompiler.LoadProcedures();
            decompiler.DecodeAll();
            Dictionary<PascalProcedure, NativeSignature> observed = decompiler.ObservedSignatures();
            if (pass == MaximumSigningPasses || observed.All(pair => decompiler.Signed(pair.Key) == pair.Value))
            {
                break;
            }

            signatures = observed;
        }

        decompiler.Withs();
        decompiler.Absorb();
        decompiler.Infer();
        decompiler.Contain();
        decompiler.Layout();
        decompiler.Rename();
        string source = decompiler.Write();
        string? assembly = decompiler.Assembly();
        return new PascalDecompilation(source, decompiler._warnings)
        {
            Assembly = assembly,
            Units = decompiler._unitSources
        };
    }

    private void Warn(string warning) => _warnings.Add(warning);

    // What an assembled procedure's calls have in common: the fewest words below the call, and whether every call leaves
    // two zero words on top, a function's room for its result.
    private void Observe(Procedure callee, List<Expr> stack)
    {
        int words = stack.Sum(argument => argument.Words);
        bool zeros = stack.Count >= 2 && stack[^1] is Constant { Value: 0 } && stack[^2] is Constant { Value: 0 };
        _observed[callee.Code] = _observed.TryGetValue(callee.Code, out (int Words, bool Zeros) seen)
            ? (Math.Min(seen.Words, words), seen.Zeros && zeros)
            : (words, zeros);
    }

    // The signature a previous decompile's calls give an assembled procedure; null in the first.
    private NativeSignature? SignatureOf(Procedure callee) =>
        _signatures.TryGetValue(callee.Code, out NativeSignature? known) ? known : null;

    // The signatures this decompile's calls give the assembled procedures.
    private Dictionary<PascalProcedure, NativeSignature> ObservedSignatures() => _observed.ToDictionary(
        pair => pair.Key,
        pair =>
        {
            Procedure procedure = _procedures.First(procedure => procedure.Code == pair.Key);
            int words = pair.Value.Zeros ? pair.Value.Words - 2 : pair.Value.Words;
            return new NativeSignature(Math.Min(words, NativeParameterWords(procedure, pair.Value.Zeros) ?? words), pair.Value.Zeros);
        });

    // The signature an assembled procedure was given in this decompile; null if nothing called it.
    private NativeSignature? Signed(PascalProcedure code) =>
        _procedures.FirstOrDefault(procedure => procedure.Code == code) is { Signed: true } procedure
            ? new NativeSignature(procedure.Frame.ParameterWords - (procedure.IsFunction ? 2 : 0), procedure.IsFunction)
            : null;

    // Finds the program's segment and its segment procedures, and each procedure's parent and frame.
    private void LoadProcedures()
    {
        // A (*$U-*) program is a segment procedure at level 0 in the system's outer block, at level -1, which the
        // Compiler writes as segment 0.
        _main = _file.Segments.FirstOrDefault(segment => IsProgram(segment) && segment.Procedure(1)?.LexicalLevel == 0)
            ?? _file.Segments.FirstOrDefault(IsProgram)
            ?? throw new InvalidDataException("The code file holds no p-code program.");

        foreach (PascalSegment segment in _file.Segments)
        {
            if (segment.Code.Length == 0 || segment.Kind == PascalSegmentKind.Data) { continue; }
            if (segment != _main && segment.Procedure(1) is { LexicalLevel: < 0 } outer)
            {
                _shell = segment;
                if (segment.Procedures.Count > 1 || outer.Entry != outer.Exit)
                {
                    Warn($"The system's outer block, {segment.Name}, holds code, which is left out.");
                }

                continue;
            }

            if (segment != _main && segment.Procedure(1) is not { LexicalLevel: >= 1 })
            {
                Warn($"The segment {segment.Name} is not the program's or a segment procedure's, and is left out.");
                continue;
            }

            // A unit of the program's own, which the Linker linked in, has its procedures beside its initialization, at
            // its level; a segment procedure's are in it.
            if (segment != _main && segment.Procedures.Any(IsUnitProcedure)) { _unitSegments.Add(segment); }

            List<Procedure> procedures = [.. segment.Procedures.Select(code => new Procedure(segment, code))];
            foreach (Procedure procedure in procedures)
            {
                if (procedure.Code.IsNative)
                {
                    procedure.NativeBytes = NativeStackBytes(segment, procedure.Code);
                    Warn($"{procedure} is assembled code, which a Pascal source cannot hold; it is declared EXTERNAL, with the parameters and result its code and calls show, and written as source for the Assembler.");
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
        NestSegments();
        foreach (Procedure procedure in _procedures)
        {
            // A segment procedure at level 1 is the program's.
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

            // A program's body starts with a jump to the segments it loads, or two NOPs; a (*$U-*) program's does not.
            if (procedure == _program)
            {
                _systemProgram = procedure.Instructions.Count == 0 || procedure.Instructions[0].Opcode.Code is not (Pcode.Ujp or 210 or 215);
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

    // A segment procedure deeper than level 1 is declared in a procedure one level up, which may be another segment
    // procedure or an ordinary procedure in one: the one its callers are in, or are, at that level, as only there is
    // it seen. A caller's own parent may be such a segment procedure's, so this goes until no more are found.
    private void NestSegments()
    {
        Dictionary<int, List<Procedure>> callers = [];
        foreach (Procedure caller in _procedures.Where(procedure => !procedure.Code.IsNative))
        {
            IReadOnlyList<PcodeInstruction> code;
            try
            {
                code = PcodeDisassembler.Disassemble(caller.Segment, caller.Code);
            }
            catch (InvalidDataException)
            {
                continue;
            }

            foreach (PcodeInstruction call in code.Where(instruction => instruction.Opcode.Code == Pcode.Cxp && instruction.Operands[1] == 1))
            {
                if (!callers.TryGetValue(call.Operands[0], out List<Procedure>? list))
                {
                    list = [];
                    callers[call.Operands[0]] = list;
                }

                list.Add(caller);
            }
        }

        for (bool found = true; found;)
        {
            found = false;
            foreach (Procedure segment in _procedures.Where(procedure => procedure.Parent is null && procedure.IsSegmentProcedure && procedure.Level >= 2))
            {
                foreach (Procedure caller in callers.GetValueOrDefault(segment.Segment.Number) ?? [])
                {
                    Procedure? outer = caller;
                    while (outer is not null && outer.Level > segment.Level - 1 && outer != segment)
                    {
                        outer = outer.Parent;
                    }

                    if (outer is null || outer == segment || outer.Level != segment.Level - 1) { continue; }

                    segment.Parent = outer;
                    found = true;
                    break;
                }
            }
        }

        foreach (Procedure lost in _procedures.Where(procedure => procedure.Parent is null && procedure.IsSegmentProcedure && procedure.Level >= 2))
        {
            Warn($"No call shows which procedure {lost} is declared in; it is put in the program's.");
        }
    }

    // A procedure beside a segment's procedure 1, at its level: a unit's.
    private static bool IsUnitProcedure(PascalProcedure code) => code.Index != 1 && (code.IsNative || code.LexicalLevel == 1);

    // Whether a segment holds the program: a p-code procedure 1 at the outer level. The Linker marks a segment it links
    // assembled procedures into as the machine's (FORMATTER's is M6502), so the machine type does not say.
    private static bool IsProgram(PascalSegment segment) => segment.Code.Length > 0
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
