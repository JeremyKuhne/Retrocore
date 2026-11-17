// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Pascal;

public sealed partial class PascalDecompiler
{
    /// <summary>
    ///  An operator, named by the p-code that does it.
    /// </summary>
    private enum Operator
    {
        /// <summary>
        ///  Integer addition, ADI.
        /// </summary>
        Add,

        /// <summary>
        ///  Integer subtraction, SBI.
        /// </summary>
        Subtract,

        /// <summary>
        ///  Integer multiplication, MPI.
        /// </summary>
        Multiply,

        /// <summary>
        ///  Integer division, DVI.
        /// </summary>
        Divide,

        /// <summary>
        ///  Integer remainder, MODI.
        /// </summary>
        Modulo,

        /// <summary>
        ///  Real addition, ADR.
        /// </summary>
        RealAdd,

        /// <summary>
        ///  Real subtraction, SBR.
        /// </summary>
        RealSubtract,

        /// <summary>
        ///  Real multiplication, MPR.
        /// </summary>
        RealMultiply,

        /// <summary>
        ///  Real division, DVR.
        /// </summary>
        RealDivide,

        /// <summary>
        ///  Logical and, LAND.
        /// </summary>
        And,

        /// <summary>
        ///  Logical or, LOR.
        /// </summary>
        Or,

        /// <summary>
        ///  Set union, UNI.
        /// </summary>
        Union,

        /// <summary>
        ///  Set intersection, INT.
        /// </summary>
        Intersection,

        /// <summary>
        ///  Set difference, DIF.
        /// </summary>
        Difference,

        /// <summary>
        ///  Integer negation, NGI.
        /// </summary>
        Negate,

        /// <summary>
        ///  Real negation, NGR.
        /// </summary>
        RealNegate,

        /// <summary>
        ///  An integer's absolute value, ABI.
        /// </summary>
        Absolute,

        /// <summary>
        ///  A real's absolute value, ABR.
        /// </summary>
        RealAbsolute,

        /// <summary>
        ///  An integer's square, SQI.
        /// </summary>
        Square,

        /// <summary>
        ///  A real's square, SQR.
        /// </summary>
        RealSquare,

        /// <summary>
        ///  Logical not, LNOT.
        /// </summary>
        Not,

        /// <summary>
        ///  An integer made a real, FLT or FLO.
        /// </summary>
        Float,

        /// <summary>
        ///  Equal, EQU or EQUI.
        /// </summary>
        Equal,

        /// <summary>
        ///  Not equal, NEQ or NEQI.
        /// </summary>
        NotEqual,

        /// <summary>
        ///  Less than, LES or LESI.
        /// </summary>
        Less,

        /// <summary>
        ///  Less than or equal, LEQ or LEQI.
        /// </summary>
        LessEqual,

        /// <summary>
        ///  Greater than, GRT or GRTI.
        /// </summary>
        Greater,

        /// <summary>
        ///  Greater than or equal, GEQ or GEQI.
        /// </summary>
        GreaterEqual,

        /// <summary>
        ///  Set membership, INN.
        /// </summary>
        In
    }
}
