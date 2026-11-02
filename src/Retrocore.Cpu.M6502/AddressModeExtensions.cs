// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using System.ComponentModel;

namespace Retrocore.Cpu.M6502;

/// <summary>
///  Extension members for <see cref="AddressMode"/>.
/// </summary>
public static class AddressModeExtensions
{
    private static readonly string[] s_addressModeMnemonic =
    [
        "a", "(a,x)", "a,x", "a,y", "(a)", "A", "#", "i",
        "r", "s", "zp", "(zp,x)", "zp,x", "zp,y", "(zp)", "(zp),y", "zp,r"
    ];

    /// <param name="addressMode">The addressing mode.</param>
    extension(AddressMode addressMode)
    {
        /// <summary>
        ///  Gets the shorthand form of the address mode. For example, '
        ///  <code>#</code>
        ///  ' is returned for
        ///  <see cref="AddressMode.Immediate"/>.
        /// </summary>
        /// <exception cref="InvalidEnumArgumentException">The address mode wasn't a valid value.</exception>
        public string Mnemonic
        {
            get
            {
                int mode = (int)addressMode;
                if (mode >= s_addressModeMnemonic.Length || mode < 0)
                {
                    ThrowHelper.ThrowInvalidEnum(addressMode);
                }

                return s_addressModeMnemonic[mode];
            }
        }
    }
}
