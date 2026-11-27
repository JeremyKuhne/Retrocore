// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Debug.Project;

/// <summary>
///  A machine family a template builds for.
/// </summary>
/// <param name="Name">The family, as its platform folder names it, such as <c>apple2</c>.</param>
/// <param name="Machine">The catalog id of the machine the family's name means, such as <c>apple2-iiplus</c>.</param>
/// <param name="Environment">The environment the family's targets use, such as <c>dos33</c>.</param>
/// <param name="Suffix">
///  What a target's name ends in after its machine's, such as <c>dos</c> in <c>apple2-dos</c>.
/// </param>
internal sealed record TemplateFamily(string Name, string Machine, string Environment, string Suffix);
