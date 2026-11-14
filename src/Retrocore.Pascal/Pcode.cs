// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Pascal;

/// <summary>
///  The p-code of UCSD Pascal II.1, as Apple Pascal 1.1 and later and Apple III Pascal run it.
/// </summary>
/// <remarks>
///  <para>
///   Opcodes 0-127 load themselves as constants (<c>SLDC</c>), and 216-255 are short forms of loading a local, a
///   global or through a pointer. Apple Pascal adds <c>LDE</c>, <c>LAE</c> and <c>STE</c> for intrinsic units' data.
///  </para>
/// </remarks>
public static class Pcode
{
    /// <summary>
    ///  The opcode of <c>CSP</c>: call a standard procedure.
    /// </summary>
    public const byte Csp = 158;

    /// <summary>
    ///  The opcode of <c>FJP</c>: jump if false.
    /// </summary>
    public const byte Fjp = 161;

    /// <summary>
    ///  The opcode of <c>XJP</c>: case jump.
    /// </summary>
    public const byte Xjp = 172;

    /// <summary>
    ///  The opcode of <c>LDC</c>: load a multiword constant, from the next word boundary.
    /// </summary>
    public const byte Ldc = 179;

    /// <summary>
    ///  The opcode of <c>RNP</c>: return from a procedure, leaving a function's result.
    /// </summary>
    public const byte Rnp = 173;

    /// <summary>
    ///  The opcode of <c>CIP</c>: call an intermediate procedure.
    /// </summary>
    public const byte Cip = 174;

    /// <summary>
    ///  The opcode of <c>UJP</c>: jump.
    /// </summary>
    public const byte Ujp = 185;

    /// <summary>
    ///  The opcode of <c>RBP</c>: return from a base procedure.
    /// </summary>
    public const byte Rbp = 193;

    /// <summary>
    ///  The opcode of <c>CBP</c>: call a base procedure.
    /// </summary>
    public const byte Cbp = 194;

    /// <summary>
    ///  The opcode of <c>CXP</c>: call a procedure in another segment.
    /// </summary>
    public const byte Cxp = 205;

    /// <summary>
    ///  The opcode of <c>CLP</c>: call a local procedure.
    /// </summary>
    public const byte Clp = 206;

    /// <summary>
    ///  The opcode of <c>CGP</c>: call a global procedure.
    /// </summary>
    public const byte Cgp = 207;

    /// <summary>
    ///  The opcode of <c>EFJ</c>: jump if not equal.
    /// </summary>
    public const byte Efj = 211;

    /// <summary>
    ///  The opcode of <c>NFJ</c>: jump if equal.
    /// </summary>
    public const byte Nfj = 212;

    /// <summary>
    ///  The opcode of <c>BPT</c>: breakpoint.
    /// </summary>
    public const byte Bpt = 213;

    /// <summary>
    ///  The opcode of <c>XIT</c>: exit the system.
    /// </summary>
    public const byte Xit = 214;

    private static readonly PcodeOpcode[] s_opcodes =
    [
        new(0, "SLDC", PcodeOperands.None, "load the constant 0"),
        new(1, "SLDC", PcodeOperands.None, "load the constant 1"),
        new(2, "SLDC", PcodeOperands.None, "load the constant 2"),
        new(3, "SLDC", PcodeOperands.None, "load the constant 3"),
        new(4, "SLDC", PcodeOperands.None, "load the constant 4"),
        new(5, "SLDC", PcodeOperands.None, "load the constant 5"),
        new(6, "SLDC", PcodeOperands.None, "load the constant 6"),
        new(7, "SLDC", PcodeOperands.None, "load the constant 7"),
        new(8, "SLDC", PcodeOperands.None, "load the constant 8"),
        new(9, "SLDC", PcodeOperands.None, "load the constant 9"),
        new(10, "SLDC", PcodeOperands.None, "load the constant 10"),
        new(11, "SLDC", PcodeOperands.None, "load the constant 11"),
        new(12, "SLDC", PcodeOperands.None, "load the constant 12"),
        new(13, "SLDC", PcodeOperands.None, "load the constant 13"),
        new(14, "SLDC", PcodeOperands.None, "load the constant 14"),
        new(15, "SLDC", PcodeOperands.None, "load the constant 15"),
        new(16, "SLDC", PcodeOperands.None, "load the constant 16"),
        new(17, "SLDC", PcodeOperands.None, "load the constant 17"),
        new(18, "SLDC", PcodeOperands.None, "load the constant 18"),
        new(19, "SLDC", PcodeOperands.None, "load the constant 19"),
        new(20, "SLDC", PcodeOperands.None, "load the constant 20"),
        new(21, "SLDC", PcodeOperands.None, "load the constant 21"),
        new(22, "SLDC", PcodeOperands.None, "load the constant 22"),
        new(23, "SLDC", PcodeOperands.None, "load the constant 23"),
        new(24, "SLDC", PcodeOperands.None, "load the constant 24"),
        new(25, "SLDC", PcodeOperands.None, "load the constant 25"),
        new(26, "SLDC", PcodeOperands.None, "load the constant 26"),
        new(27, "SLDC", PcodeOperands.None, "load the constant 27"),
        new(28, "SLDC", PcodeOperands.None, "load the constant 28"),
        new(29, "SLDC", PcodeOperands.None, "load the constant 29"),
        new(30, "SLDC", PcodeOperands.None, "load the constant 30"),
        new(31, "SLDC", PcodeOperands.None, "load the constant 31"),
        new(32, "SLDC", PcodeOperands.None, "load the constant 32"),
        new(33, "SLDC", PcodeOperands.None, "load the constant 33"),
        new(34, "SLDC", PcodeOperands.None, "load the constant 34"),
        new(35, "SLDC", PcodeOperands.None, "load the constant 35"),
        new(36, "SLDC", PcodeOperands.None, "load the constant 36"),
        new(37, "SLDC", PcodeOperands.None, "load the constant 37"),
        new(38, "SLDC", PcodeOperands.None, "load the constant 38"),
        new(39, "SLDC", PcodeOperands.None, "load the constant 39"),
        new(40, "SLDC", PcodeOperands.None, "load the constant 40"),
        new(41, "SLDC", PcodeOperands.None, "load the constant 41"),
        new(42, "SLDC", PcodeOperands.None, "load the constant 42"),
        new(43, "SLDC", PcodeOperands.None, "load the constant 43"),
        new(44, "SLDC", PcodeOperands.None, "load the constant 44"),
        new(45, "SLDC", PcodeOperands.None, "load the constant 45"),
        new(46, "SLDC", PcodeOperands.None, "load the constant 46"),
        new(47, "SLDC", PcodeOperands.None, "load the constant 47"),
        new(48, "SLDC", PcodeOperands.None, "load the constant 48"),
        new(49, "SLDC", PcodeOperands.None, "load the constant 49"),
        new(50, "SLDC", PcodeOperands.None, "load the constant 50"),
        new(51, "SLDC", PcodeOperands.None, "load the constant 51"),
        new(52, "SLDC", PcodeOperands.None, "load the constant 52"),
        new(53, "SLDC", PcodeOperands.None, "load the constant 53"),
        new(54, "SLDC", PcodeOperands.None, "load the constant 54"),
        new(55, "SLDC", PcodeOperands.None, "load the constant 55"),
        new(56, "SLDC", PcodeOperands.None, "load the constant 56"),
        new(57, "SLDC", PcodeOperands.None, "load the constant 57"),
        new(58, "SLDC", PcodeOperands.None, "load the constant 58"),
        new(59, "SLDC", PcodeOperands.None, "load the constant 59"),
        new(60, "SLDC", PcodeOperands.None, "load the constant 60"),
        new(61, "SLDC", PcodeOperands.None, "load the constant 61"),
        new(62, "SLDC", PcodeOperands.None, "load the constant 62"),
        new(63, "SLDC", PcodeOperands.None, "load the constant 63"),
        new(64, "SLDC", PcodeOperands.None, "load the constant 64"),
        new(65, "SLDC", PcodeOperands.None, "load the constant 65"),
        new(66, "SLDC", PcodeOperands.None, "load the constant 66"),
        new(67, "SLDC", PcodeOperands.None, "load the constant 67"),
        new(68, "SLDC", PcodeOperands.None, "load the constant 68"),
        new(69, "SLDC", PcodeOperands.None, "load the constant 69"),
        new(70, "SLDC", PcodeOperands.None, "load the constant 70"),
        new(71, "SLDC", PcodeOperands.None, "load the constant 71"),
        new(72, "SLDC", PcodeOperands.None, "load the constant 72"),
        new(73, "SLDC", PcodeOperands.None, "load the constant 73"),
        new(74, "SLDC", PcodeOperands.None, "load the constant 74"),
        new(75, "SLDC", PcodeOperands.None, "load the constant 75"),
        new(76, "SLDC", PcodeOperands.None, "load the constant 76"),
        new(77, "SLDC", PcodeOperands.None, "load the constant 77"),
        new(78, "SLDC", PcodeOperands.None, "load the constant 78"),
        new(79, "SLDC", PcodeOperands.None, "load the constant 79"),
        new(80, "SLDC", PcodeOperands.None, "load the constant 80"),
        new(81, "SLDC", PcodeOperands.None, "load the constant 81"),
        new(82, "SLDC", PcodeOperands.None, "load the constant 82"),
        new(83, "SLDC", PcodeOperands.None, "load the constant 83"),
        new(84, "SLDC", PcodeOperands.None, "load the constant 84"),
        new(85, "SLDC", PcodeOperands.None, "load the constant 85"),
        new(86, "SLDC", PcodeOperands.None, "load the constant 86"),
        new(87, "SLDC", PcodeOperands.None, "load the constant 87"),
        new(88, "SLDC", PcodeOperands.None, "load the constant 88"),
        new(89, "SLDC", PcodeOperands.None, "load the constant 89"),
        new(90, "SLDC", PcodeOperands.None, "load the constant 90"),
        new(91, "SLDC", PcodeOperands.None, "load the constant 91"),
        new(92, "SLDC", PcodeOperands.None, "load the constant 92"),
        new(93, "SLDC", PcodeOperands.None, "load the constant 93"),
        new(94, "SLDC", PcodeOperands.None, "load the constant 94"),
        new(95, "SLDC", PcodeOperands.None, "load the constant 95"),
        new(96, "SLDC", PcodeOperands.None, "load the constant 96"),
        new(97, "SLDC", PcodeOperands.None, "load the constant 97"),
        new(98, "SLDC", PcodeOperands.None, "load the constant 98"),
        new(99, "SLDC", PcodeOperands.None, "load the constant 99"),
        new(100, "SLDC", PcodeOperands.None, "load the constant 100"),
        new(101, "SLDC", PcodeOperands.None, "load the constant 101"),
        new(102, "SLDC", PcodeOperands.None, "load the constant 102"),
        new(103, "SLDC", PcodeOperands.None, "load the constant 103"),
        new(104, "SLDC", PcodeOperands.None, "load the constant 104"),
        new(105, "SLDC", PcodeOperands.None, "load the constant 105"),
        new(106, "SLDC", PcodeOperands.None, "load the constant 106"),
        new(107, "SLDC", PcodeOperands.None, "load the constant 107"),
        new(108, "SLDC", PcodeOperands.None, "load the constant 108"),
        new(109, "SLDC", PcodeOperands.None, "load the constant 109"),
        new(110, "SLDC", PcodeOperands.None, "load the constant 110"),
        new(111, "SLDC", PcodeOperands.None, "load the constant 111"),
        new(112, "SLDC", PcodeOperands.None, "load the constant 112"),
        new(113, "SLDC", PcodeOperands.None, "load the constant 113"),
        new(114, "SLDC", PcodeOperands.None, "load the constant 114"),
        new(115, "SLDC", PcodeOperands.None, "load the constant 115"),
        new(116, "SLDC", PcodeOperands.None, "load the constant 116"),
        new(117, "SLDC", PcodeOperands.None, "load the constant 117"),
        new(118, "SLDC", PcodeOperands.None, "load the constant 118"),
        new(119, "SLDC", PcodeOperands.None, "load the constant 119"),
        new(120, "SLDC", PcodeOperands.None, "load the constant 120"),
        new(121, "SLDC", PcodeOperands.None, "load the constant 121"),
        new(122, "SLDC", PcodeOperands.None, "load the constant 122"),
        new(123, "SLDC", PcodeOperands.None, "load the constant 123"),
        new(124, "SLDC", PcodeOperands.None, "load the constant 124"),
        new(125, "SLDC", PcodeOperands.None, "load the constant 125"),
        new(126, "SLDC", PcodeOperands.None, "load the constant 126"),
        new(127, "SLDC", PcodeOperands.None, "load the constant 127"),
        new(128, "ABI", PcodeOperands.None, "absolute value of an integer"),
        new(129, "ABR", PcodeOperands.None, "absolute value of a real"),
        new(130, "ADI", PcodeOperands.None, "add integers"),
        new(131, "ADR", PcodeOperands.None, "add reals"),
        new(132, "LAND", PcodeOperands.None, "logical and"),
        new(133, "DIF", PcodeOperands.None, "set difference"),
        new(134, "DVI", PcodeOperands.None, "divide integers"),
        new(135, "DVR", PcodeOperands.None, "divide reals"),
        new(136, "CHK", PcodeOperands.None, "check that an index is in its range"),
        new(137, "FLO", PcodeOperands.None, "float the integer under the top of the stack"),
        new(138, "FLT", PcodeOperands.None, "float the integer on top of the stack"),
        new(139, "INN", PcodeOperands.None, "test set membership"),
        new(140, "INT", PcodeOperands.None, "set intersection"),
        new(141, "LOR", PcodeOperands.None, "logical or"),
        new(142, "MODI", PcodeOperands.None, "integer remainder"),
        new(143, "MPI", PcodeOperands.None, "multiply integers"),
        new(144, "MPR", PcodeOperands.None, "multiply reals"),
        new(145, "NGI", PcodeOperands.None, "negate an integer"),
        new(146, "NGR", PcodeOperands.None, "negate a real"),
        new(147, "LNOT", PcodeOperands.None, "logical not"),
        new(148, "SRS", PcodeOperands.None, "build a subrange set"),
        new(149, "SBI", PcodeOperands.None, "subtract integers"),
        new(150, "SBR", PcodeOperands.None, "subtract reals"),
        new(151, "SGS", PcodeOperands.None, "build a singleton set"),
        new(152, "SQI", PcodeOperands.None, "square an integer"),
        new(153, "SQR", PcodeOperands.None, "square a real"),
        new(154, "STO", PcodeOperands.None, "store indirect"),
        new(155, "IXS", PcodeOperands.None, "index a string, checking the index"),
        new(156, "UNI", PcodeOperands.None, "set union"),
        new(157, "LDE", PcodeOperands.SegmentBig, "load a word of an intrinsic unit's data"),
        new(158, "CSP", PcodeOperands.StandardProcedure, "call a standard procedure"),
        new(159, "LDCN", PcodeOperands.None, "load the constant nil"),
        new(160, "ADJ", PcodeOperands.Byte, "adjust a set to a number of words"),
        new(161, "FJP", PcodeOperands.Jump, "jump if false"),
        new(162, "INC", PcodeOperands.Big, "increment a field pointer"),
        new(163, "IND", PcodeOperands.Big, "load indirect from an offset"),
        new(164, "IXA", PcodeOperands.Big, "index an array"),
        new(165, "LAO", PcodeOperands.Big, "load a global's address"),
        new(166, "LSA", PcodeOperands.String, "load a string constant's address"),
        new(167, "LAE", PcodeOperands.SegmentBig, "load the address of an intrinsic unit's data"),
        new(168, "MOV", PcodeOperands.Big, "move words"),
        new(169, "LDO", PcodeOperands.Big, "load a global"),
        new(170, "SAS", PcodeOperands.Byte, "assign a string"),
        new(171, "SRO", PcodeOperands.Big, "store a global"),
        new(172, "XJP", PcodeOperands.CaseJump, "case jump"),
        new(173, "RNP", PcodeOperands.Byte, "return from a procedure, leaving a function's result"),
        new(174, "CIP", PcodeOperands.Byte, "call an intermediate procedure"),
        new(175, "EQU", PcodeOperands.Comparison, "compare for equal"),
        new(176, "GEQ", PcodeOperands.Comparison, "compare for greater or equal"),
        new(177, "GRT", PcodeOperands.Comparison, "compare for greater"),
        new(178, "LDA", PcodeOperands.LevelBig, "load an intermediate variable's address"),
        new(179, "LDC", PcodeOperands.Words, "load a multiple-word constant"),
        new(180, "LEQ", PcodeOperands.Comparison, "compare for less or equal"),
        new(181, "LES", PcodeOperands.Comparison, "compare for less"),
        new(182, "LOD", PcodeOperands.LevelBig, "load an intermediate variable"),
        new(183, "NEQ", PcodeOperands.Comparison, "compare for not equal"),
        new(184, "STR", PcodeOperands.LevelBig, "store an intermediate variable"),
        new(185, "UJP", PcodeOperands.Jump, "jump"),
        new(186, "LDP", PcodeOperands.None, "load a packed field"),
        new(187, "STP", PcodeOperands.None, "store a packed field"),
        new(188, "LDM", PcodeOperands.Byte, "load words"),
        new(189, "STM", PcodeOperands.Byte, "store words"),
        new(190, "LDB", PcodeOperands.None, "load a byte"),
        new(191, "STB", PcodeOperands.None, "store a byte"),
        new(192, "IXP", PcodeOperands.TwoBytes, "index a packed array"),
        new(193, "RBP", PcodeOperands.Byte, "return from a base procedure"),
        new(194, "CBP", PcodeOperands.Byte, "call a base procedure"),
        new(195, "EQUI", PcodeOperands.None, "compare integers for equal"),
        new(196, "GEQI", PcodeOperands.None, "compare integers for greater or equal"),
        new(197, "GRTI", PcodeOperands.None, "compare integers for greater"),
        new(198, "LLA", PcodeOperands.Big, "load a local's address"),
        new(199, "LDCI", PcodeOperands.Word, "load a word constant"),
        new(200, "LEQI", PcodeOperands.None, "compare integers for less or equal"),
        new(201, "LESI", PcodeOperands.None, "compare integers for less"),
        new(202, "LDL", PcodeOperands.Big, "load a local"),
        new(203, "NEQI", PcodeOperands.None, "compare integers for not equal"),
        new(204, "STL", PcodeOperands.Big, "store a local"),
        new(205, "CXP", PcodeOperands.TwoBytes, "call a procedure in another segment"),
        new(206, "CLP", PcodeOperands.Byte, "call a local procedure"),
        new(207, "CGP", PcodeOperands.Byte, "call a global procedure"),
        new(208, "LPA", PcodeOperands.Bytes, "load a packed array constant's address"),
        new(209, "STE", PcodeOperands.SegmentBig, "store a word of an intrinsic unit's data"),
        new(210, "NOP", PcodeOperands.None, "no operation (unused)"),
        new(211, "EFJ", PcodeOperands.Jump, "jump if not equal"),
        new(212, "NFJ", PcodeOperands.Jump, "jump if equal"),
        new(213, "BPT", PcodeOperands.Big, "breakpoint"),
        new(214, "XIT", PcodeOperands.None, "exit the system"),
        new(215, "NOP", PcodeOperands.None, "no operation"),
        new(216, "SLDL1", PcodeOperands.None, "load local 1"),
        new(217, "SLDL2", PcodeOperands.None, "load local 2"),
        new(218, "SLDL3", PcodeOperands.None, "load local 3"),
        new(219, "SLDL4", PcodeOperands.None, "load local 4"),
        new(220, "SLDL5", PcodeOperands.None, "load local 5"),
        new(221, "SLDL6", PcodeOperands.None, "load local 6"),
        new(222, "SLDL7", PcodeOperands.None, "load local 7"),
        new(223, "SLDL8", PcodeOperands.None, "load local 8"),
        new(224, "SLDL9", PcodeOperands.None, "load local 9"),
        new(225, "SLDL10", PcodeOperands.None, "load local 10"),
        new(226, "SLDL11", PcodeOperands.None, "load local 11"),
        new(227, "SLDL12", PcodeOperands.None, "load local 12"),
        new(228, "SLDL13", PcodeOperands.None, "load local 13"),
        new(229, "SLDL14", PcodeOperands.None, "load local 14"),
        new(230, "SLDL15", PcodeOperands.None, "load local 15"),
        new(231, "SLDL16", PcodeOperands.None, "load local 16"),
        new(232, "SLDO1", PcodeOperands.None, "load global 1"),
        new(233, "SLDO2", PcodeOperands.None, "load global 2"),
        new(234, "SLDO3", PcodeOperands.None, "load global 3"),
        new(235, "SLDO4", PcodeOperands.None, "load global 4"),
        new(236, "SLDO5", PcodeOperands.None, "load global 5"),
        new(237, "SLDO6", PcodeOperands.None, "load global 6"),
        new(238, "SLDO7", PcodeOperands.None, "load global 7"),
        new(239, "SLDO8", PcodeOperands.None, "load global 8"),
        new(240, "SLDO9", PcodeOperands.None, "load global 9"),
        new(241, "SLDO10", PcodeOperands.None, "load global 10"),
        new(242, "SLDO11", PcodeOperands.None, "load global 11"),
        new(243, "SLDO12", PcodeOperands.None, "load global 12"),
        new(244, "SLDO13", PcodeOperands.None, "load global 13"),
        new(245, "SLDO14", PcodeOperands.None, "load global 14"),
        new(246, "SLDO15", PcodeOperands.None, "load global 15"),
        new(247, "SLDO16", PcodeOperands.None, "load global 16"),
        new(248, "SIND0", PcodeOperands.None, "load indirect from offset 0"),
        new(249, "SIND1", PcodeOperands.None, "load indirect from offset 1"),
        new(250, "SIND2", PcodeOperands.None, "load indirect from offset 2"),
        new(251, "SIND3", PcodeOperands.None, "load indirect from offset 3"),
        new(252, "SIND4", PcodeOperands.None, "load indirect from offset 4"),
        new(253, "SIND5", PcodeOperands.None, "load indirect from offset 5"),
        new(254, "SIND6", PcodeOperands.None, "load indirect from offset 6"),
        new(255, "SIND7", PcodeOperands.None, "load indirect from offset 7")
    ];

    private static readonly string[] s_standardProcedures =
    [
        "IOC",
        "NEW",
        "MVL",
        "MVR",
        "EXIT",
        "UREAD",
        "UWRITE",
        "IDS",
        "TRS",
        "TIM",
        "FLC",
        "SCN",
        "",
        "",
        "",
        "",
        "",
        "",
        "",
        "",
        "",
        "GSEG",
        "RSEG",
        "TNC",
        "RND",
        "SIN",
        "COS",
        "LOG",
        "ATAN",
        "LN",
        "EXP",
        "SQT",
        "MRK",
        "RLS",
        "IOR",
        "UBUSY",
        "POT",
        "UWAIT",
        "UCLEAR",
        "HLT",
        "MEMA"
    ];

    /// <summary>
    ///  Gets the opcode a byte is.
    /// </summary>
    /// <param name="code">The byte.</param>
    /// <returns>Its opcode.</returns>
    public static PcodeOpcode Opcode(byte code) => s_opcodes[code];

    /// <summary>
    ///  Gets the name of a standard procedure that <c>CSP</c> calls, such as <c>IOC</c> or <c>MVL</c>.
    /// </summary>
    /// <param name="number">Its number.</param>
    /// <returns>Its name, or its number when it has none.</returns>
    public static string StandardProcedure(int number) =>
        number < s_standardProcedures.Length && s_standardProcedures[number].Length != 0
            ? s_standardProcedures[number]
            : number.ToString(System.Globalization.CultureInfo.InvariantCulture);
}
