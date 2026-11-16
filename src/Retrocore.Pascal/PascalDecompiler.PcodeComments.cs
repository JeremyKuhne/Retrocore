// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Pascal;

public sealed partial class PascalDecompiler
{
    // The longest a line of p-code comments runs to, its indentation included.
    private const int PcodeLineWidth = 110;

    // The longest an instruction is written in a p-code comment: a CASE's table or a long constant is cut.
    private const int PcodeInstructionWidth = 48;

    // The index of the procedure's next p-code not yet written in a comment, with PcodeComments.
    private int _pcodeNext;

    // The last p-code of a statement's own code before its statements: an IF's or WHILE's test, a FOR's start
    // and test, a CASE's selector, a WITH's record; a statement with none in it, all its code.
    private static int? PcodeHead(Statement statement)
    {
        if (statement is LabelStatement or OptionStatement) { return null; }

        int? first = Nested(statement).Select(FirstPcode).Min();
        return first is { } start ? start - 1 : LastPcode(statement);
    }

    // The statements a statement holds.
    private static IEnumerable<Statement> Nested(Statement statement) => statement switch
    {
        IfStatement branch => branch.Else is null ? branch.Then : [.. branch.Then, .. branch.Else],
        WhileStatement loop => loop.Body,
        RepeatStatement loop => loop.Body,
        ForStatement loop => loop.Body,
        WithStatement with => with.Body,
        CaseStatement choice => choice.Arms.SelectMany(arm => arm.Body),
        _ => []
    };

    // The first p-code of a statement's code, or of the statements it holds where it has no span of its own, as a
    // WITH, which the decoder makes from the statements in it.
    private static int? FirstPcode(Statement statement) =>
        statement.Start ?? Nested(statement).Select(FirstPcode).Min();

    // The last p-code of a statement's code, or of the statements it holds.
    private static int? LastPcode(Statement statement) =>
        statement.End ?? Nested(statement).Select(LastPcode).Max();

    // Writes the procedure's p-code up to an offset that no comment has had yet, as {...} comments.
    private void PcodeLines(Procedure procedure, int? upTo, List<string> lines)
    {
        if (!_options.PcodeComments || upTo is not { } last) { return; }

        IReadOnlyList<PcodeInstruction> code = procedure.Instructions;
        List<string> texts = [];
        while (_pcodeNext < code.Count && code[_pcodeNext].Offset <= last)
        {
            texts.Add(PcodeText(code[_pcodeNext]));
            _pcodeNext++;
        }

        if (texts.Count == 0) { return; }

        int width = Math.Max(40, PcodeLineWidth - (_indent * 2) - 2);
        string line = "";
        foreach (string text in texts)
        {
            if (line.Length > 0 && line.Length + text.Length + 2 > width)
            {
                lines.Add(Indented($"{{{line}}}"));
                line = "";
            }

            line = line.Length == 0 ? text : $"{line}; {text}";
        }

        lines.Add(Indented($"{{{line}}}"));
    }

    // A line of p-code comments, which a semicolon goes before, after the statement's own last line.
    private static bool IsPcodeComment(string line)
    {
        string text = line.TrimStart();
        return text.StartsWith('{') && !text.StartsWith("{$", StringComparison.Ordinal);
    }

    // The p-code after a procedure's last statement, such as its return, above its END.
    private void PcodeTail(Procedure procedure)
    {
        if (!_options.PcodeComments || procedure.Instructions.Count == 0) { return; }

        List<string> lines = [];
        _indent++;
        PcodeLines(procedure, procedure.Instructions[^1].Offset, lines);
        _indent--;
        foreach (string line in lines) { _source.Append(line); }
    }

    // An instruction as a comment has it: without a blank after a comma but in a string, cut where long, and with
    // no brace that would end the comment.
    private static string PcodeText(PcodeInstruction instruction)
    {
        string text = PcodeDisassembler.Format(instruction);
        if (instruction.Opcode.Operands != PcodeOperands.String)
        {
            text = text.Replace(", ", ",", StringComparison.Ordinal);
        }

        if (text.Length > PcodeInstructionWidth)
        {
            text = string.Concat(text.AsSpan(0, PcodeInstructionWidth - 3), "...");
        }

        return text.Replace('}', ')').Replace('{', '(');
    }
}
