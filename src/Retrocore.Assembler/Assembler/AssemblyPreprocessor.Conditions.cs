// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Assembler;

internal sealed partial class AssemblyPreprocessor
{
    // An error found expanding a conditional's line, before its condition could be read; reported, as false, where
    // the condition is tested, so the conditional still opens and its .else and .endif stay matched.
    private string? _conditionFailure;

    private bool ConditionalDirective(string operation, string operand, AssemblyLocation location, int floor, AssemblyDialect dialect)
    {
        try
        {
            return ConditionalDirectiveText(operation, operand, location, floor, dialect);
        }
        finally
        {
            // An ambiguity or failure the line's expansion found is for this line's condition only.
            _conditionAmbiguity = null;
            _conditionFailure = null;
        }
    }

    /// <summary>
    ///  Reports an error that stopped a line's expansion, keeping a conditional on that line in the nesting.
    /// </summary>
    /// <param name="message">The error.</param>
    /// <param name="line">The line, before expansion.</param>
    /// <param name="floor">The conditional depth this source or macro body opened at.</param>
    /// <remarks>
    ///  <para>
    ///   A function in a condition, such as <c>.definedmacro(1+2)</c>, fails while the whole line is expanded,
    ///   before the condition is read. The conditional is still opened, or continued, and treated as false, as
    ///   for any condition that cannot be read; its error is reported where the condition is tested, so an
    ///   <c>.elseif</c> after a taken branch, which is not tested, reports nothing, as in ca65. A failing operand
    ///   of <c>.else</c> or <c>.endif</c> is reported, and the branch still changes or closes. Without this, the
    ///   conditional's <c>.endif</c> would be reported as unexpected too.
    ///  </para>
    /// </remarks>
    private void ExpansionFailure(string message, Line line, int floor)
    {
        // The keyword may come from a text definition, so the line is read with its definitions expanded.
        string text = AssemblySyntax.AsString(line.Text);
        try
        {
            text = ExpandCa65Definitions(text);
        }
        catch (Exception exception) when (exception is AssemblyError or OverflowException)
        {
            // The failure being reported may be this expansion's; the line is then read as written.
        }

        Split(text, out _, out ReadOnlySpan<char> operationText, out ReadOnlySpan<char> operandText);
        string operation = operationText.ToString().ToUpperInvariant();
        bool active = _conditions.Count == 0 || _conditions[^1].Active;
        if (operation is ".ELSE" or ".ENDIF")
        {
            if (active) { Error(message, line.Location); }
            ConditionalDirective(operation, "", line.Location, floor, line.Dialect);
            return;
        }

        if (operation is ".IF" or ".ELSEIF" or ".IFDEF" or ".IFNDEF" or ".IFBLANK" || IsCa65Condition(operation))
        {
            _conditionFailure = message;
            ConditionalDirective(operation, operandText.ToString(), line.Location, floor, line.Dialect);
            return;
        }

        if (active) { Error(message, line.Location); }
    }

    private bool ConditionalDirectiveText(string operation, string operand, AssemblyLocation location, int floor, AssemblyDialect dialect)
    {
        if (operation is ".IF" or ".IFDEF" or ".IFNDEF" or ".IFBLANK"
            || (dialect is AssemblyDialect.Ca65 or AssemblyDialect.Native && IsCa65Condition(operation)))
        {
            bool parent = _conditions.Count == 0 || _conditions[^1].Active;
            bool active = parent && TestCondition(operation, operand, location, dialect);
            if (parent) { MarkLine(location, assembled: true); }
            _conditions.Add(new(location, parent, active, _visited));
            return true;
        }

        if (operation is not (".ELSE" or ".ELSEIF" or ".ENDIF")) { return false; }
        if (_conditions.Count <= floor)
        {
            if (_conditionFailure is { } failure) { Error(failure, location); }
            Error($"Unexpected {operation}.", location);
            return true;
        }

        Conditional current = _conditions[^1];

        // A closing or continuing directive belongs to the branch around the whole conditional, unless it carries a
        // label, which is defined only when the branch it closes was taken.
        if (current.Parent && !_labeledDirective) { MarkLine(location, assembled: true); }
        if (operation == ".ENDIF")
        {
            if (operand.Length != 0) { Error(".endif takes no operand.", location); }
            _conditions.RemoveAt(_conditions.Count - 1);
        }
        else if (current.ElseSeen)
        {
            Error("A conditional cannot continue after .else.", location);
        }
        else if (operation == ".ELSE")
        {
            if (operand.Length != 0) { Error(".else takes no operand.", location); }
            current.Active = current.Parent && !current.Taken;
            current.Taken |= current.Active;
            current.ElseSeen = true;
        }
        else
        {
            current.Active = current.Parent && !current.Taken && TestCondition(".IF", operand, location, dialect);
            current.Taken |= current.Active;
        }

        return true;
    }

    private bool TestCondition(string operation, string operand, AssemblyLocation location, AssemblyDialect dialect)
    {
        if (_conditionFailure is { } failure)
        {
            Error(failure, location);
            return false;
        }

        _nameAmbiguity = null;
        bool result = TestConditionText(operation, operand, location, dialect);
        _nameAmbiguity ??= _conditionAmbiguity;

        // A name that two definitions could mean (two used scopes, or two definitions giving a historical name) is an error where a condition tests it, as in code.
        if (_nameAmbiguity is { } ambiguity)
        {
            Error(ambiguity, location);
            _nameAmbiguity = null;
            return false;
        }

        return result;
    }

    private bool TestConditionText(string operation, string operand, AssemblyLocation location, AssemblyDialect dialect)
    {
        // Native sources share ca65's extra conditions; .ifdef keeps its native meaning (macros count).
        bool shared = dialect == AssemblyDialect.Ca65
            || (dialect == AssemblyDialect.Native && operation is not (".IFDEF" or ".IFNDEF" or ".IFBLANK"));

        if (shared)
        {
            try
            {
                return Ca65Condition(operation, operand);
            }
            catch (AssemblyError failure)
            {
                Error(failure.Message, location);
                return false;
            }
            catch (OverflowException)
            {
                Error("Conditional overflow.", location);
                return false;
            }
        }

        if (operation == ".IFBLANK") { return string.IsNullOrWhiteSpace(operand); }
        if (operation is ".IFDEF" or ".IFNDEF")
        {
            if (!AssemblySyntax.IsIdentifier(operand))
            {
                Error("A defined-name condition requires one identifier.", location);
                return false;
            }

            bool defined = _defined.Contains(ConstantName(operand)) || _macros.ContainsKey(operand);
            return operation == ".IFDEF" ? defined : !defined;
        }

        return Constant(operand, location, out long value) && value != 0;
    }

    private void CloseConditions(int depth, bool report = true)
    {
        while (_conditions.Count > depth)
        {
            Conditional condition = _conditions[^1];
            if (report) { Error("Unterminated conditional.", condition.Location, condition.Order); }
            _conditions.RemoveAt(_conditions.Count - 1);
        }
    }
}
