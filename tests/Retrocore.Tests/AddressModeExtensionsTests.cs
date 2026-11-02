// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Tests;

/// <summary>
///  Tests addressing mode mnemonics.
/// </summary>
[TestClass]
public class AddressModeExtensionsTests
{
    /// <summary>
    ///  Verifies the shorthand for an addressing mode.
    /// </summary>
    /// <param name="mode">The addressing mode.</param>
    /// <param name="expected">The expected mnemonic.</param>
    [TestMethod]
    [DataRow(AddressMode.Absolute, "a")]
    [DataRow(AddressMode.Immediate, "#")]
    [DataRow(AddressMode.Accumulator, "A")]
    [DataRow(AddressMode.ZeroPageIndirectIndexedY, "(zp),y")]
    public void MnemonicReturnsExpectedShorthand(AddressMode mode, string expected)
    {
        mode.Mnemonic.Should().Be(expected);
    }
}
