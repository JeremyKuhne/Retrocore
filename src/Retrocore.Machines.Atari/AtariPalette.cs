// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Machines.Atari;

/// <summary>
///  The 256 colours GTIA can make: 16 hues in bits 4-7 and 16 luminances in bits 0-3, of which the colour registers
///  reach the even ones.
/// </summary>
/// <remarks>
///  <para>
///   An approximation from the colour encoding: hue 0 is grey, and hues 1-15 step about 23 degrees apart around the
///   colour wheel from the colour burst's orange through red, purple, blue, cyan and green to yellow, at one
///   saturation, as a television shows them. Luminance is linear from near black to white.
///  </para>
/// </remarks>
internal static class AtariPalette
{
    /// <summary>
    ///  Makes the palette as RGBA, <c>0xAABBGGRR</c>.
    /// </summary>
    /// <param name="standard">The television standard.</param>
    /// <returns>The 256 colours.</returns>
    public static uint[] Create(AtariVideoStandard standard)
    {
        uint[] palette = new uint[256];
        double step = standard == AtariVideoStandard.Pal ? 23.5 : 23.0;
        for (int value = 0; value < 256; value++)
        {
            int hue = value >> 4;
            int luminance = value & 0x0F;
            double y = 0.04 + (luminance / 15.0 * 0.92);
            double u = 0;
            double v = 0;
            if (hue != 0)
            {
                double angle = (150 - ((hue - 1) * step)) * Math.PI / 180;
                u = Math.Cos(angle) * 0.22;
                v = Math.Sin(angle) * 0.22;
            }

            double r = y + (1.140 * v);
            double g = y - (0.395 * u) - (0.581 * v);
            double b = y + (2.032 * u);
            palette[value] = 0xFF000000u | (Channel(b) << 16) | (Channel(g) << 8) | Channel(r);
        }

        return palette;
    }

    private static uint Channel(double level) => (uint)Math.Round(Math.Clamp(level, 0, 1) * 255);
}
