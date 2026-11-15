// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using System.Text;
using Retrocore.Media;

namespace Retrocore.Pascal;

public sealed partial class PascalDecompiler
{
    // Whether a procedure is in a unit of the program's own.
    private bool InUnit(Procedure procedure) => _unitSegments.Contains(procedure.Segment);

    // The units' segments, in the order the program's USES names them, which gives their numbers.
    private List<PascalSegment> UnitSegments() => [.. _unitSegments.OrderBy(segment => segment.Number)];

    // A unit's interface: its procedures, from 2, up to the last one called from outside it; the rest are its own.
    private List<Procedure> Interface(PascalSegment segment)
    {
        int last = 1;
        foreach (Procedure caller in _procedures.Where(procedure => procedure.Segment != segment))
        {
            Walk(caller.Body, statement => Called(statement is CallStatement call ? call.Callee : null), expression => Called(expression is Call call ? call.Callee : null));
        }

        return [.. _procedures
            .Where(procedure => procedure.Segment == segment && procedure.Number >= 2 && procedure.Number <= last)
            .OrderBy(procedure => procedure.Number)];

        void Called(Callee? callee)
        {
            if (callee?.Procedure is { } called && called.Segment == segment) { last = Math.Max(last, called.Number); }
        }
    }

    // The named types procedures declare their variables, parameters or results with, and those those types name.
    private HashSet<TypeNode> TypesOf(IEnumerable<Procedure> procedures, bool variables, bool signatures)
    {
        HashSet<TypeNode> types = [];
        foreach (Procedure procedure in procedures)
        {
            if (variables)
            {
                foreach (Variable variable in _declared[procedure.Frame]) { Reach(variable.Type, types); }
            }

            if (signatures)
            {
                foreach (Variable parameter in _parameters[procedure])
                {
                    Reach(parameter.Copy?.Type ?? (parameter.IsReference ? parameter.Type.Target() : parameter.Type), types);
                }

                if (procedure.IsFunction) { Reach(procedure.ResultType, types); }
            }
        }

        return types;
    }

    private static void Reach(TypeNode type, HashSet<TypeNode> types)
    {
        TypeNode root = type.Find();
        if (root.Name is not null && !types.Add(root)) { return; }

        IEnumerable<TypeNode> parts = root.Kind == TypeKind.Record
            ? [.. root.AllFields, .. root.PackedFields?.Values.Select(field => field.Type) ?? []]
            : root.Element is { } element ? [element] : [];

        foreach (TypeNode part in parts) { Reach(part, types); }
    }

    // The types the units' interfaces declare, which the program and the units take from them.
    private HashSet<TypeNode> InterfaceTypes() =>
        [.. UnitSegments().SelectMany(segment => TypesOf(Interface(segment), variables: false, signatures: true))];

    // Declares types, in the order their declarations need.
    private void Types(HashSet<TypeNode> types)
    {
        List<TypeNode> ordered = [.. Ordered().Where(types.Contains)];
        if (ordered.Count == 0) { return; }

        // Each record laid out first, which sizes the arrays of its words that the code shows no length of: the
        // declarations of those arrays, which come before, then have it.
        foreach (TypeNode type in ordered.Where(type => type.Find().Kind == TypeKind.Record))
        {
            _ = Declare(type, inline: false);
        }

        Line("TYPE");
        _indent++;
        foreach (TypeNode type in ordered) { Line($"{type.Name} = {Declare(type, inline: false)};"); }
        _indent--;
    }

    // Each unit's source: its interface's types and headings; then its implementation's types, its procedures, those
    // of its interface by name alone, and its initialization.
    private List<PascalDecompiledUnit> WriteUnits()
    {
        List<PascalDecompiledUnit> units = [];
        HashSet<TypeNode> shared = [];
        foreach (PascalSegment segment in UnitSegments())
        {
            _source = new StringBuilder();
            _constants.Clear();
            string name = segment.Name.Trim();
            List<Procedure> procedures = [.. _procedures.Where(procedure => procedure.Segment == segment)];
            Options(procedures);
            Procedure? initialization = procedures.FirstOrDefault(procedure => procedure.Number == 1);
            List<Procedure> exported = Interface(segment);
            List<Procedure> outer = [.. procedures.Where(procedure => procedure.Number >= 2 && procedure.Parent == _program)];
            List<Procedure> own = [.. outer.Where(procedure => !exported.Contains(procedure))];

            if (initialization is { } init && _declared[init.Frame].Count > 0)
            {
                Warn($"The unit {name} has variables of its own, which are not decompiled.");
            }

            Line($"UNIT {name};");
            Line("INTERFACE");
            _indent++;
            HashSet<TypeNode> interfaceTypes = TypesOf(exported, variables: false, signatures: true);
            interfaceTypes.ExceptWith(shared);
            Types(interfaceTypes);
            foreach (Procedure procedure in exported) { Line(Header(procedure, full: true)); }
            _indent--;

            Line("IMPLEMENTATION");
            _indent++;
            int constants = _source.Length;
            HashSet<TypeNode> ownTypes = TypesOf(procedures, variables: true, signatures: false);
            ownTypes.UnionWith(TypesOf(own, variables: false, signatures: true));
            ownTypes.ExceptWith(interfaceTypes);
            ownTypes.ExceptWith(shared);
            Types(ownTypes);
            shared.UnionWith(interfaceTypes);

            // An assembled procedure the interface declares is EXTERNAL here; the others in the order of their code.
            foreach (Procedure procedure in exported.Where(procedure => procedure.Code.IsNative))
            {
                WriteProcedure(procedure, forwarded: true);
            }

            Ordinary(outer, [.. exported]);
            _indent--;

            if (initialization is { Body.Count: > 0 } body)
            {
                Line("BEGIN");
                Statements(body, body.Body);
            }

            Line("END.");
            Alignment([segment]);
            if (_constants.Count > 0)
            {
                _source.Insert(constants, $"  CONST\n{string.Concat(_constants.Select(constant => $"    {constant.Value} = {constant.Key.ToString(System.Globalization.CultureInfo.InvariantCulture)};\n"))}");
            }

            units.Add(new PascalDecompiledUnit(name, segment.Number, _source.ToString()));
        }

        return units;
    }
}
