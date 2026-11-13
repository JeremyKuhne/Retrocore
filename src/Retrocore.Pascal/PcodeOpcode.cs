// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Pascal;

/// <summary>
///  A p-code: its mnemonic, its operands and what it does.
/// </summary>
/// <param name="Code">Its opcode byte.</param>
/// <param name="Mnemonic">Its mnemonic, such as <c>LDL</c>.</param>
/// <param name="Operands">The operands after the opcode.</param>
/// <param name="Summary">What it does, in a few words.</param>
public sealed record PcodeOpcode(byte Code, string Mnemonic, PcodeOperands Operands, string Summary)
{
    /// <summary>
    ///  Gets whether it leaves the procedure: <c>RNP</c>, <c>RBP</c> or <c>XIT</c>.
    /// </summary>
    public bool Returns => Code is Pcode.Rnp or Pcode.Rbp or Pcode.Xit;

    /// <summary>
    ///  Gets whether it calls a procedure.
    /// </summary>
    public bool Calls => Code is Pcode.Cip or Pcode.Cbp or Pcode.Cxp or Pcode.Clp or Pcode.Cgp;

    /// <summary>
    ///  Gets whether it always jumps: <c>UJP</c> or <c>XJP</c>.
    /// </summary>
    public bool Jumps => Code is Pcode.Ujp or Pcode.Xjp;
}
