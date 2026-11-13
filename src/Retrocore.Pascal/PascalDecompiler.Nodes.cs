// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Pascal;

public sealed partial class PascalDecompiler
{
    // An operator, named by the p-code that does it.
    private enum Operator
    {
        Add,
        Subtract,
        Multiply,
        Divide,
        Modulo,
        RealAdd,
        RealSubtract,
        RealMultiply,
        RealDivide,
        And,
        Or,
        Union,
        Intersection,
        Difference,
        Negate,
        RealNegate,
        Absolute,
        RealAbsolute,
        Square,
        RealSquare,
        Not,
        Float,
        Equal,
        NotEqual,
        Less,
        LessEqual,
        Greater,
        GreaterEqual,
        In
    }

    // What a comparison compares: words, or with EQU and the others, reals, strings, booleans, sets, or arrays.
    private enum Comparand
    {
        Word,
        Real,
        String,
        Boolean,
        Set,
        Bytes,
        Words
    }

    /// <summary>
    ///  A value on the p-machine's stack.
    /// </summary>
    private abstract class Expr
    {
        // The words it takes on the stack.
        public virtual int Words => 1;

        public virtual TypeNode Type { get; } = new();
    }

    // A one-word constant: an integer, a character, a boolean, or an enumerated value.
    private sealed class Constant(int value) : Expr
    {
        public int Value { get; } = value;
    }

    // A constant of several words, from LDC: a real, or a set's words.
    private sealed class WordsConstant(ushort[] values) : Expr
    {
        public ushort[] Values { get; } = values;

        public override int Words => Values.Length;
    }

    // A string constant's address, from LSA.
    private sealed class StringConstant(byte[] characters) : Expr
    {
        public byte[] Characters { get; } = characters;
    }

    // A packed array constant's address, from LPA.
    private sealed class PackedConstant(byte[] bytes) : Expr
    {
        public byte[] Bytes { get; } = bytes;
    }

    private sealed class Nil : Expr;

    // A designator's value.
    private sealed class Load(Designator designator, int words) : Expr
    {
        public Designator Designator { get; } = designator;

        public override int Words { get; } = words;

        public override TypeNode Type => Designator.Type;
    }

    // A designator's address.
    private sealed class Address(Designator designator) : Expr
    {
        public Designator Designator { get; } = designator;

        public override TypeNode Type => Designator.Type;
    }

    // A byte's address: a base and an index, two words, from IXS or a packed array of bytes.
    private sealed class ByteAddress(Designator designator) : Expr
    {
        public Designator Designator { get; } = designator;

        public override int Words => 2;

        public override TypeNode Type => Designator.Type;
    }

    // A packed field's address: a word's address, its width and its first bit, three words, from IXP.
    private sealed class PackedAddress(Designator designator) : Expr
    {
        public Designator Designator { get; } = designator;

        public override int Words => 3;

        public override TypeNode Type => Designator.Type;
    }

    private sealed class Unary(Operator op, Expr operand) : Expr
    {
        public Operator Op { get; } = op;

        public Expr Operand { get; } = operand;

        public override int Words => Op is Operator.RealNegate or Operator.RealAbsolute or Operator.RealSquare or Operator.Float ? 2 : 1;
    }

    private sealed class Binary(Operator op, Expr left, Expr right) : Expr
    {
        public Operator Op { get; } = op;

        public Expr Left { get; } = left;

        public Expr Right { get; } = right;

        public override int Words => Op is Operator.RealAdd or Operator.RealSubtract or Operator.RealMultiply or Operator.RealDivide ? 2 : 1;
    }

    private sealed class Comparison(Operator op, Comparand comparand, Expr left, Expr right, int size) : Expr
    {
        public Operator Op { get; } = op;

        public Comparand Comparand { get; } = comparand;

        public Expr Left { get; } = left;

        public Expr Right { get; } = right;

        // An array comparison's size: bytes for a packed array of characters, words otherwise.
        public int Size { get; } = size;
    }

    // A value a range check bounds, from CHK.
    private sealed class Checked(Expr value, int low, int high) : Expr
    {
        public Expr Value { get; } = value;

        public int Low { get; } = low;

        public int High { get; } = high;

        public override int Words => Value.Words;

        public override TypeNode Type => Value.Type;
    }

    // A set: its elements and ranges, and a constant's bits, with or without its size word.
    private sealed class SetValue : Expr
    {
        // A set variable's or constant's value, or null for a set built here.
        public Expr? Value { get; set; }

        public List<(Expr Low, Expr? High)> Members { get; } = [];

        public Operator? Op { get; set; }

        public SetValue? Left { get; set; }

        public SetValue? Right { get; set; }

        // Its words once ADJ fixes them; 0 while it carries its size.
        public int Fixed { get; set; }

        public override int Words => Fixed == 0 ? 1 : Fixed;

        public override TypeNode Type { get; } = TypeNode.Of(TypeKind.Set);
    }

    // A call of a function: a user's, a unit's, or a built-in one.
    private sealed class Call(Callee callee, List<Expr> arguments, int words) : Expr
    {
        public Callee Callee { get; } = callee;

        public List<Expr> Arguments { get; } = arguments;

        public override int Words { get; } = words;

        public override TypeNode Type { get; } = callee.ResultType ?? new TypeNode();
    }

    // A string expression the compiler builds in a temporary: CONCAT or COPY.
    private sealed class StringFunction(string name, List<Expr> arguments) : Expr
    {
        public string Name { get; } = name;

        public List<Expr> Arguments { get; } = arguments;

        public override TypeNode Type { get; } = TypeNode.Of(TypeKind.String);
    }

    // A word a built-in takes as written, such as CLOSE's LOCK.
    private sealed class Keyword(string text) : Expr
    {
        public string Text { get; } = text;
    }

    // A value WRITE writes, with the system procedure that writes it: 13 an integer, 17 a character, 19 a string,
    // 20 a packed array of characters, 0 a real.
    private sealed class Written(Expr value, int procedure) : Expr
    {
        public Expr Value { get; } = value;

        public int Procedure { get; } = procedure;

        public override int Words => Value.Words;

        public override TypeNode Type => Value.Type;
    }

    /// <summary>
    ///  What a call calls: a procedure in the code file, a unit's, or a built-in.
    /// </summary>
    private sealed class Callee
    {
        public Procedure? Procedure { get; init; }

        public PascalUnit? Unit { get; init; }

        public PascalUnitProcedure? UnitProcedure { get; init; }

        // A built-in procedure or function, such as WRITE or LENGTH.
        public string? Builtin { get; init; }

        // A segment and procedure number the decompiler could not name.
        public int Segment { get; init; }

        public int Number { get; init; }

        public TypeNode? ResultType { get; init; }
    }

    /// <summary>
    ///  Something with an address: a variable, or a part of one.
    /// </summary>
    private abstract class Designator
    {
        public abstract TypeNode Type { get; }
    }

    private sealed class VariableDesignator(Variable variable) : Designator
    {
        public Variable Variable { get; } = variable;

        public override TypeNode Type => Variable.Type;
    }

    private sealed class FieldDesignator(Designator record, int offset) : Designator
    {
        public Designator Record { get; } = record;

        public int Offset { get; } = offset;

        public override TypeNode Type { get; } = record.Type.Field(offset);
    }

    private sealed class PackedFieldDesignator(Designator record, int word, int bit, int width) : Designator
    {
        public Designator Record { get; } = record;

        public int Word { get; } = word;

        public int Bit { get; } = bit;

        public int Width { get; } = width;

        public override TypeNode Type { get; } = record.Type.PackedField(word, bit, width);
    }

    // An array's element: by words (IXA), packed (IXP), or by byte (LDB and STB).
    private sealed class IndexDesignator : Designator
    {
        public IndexDesignator(Designator array, Expr index, int? low, int? high, TypeNode element)
        {
            Array = array;
            Index = index;
            Low = low;
            High = high;
            Type = element;
        }

        public Designator Array { get; }

        public Expr Index { get; }

        public int? Low { get; }

        public int? High { get; }

        // Whether the code says nothing of range checking, as for MOVELEFT's byte offset; otherwise a range check
        // (CHK) gives the high bound, and its absence means range checking was off.
        public bool Neutral { get; init; }

        public override TypeNode Type { get; }
    }

    // A string's character, from IXS, or its length, at byte 0.
    private sealed class StringIndexDesignator(Designator text, Expr index) : Designator
    {
        public Designator Text { get; } = text;

        public Expr Index { get; } = index;

        public override TypeNode Type { get; } = TypeNode.Scalar(ScalarKind.Char);
    }

    // A string's length: its byte 0.
    private sealed class LengthDesignator(Designator text) : Designator
    {
        public Designator Text { get; } = text;

        public override TypeNode Type { get; } = TypeNode.Scalar(ScalarKind.Integer);
    }

    // What a pointer points to; for a VAR parameter, what it stands for.
    private sealed class Dereference(Expr pointer) : Designator
    {
        public Expr Pointer { get; } = pointer;

        public override TypeNode Type { get; } = pointer.Type.Target();
    }

    // A file's window, F^.
    private sealed class WindowDesignator(Designator file) : Designator
    {
        public Designator File { get; } = file;

        public override TypeNode Type { get; } = file.Type.Find().Element ?? new TypeNode();
    }

    // A function's result, its name inside it.
    private sealed class ResultDesignator(Procedure procedure) : Designator
    {
        public Procedure Procedure { get; } = procedure;

        public override TypeNode Type => Procedure.ResultType;
    }

    /// <summary>
    ///  A statement, at its first p-code's offset.
    /// </summary>
    private abstract class Statement
    {
        public int Offset { get; set; }
    }

    private sealed class Assignment(Designator target, Expr value, bool block = false) : Statement
    {
        public Designator Target { get; } = target;

        public Expr Value { get; } = value;

        // Whether it copies a block, a string's (SAS) or a record's or array's (MOV), as a value parameter's copy does.
        public bool Block { get; } = block;
    }

    // A call of a procedure, or a built-in one such as WRITE, whose arguments may have widths.
    private sealed class CallStatement(Callee callee, List<Argument> arguments) : Statement
    {
        public Callee Callee { get; } = callee;

        public List<Argument> Arguments { get; } = arguments;

        // An I/O statement whose result is checked (CSP IOC after it).
        public bool Checked { get; set; }
    }

    // An argument: a value with a WRITE's width and decimals, or a file.
    private sealed record Argument(Expr Value, Expr? Width = null, Expr? Decimals = null);

    private sealed class IfStatement(Expr condition, List<Statement> then, List<Statement>? otherwise) : Statement
    {
        public Expr Condition { get; } = condition;

        public List<Statement> Then { get; } = then;

        public List<Statement>? Else { get; } = otherwise;
    }

    private sealed class WhileStatement(Expr condition, List<Statement> body) : Statement
    {
        public Expr Condition { get; } = condition;

        public List<Statement> Body { get; } = body;
    }

    private sealed class RepeatStatement(List<Statement> body, Expr condition) : Statement
    {
        public List<Statement> Body { get; } = body;

        public Expr Condition { get; } = condition;
    }

    private sealed class ForStatement(Designator control, Expr from, Expr to, bool down, List<Statement> body) : Statement
    {
        public Designator Control { get; } = control;

        public Expr From { get; } = from;

        public Expr To { get; } = to;

        public bool Down { get; } = down;

        public List<Statement> Body { get; } = body;
    }

    private sealed class CaseStatement(Expr selector, List<(List<int> Labels, List<Statement> Body)> arms) : Statement
    {
        public Expr Selector { get; } = selector;

        public List<(List<int> Labels, List<Statement> Body)> Arms { get; } = arms;
    }

    private sealed class WithStatement(Designator record, Variable temporary, List<Statement> body) : Statement
    {
        public Designator Record { get; } = record;

        public Variable Temporary { get; } = temporary;

        public List<Statement> Body { get; } = body;
    }

    private sealed class GotoStatement(int target) : Statement
    {
        public int Target { get; } = target;
    }

    private sealed class LabelStatement(int target) : Statement
    {
        public int Target { get; } = target;
    }

    // EXIT(procedure), naming a procedure by its segment and number.
    private sealed class ExitStatement(int segment, int procedure) : Statement
    {
        public int Segment { get; } = segment;

        public int Procedure { get; } = procedure;
    }

    // Code the decompiler could not express, as a comment.
    private sealed class Unsupported(string text) : Statement
    {
        public string Text { get; } = text;
    }

    // Leaves the range checks or I/O checks on or off from here: (*$R-*) and the like.
    private sealed class OptionStatement(char option, bool on) : Statement
    {
        public char Option { get; } = option;

        public bool On { get; } = on;
    }
}
