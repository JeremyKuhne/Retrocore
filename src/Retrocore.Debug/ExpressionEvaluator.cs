// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Isa;
using System.Globalization;
using System.Text.RegularExpressions;

namespace Retrocore.Debug;

/// <summary>
///  Evaluates debugger arithmetic, labels, register names, and side-effect-free memory expressions.
/// </summary>
internal sealed partial class ExpressionEvaluator
{
    private readonly IDebugTarget _target;
    private readonly DebugInfo _symbols;
    private readonly DebugFrame _registers;
    private readonly string[] _tokens;
    private int _position;

    // The hints file's space names are looked for in: the bank a reference or brackets name, else the frame's own.
    private string _space;

    /// <summary>
    ///  Creates an evaluator.
    /// </summary>
    /// <param name="target">The stopped machine.</param>
    /// <param name="symbols">The session's debug modules, for labels.</param>
    /// <param name="expression">The expression.</param>
    /// <param name="registers">Optional suspended caller registers.</param>
    /// <param name="bank">The bank a reference named before the expression, whose hint names it reads first.</param>
    internal ExpressionEvaluator(
        IDebugTarget target,
        DebugInfo symbols,
        string expression,
        DebugFrame? registers = null,
        DebugMemoryBank? bank = null)
    {
        _target = target;
        _symbols = symbols;
        _registers = registers ?? target.Frame;
        _space = bank?.Name ?? OwnSpace(target);
        List<string> tokens = [];
        int consumed = 0;
        foreach (Match match in ExpressionTokens().Matches(expression))
        {
            if (match.Index != consumed) { throw new FormatException("Invalid expression token."); }
            tokens.Add(match.Groups[1].Value);
            consumed += match.Length;
        }

        if (expression[consumed..].Trim().Length != 0 || tokens.Count == 0)
        {
            throw new FormatException("Invalid or empty expression.");
        }

        _tokens = [.. tokens];
    }

    /// <summary>
    ///  Evaluates the complete expression.
    /// </summary>
    /// <returns>The integer result.</returns>
    internal long Evaluate()
    {
        long value = Parse(minimum: 0);
        return _position != _tokens.Length ? throw new FormatException("Unexpected expression suffix.") : value;
    }

    /// <summary>
    ///  The prefix that names memory as the machine's own CPU maps it now, as no prefix does except in a
    ///  coprocessor's frame, where no prefix is the coprocessor's memory.
    /// </summary>
    internal const string CpuPrefix = "cpu";

    /// <summary>
    ///  Evaluates an address that may name a memory bank first, such as <c>aux:$0400</c>.
    /// </summary>
    /// <param name="bank">The bank it names, or null for memory as the CPU maps it now.</param>
    /// <returns>The address.</returns>
    /// <exception cref="FormatException">The expression or the bank is not valid.</exception>
    internal long EvaluateReference(out DebugMemoryBank? bank) => EvaluateReference(out bank, out _);

    /// <summary>
    ///  Evaluates an address that may name a memory bank first, such as <c>aux:$0400</c>, or the machine's CPU, as
    ///  <c>cpu:$0400</c> does.
    /// </summary>
    /// <param name="bank">The bank it names, or null for memory as a CPU maps it now.</param>
    /// <param name="cpu">Whether it names the machine's own CPU with <c>cpu:</c>.</param>
    /// <returns>The address.</returns>
    /// <exception cref="FormatException">The expression or the bank is not valid.</exception>
    internal long EvaluateReference(out DebugMemoryBank? bank, out bool cpu)
    {
        bank = BankPrefix(out cpu);
        _space = Space(bank, cpu, _space);
        return Evaluate();
    }

    // A coprocessor's memory is its bank's space in the hints file; the machine CPU's is the empty one.
    private static string OwnSpace(IDebugTarget target) => target is SoftCardDebugTarget softCard ? softCard.Bank.Name : "";

    private static string Space(DebugMemoryBank? bank, bool cpu, string outer) => bank?.Name ?? (cpu ? "" : outer);

    /// <summary>
    ///  Splits a bank prefix from a memory reference, such as <c>aux</c> from <c>aux:$0400</c>.
    /// </summary>
    /// <param name="target">The machine, whose banks the prefix names.</param>
    /// <param name="reference">The reference.</param>
    /// <param name="bank">The bank, or null when the reference names none.</param>
    /// <returns>The rest of the reference.</returns>
    /// <exception cref="FormatException">The prefix names no bank of this machine.</exception>
    internal static string SplitBank(IDebugTarget target, string reference, out DebugMemoryBank? bank)
    {
        bank = null;
        Match match = BankReference().Match(reference);
        if (!match.Success) { return reference; }

        // A memory reference with no bank is already the machine's CPU's.
        if (IsCpu(match.Groups[1].Value)) { return match.Groups[2].Value; }
        bank = FindBank(target, match.Groups[1].Value);
        return match.Groups[2].Value;
    }

    private static bool IsCpu(string name) => string.Equals(name, CpuPrefix, StringComparison.OrdinalIgnoreCase);

    private DebugMemoryBank? BankPrefix(out bool cpu)
    {
        cpu = false;
        if (_position == _tokens.Length || !_tokens[_position].EndsWith(':')) { return null; }
        string name = _tokens[_position++][..^1];
        if (IsCpu(name))
        {
            cpu = true;
            return null;
        }

        return FindBank(_target, name);
    }

    private static DebugMemoryBank FindBank(IDebugTarget target, string name) =>
        target.Banks.FirstOrDefault(bank => string.Equals(bank.Name, name, StringComparison.OrdinalIgnoreCase))
            ?? throw new FormatException(target.Banks.Count == 0
                ? $"This machine has no memory banks; '{name}:' names none."
                : $"Unknown memory bank '{name}'; this machine has {string.Join(", ", target.Banks.Select(bank => bank.Name))}.");

    private byte Peek(DebugMemoryBank? bank, bool cpu, ushort address) => bank is null
        ? (cpu ? _target.Machine : _target).Peek(address)
        : bank.Peek(address) ?? throw new FormatException($"{bank.Label} has no byte at ${address:X4}.");

    private long Parse(int minimum)
    {
        long left = Primary();
        while (_position < _tokens.Length)
        {
            string operation = _tokens[_position];
            int precedence = Precedence(operation);
            if (precedence < minimum) { break; }
            _position++;
            long right = Parse(precedence + 1);
            left = operation switch
            {
                "+" => left + right, "-" => left - right, "*" => left * right,
                "/" => right != 0 ? left / right : throw new DivideByZeroException(),
                "%" => right != 0 ? left % right : throw new DivideByZeroException(),
                "&" => left & right, "|" => left | right, "^" => left ^ right,
                "<<" => left << (int)right, ">>" => left >> (int)right,
                "==" => left == right ? 1 : 0, "!=" => left != right ? 1 : 0,
                "<" => left < right ? 1 : 0, ">" => left > right ? 1 : 0,
                "<=" => left <= right ? 1 : 0, ">=" => left >= right ? 1 : 0,
                "&&" => left != 0 && right != 0 ? 1 : 0, "||" => left != 0 || right != 0 ? 1 : 0,
                _ => throw new FormatException("Unsupported expression operator.")
            };
        }

        return left;
    }

    private long Primary()
    {
        if (_position == _tokens.Length) { throw new FormatException("Missing expression operand."); }
        string token = _tokens[_position++];
        if (token == "(")
        {
            long value = Parse(minimum: 0);
            Expect(")");
            return value;
        }

        if (token == "[")
        {
            DebugMemoryBank? bank = BankPrefix(out bool cpu);
            string outer = _space;
            _space = Space(bank, cpu, outer);
            ushort address = checked((ushort)Parse(minimum: 0));
            _space = outer;
            Expect("]");
            long value = Peek(bank, cpu, address);
            if (_position < _tokens.Length && _tokens[_position] == ".w")
            {
                // A word in its CPU's byte order: low byte first but on the 6809.
                _position++;
                long next = Peek(bank, cpu, (ushort)(address + 1));
                InstructionSet isa = bank?.InstructionSet ?? (cpu ? _target.Machine : _target).InstructionSet;
                value = isa.Endianness == Endianness.Big ? (value << 8) | next : value | (next << 8);
            }

            return value;
        }

        if (token.EndsWith(':'))
        {
            throw new FormatException($"A memory bank such as '{token}' goes inside brackets, as [{token}$0400].");
        }

        if (token is "-" or "+" or "~" or "!")
        {
            long value = Primary();
            return token switch { "-" => -value, "+" => value, "~" => ~value, _ => value == 0 ? 1 : 0 };
        }

        if (token.StartsWith('$') || token.StartsWith("0x", StringComparison.OrdinalIgnoreCase))
        {
            return long.Parse(token[(token[0] == '$' ? 1 : 2)..], NumberStyles.HexNumber, CultureInfo.InvariantCulture);
        }

        if (char.IsDigit(token[0])) { return long.Parse(token, CultureInfo.InvariantCulture); }
        return _target.Registers.Value(_registers, token) ?? _symbols.Resolve(token, _target, _space);
    }

    private void Expect(string token)
    {
        if (_position == _tokens.Length || _tokens[_position++] != token)
        {
            throw new FormatException($"Expected '{token}'.");
        }
    }

    private static int Precedence(string operation) => operation switch
    {
        "||" => 0, "&&" => 1, "|" => 2, "^" => 3, "&" => 4,
        "==" or "!=" => 5, "<" or ">" or "<=" or ">=" => 6,
        "<<" or ">>" => 7, "+" or "-" => 8, "*" or "/" or "%" => 9, _ => -1
    };

    [GeneratedRegex(@"^\s*([a-zA-Z][a-zA-Z0-9]*):(?!:)(.*)$", RegexOptions.Singleline)]
    private static partial Regex BankReference();

    [GeneratedRegex("""\s*(\$[0-9a-fA-F]+|0x[0-9a-fA-F]+|\d+|[a-zA-Z][a-zA-Z0-9]*:(?!:)|[a-zA-Z_@][a-zA-Z_0-9@]*(?:::[a-zA-Z_@][a-zA-Z_0-9@]*)*|\.w|==|!=|<=|>=|&&|\|\||<<|>>|[+\-*/%&|^!~()<>\[\]])""")]
    private static partial Regex ExpressionTokens();
}
