// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Assembler;

internal sealed partial class AssemblyPreprocessor
{
    private bool ConditionalDirective(string operation, string operand, AssemblyLocation location, int floor, AssemblyDialect dialect)
    {
        if (operation is ".IF" or ".IFDEF" or ".IFNDEF" or ".IFBLANK"
            || (dialect is AssemblyDialect.Ca65 or AssemblyDialect.Native && IsCa65Condition(operation)))
        {
            bool parent = _conditions.Count == 0 || _conditions[^1].Active;
            bool active = parent && TestCondition(operation, operand, location, dialect);
            _conditions.Add(new(location, parent, active, _visited));
            return true;
        }

        if (operation is not (".ELSE" or ".ELSEIF" or ".ENDIF")) { return false; }
        if (_conditions.Count <= floor)
        {
            Error($"Unexpected {operation}.", location);
            return true;
        }

        Conditional current = _conditions[^1];
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
