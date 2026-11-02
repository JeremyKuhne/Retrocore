// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Cpu.M6502;

namespace Retrocore.Machines.Apple2;

/// <summary>
///  What each <see cref="Apple2Model"/> has: its processor and the parts of the board that differ across the family.
/// </summary>
public static class Apple2ModelExtensions
{
    /// <summary>
    ///  Gets whether the model is a IIe, with the IIe's switches, auxiliary slot, built-in $C100-$CFFF firmware and
    ///  16 KB system ROM.
    /// </summary>
    /// <param name="model">The model.</param>
    /// <returns>Whether it is a IIe.</returns>
    public static bool IsIIe(this Apple2Model model) => model is Apple2Model.IIe or Apple2Model.IIeEnhanced;

    /// <summary>
    ///  Gets whether the model is the enhanced IIe, with the 65C02, MouseText and the enhanced firmware.
    /// </summary>
    /// <param name="model">The model.</param>
    /// <returns>Whether it is the enhanced IIe.</returns>
    public static bool IsEnhanced(this Apple2Model model) => model == Apple2Model.IIeEnhanced;

    /// <summary>
    ///  Gets the model's processor: the Rockwell 65C02 in the enhanced IIe, an NMOS 6502 in the others.
    /// </summary>
    /// <param name="model">The model.</param>
    /// <returns>The processor.</returns>
    public static ProcessorVariant Processor(this Apple2Model model) =>
        model.IsEnhanced() ? ProcessorVariant.Rockwell65C02 : ProcessorVariant.Mos6502;

    /// <summary>
    ///  Gets whether this version emulates the model: every model of the family.
    /// </summary>
    /// <param name="model">The model.</param>
    /// <returns>Whether a machine can be made for it.</returns>
    public static bool IsEmulated(this Apple2Model model) => Enum.IsDefined(model);

    /// <summary>
    ///  Gets the model's name, as people know it.
    /// </summary>
    /// <param name="model">The model.</param>
    /// <returns>Such as <c>Apple IIe</c> or <c>Apple II Plus</c>.</returns>
    public static string DisplayName(this Apple2Model model) => model switch
    {
        Apple2Model.IIe => "Apple IIe",
        Apple2Model.IIeEnhanced => "Enhanced Apple IIe",
        Apple2Model.IIPlus => "Apple II Plus",
        _ => "Apple II"
    };

    /// <summary>
    ///  Gets the name documentation uses for the model's build, as in <c>Model: Enhanced</c> and
    ///  <c>&lt;NAME@Enhanced&gt;</c>.
    /// </summary>
    /// <param name="model">The model.</param>
    /// <returns><c>Original</c> or <c>Enhanced</c> for the IIe models; <c>II</c> or <c>IIPlus</c> otherwise.</returns>
    public static string DocumentationName(this Apple2Model model) => model switch
    {
        Apple2Model.IIe => "Original",
        Apple2Model.IIeEnhanced => "Enhanced",
        _ => model.ToString()
    };
}
