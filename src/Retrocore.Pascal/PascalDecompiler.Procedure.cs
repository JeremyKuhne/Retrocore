// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Media;

namespace Retrocore.Pascal;

public sealed partial class PascalDecompiler
{
    /// <summary>
    ///  A procedure or function, from its segment's procedure dictionary.
    /// </summary>
    /// <param name="segment">The segment that holds it.</param>
    /// <param name="code">Its entry in the segment's procedure dictionary.</param>
    private sealed class Procedure(PascalSegment segment, PascalProcedure code)
    {
        private Frame? _frame;

        /// <summary>
        ///  Gets the segment that holds it.
        /// </summary>
        public PascalSegment Segment { get; } = segment;

        /// <summary>
        ///  Gets its entry in the segment's procedure dictionary.
        /// </summary>
        public PascalProcedure Code { get; } = code;

        /// <summary>
        ///  Gets its procedure number in the segment.
        /// </summary>
        public int Number => Code.Index;

        /// <summary>
        ///  Gets its lexical level: an assembled procedure's attributes say 0, but it is declared EXTERNAL in the
        ///  program, at level 1.
        /// </summary>
        public int Level => Code.IsNative ? 1 : Code.LexicalLevel;

        /// <summary>
        ///  Gets or sets whether an assembled procedure's parameters and result are known, from its first call.
        /// </summary>
        public bool Signed { get; set; }

        /// <summary>
        ///  Gets or sets the procedure it is declared in, or null for the program.
        /// </summary>
        public Procedure? Parent { get; set; }

        /// <summary>
        ///  Gets the procedures declared in it, by number.
        /// </summary>
        public List<Procedure> Children { get; } = [];

        /// <summary>
        ///  Gets or sets its activation record.
        /// </summary>
        /// <exception cref="InvalidOperationException">The frame has not been set.</exception>
        public Frame Frame
        {
            get => _frame ?? throw new InvalidOperationException($"{this} has no frame yet.");
            set => _frame = value;
        }

        /// <summary>
        ///  Gets or sets its p-code, from its entry to the return at its exit.
        /// </summary>
        public IReadOnlyList<PcodeInstruction> Instructions { get; set; } = [];

        /// <summary>
        ///  Gets or sets the words of a function's result, which it leaves with RNP 1 or 2; 0 for a procedure.
        /// </summary>
        public int ResultWords { get; set; }

        /// <summary>
        ///  Gets a value indicating whether it is a function.
        /// </summary>
        public bool IsFunction => ResultWords > 0;

        /// <summary>
        ///  Gets a function's inferred result type.
        /// </summary>
        public TypeNode ResultType { get; } = new();

        /// <summary>
        ///  Gets a value indicating whether its segment holds it as the segment's procedure 1, a SEGMENT PROCEDURE.
        /// </summary>
        public bool IsSegmentProcedure => Number == 1 && Level >= 1;

        /// <summary>
        ///  Gets or sets its body's statements.
        /// </summary>
        public List<Statement> Body { get; set; } = [];

        /// <summary>
        ///  Gets the labels its GOTOs jump to: each label's number, by the offset it marks.
        /// </summary>
        public SortedDictionary<int, int> Labels { get; } = [];

        /// <summary>
        ///  Gets or sets the name the writer gives it.
        /// </summary>
        public string Name { get; set; } = "";

        /// <summary>
        ///  Gets or sets a value indicating whether it could not be decoded or decompiled.
        /// </summary>
        public bool Failed { get; set; }

        /// <inheritdoc/>
        public override string ToString() => $"{Segment.Name}.{Number}";
    }
}
