// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Debug.Language;
using System.Text.Json.Nodes;

namespace Retrocore.Debug;

// The debugger's hover in an assembly source. While a session runs, the editor shows the debugger's hover in place of
// the language server's, and falls back to the language server's when the debugger has nothing to evaluate.
internal sealed partial class DebugSession
{
    /// <summary>
    ///  Gets whether a hover is on an instruction's mnemonic in an assembly source, such as LD or LDA, which the
    ///  language server describes. Such a name is not one of the CPU's, and is not a BASIC variable either: failing
    ///  its evaluation lets the editor show the language server's hover, with the instruction's summary.
    /// </summary>
    /// <param name="args">The evaluate request's arguments.</param>
    /// <param name="expression">The hovered expression.</param>
    /// <returns>Whether the hover is on a mnemonic outside a BASIC source.</returns>
    private static bool IsMnemonicHover(JsonObject args, string expression)
    {
        if (args.String("context") != "hover" || !InstructionDocs.IsMnemonic(expression.Trim()))
        {
            return false;
        }

        // A BASIC variable can have a mnemonic's name, as CP or LD.
        string? path = args["source"].String("path");
        return path is null || !IsBasicFile(path);
    }
}
