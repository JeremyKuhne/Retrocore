// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Tests;

/// <summary>
///  Tests instruction descriptions.
/// </summary>
[TestClass]
public class InstructionExtensionsTests
{
    /// <summary>
    ///  Verifies the short description of an instruction.
    /// </summary>
    /// <param name="instruction">The instruction.</param>
    /// <param name="expected">The expected description.</param>
    [TestMethod]
    [DataRow(Instruction.NOP, "No OPeration")]
    [DataRow(Instruction.ADC, "ADd memory to accumulator with Carry")]
    [DataRow(Instruction.WAI, "WAit for Interrupt")]
    public void SummaryReturnsExpectedDescription(Instruction instruction, string expected)
    {
        instruction.Summary.Should().Be(expected);
    }
}
