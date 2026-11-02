// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Debug.Language;

/// <summary>
///  Short descriptions of the native directives, for hover and completion.
/// </summary>
internal static class DirectiveDocs
{
    private static readonly Dictionary<string, string> s_native = new(StringComparer.OrdinalIgnoreCase)
    {
        [".org"] = "Sets the location counter, padding the output forward to it.",
        [".logicalorg"] = "Sets the logical address of the following code without moving the output; with no operand, ends the region.",
        [".byte"] = "Emits bytes, 0-255: expressions, `'c'` characters and `\"text\"`.",
        [".byt"] = "Emits bytes, as `.byte` does.",
        [".word"] = "Emits 16-bit little-endian words, 0-$FFFF.",
        [".dbyt"] = "Emits 16-bit big-endian words.",
        [".faraddr"] = "Emits 24-bit little-endian values.",
        [".dword"] = "Emits 32-bit little-endian values; negative values are stored in two's complement.",
        [".res"] = "Reserves bytes: `.res count[, fill]`.",
        [".align"] = "Pads to a power-of-two boundary: `.align size[, fill]`.",
        [".equ"] = "Defines a constant: `name: .equ value` (or `name = value`).",
        [".set"] = "Assigns a variable that can be reassigned later: `name .set value` or `.set name, value`.",
        [".cpu"] = "Selects the CPU for the following instructions: Mos6502, Wdc65C02, Rockwell65C02, 65SC02 or Z80.",
        [".rom"] = "Source-generator metadata: `.rom Namespace.Type, origin, size`.",
        [".section"] = "Declares or re-enters a section: `.section Name[, origin, capacity[, fill[, trim]]]`.",
        [".dum"] = "Starts storage that lays out names without emitting bytes: `.dum address`.",
        [".dend"] = "Ends a `.dum` region.",
        [".checksum"] = "Emits the XOR of every preceding byte of the section.",
        [".assert"] = "Fails the assembly when the expression is false: `.assert expression, message`.",
        [".export"] = "Exports names to the generated C# type and the debugger; each must be defined.",
        [".global"] = "Exports names as `.export` does, ignoring any that are never defined.",
        [".scope"] = "Opens a namespace: `.scope [Name]` through `.endscope`; members are `Name::member`.",
        [".endscope"] = "Ends a `.scope`.",
        [".proc"] = "Opens a namespace and defines its name as the address of its first statement: `.proc Name` through `.endproc`.",
        [".endproc"] = "Ends a `.proc`.",
        [".include"] = "Includes a file: `\"path\"` relative to this file, then include paths; `<path>` from SDK paths.",
        [".incbin"] = "Inserts a file's bytes: `.incbin \"path\"[, start[, size]]`.",
        [".macro"] = "Defines a macro: `.macro name param, ...` through `.endmacro`.",
        [".endmacro"] = "Ends a macro definition.",
        [".local"] = "Declares names local to each expansion of the macro.",
        [".exitmacro"] = "Stops the current macro expansion.",
        [".paramcount"] = "In a macro, the number of arguments the invocation passed (an expression, not a directive).",
        [".if"] = "Assembles the following lines when the expression, known at this point, is nonzero.",
        [".elseif"] = "An alternative condition in an `.if` block.",
        [".else"] = "The alternative of an `.if` block.",
        [".endif"] = "Ends an `.if` block.",
        [".ifdef"] = "Assembles the following lines when the name is defined.",
        [".ifndef"] = "Assembles the following lines when the name is not defined.",
        [".ifblank"] = "Assembles the following lines when the macro argument is empty.",
        [".repeat"] = "Repeats lines: `.repeat count[, counter]` through `.endrepeat`.",
        [".endrepeat"] = "Ends a `.repeat` block.",
        [".ifconst"] = "Assembles the following lines when the expression is a constant known at this point.",
        [".ifnconst"] = "Assembles the following lines when the expression is not a constant known at this point.",
        [".ifnblank"] = "Assembles the following lines when the macro argument is not empty.",
        [".hiascii"] = "Emits bytes with bit 7 set, as Apple II text: `.hiascii \"text\", value`.",
        [".define"] = "Defines a textual replacement: `.define NAME text` or `.define NAME(a, b) text`, invoked as `NAME x, y`.",
        [".undefine"] = "Removes a `.define`.",
        [".struct"] = "Defines a structure's field offsets and size: `.struct Name` through `.endstruct`.",
        [".endstruct"] = "Ends a `.struct`.",
        [".union"] = "Defines overlapping fields: `.union Name` through `.endunion`.",
        [".endunion"] = "Ends a `.union`.",
        [".enum"] = "Defines consecutive constants: `.enum Name` through `.endenum`; members are `Name::MEMBER`.",
        [".endenum"] = "Ends an `.enum`.",
        [".tag"] = "Reserves storage for a structure: `label: .tag Type[, count]`.",
        [".charmap"] = "Maps a source character to an output byte for later strings and character literals: `.charmap 'A', $C1`.",
        [".asciiz"] = "Emits strings followed by a zero byte.",
        [".lobytes"] = "Emits the low byte of each expression.",
        [".hibytes"] = "Emits the high byte of each expression.",
        [".error"] = "Fails the assembly with a message.",
        [".fatal"] = "Fails the assembly with a message.",
        [".warning"] = "Accepted and ignored.",
        [".out"] = "Accepted and ignored."
    };

    /// <summary>
    ///  Gets every native directive.
    /// </summary>
    internal static IEnumerable<string> Native => s_native.Keys;

    /// <summary>
    ///  Gets a directive's description.
    /// </summary>
    /// <param name="directive">The directive, with its dot.</param>
    /// <returns>The description, or null.</returns>
    internal static string? Describe(string directive) => s_native.TryGetValue(directive, out string? text) ? text : null;
}
