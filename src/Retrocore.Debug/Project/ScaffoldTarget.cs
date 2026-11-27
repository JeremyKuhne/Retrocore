// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Debug.Project;

/// <summary>
///  A target a new project gets.
/// </summary>
/// <param name="Name">The target's name, such as <c>apple2-dos</c>.</param>
/// <param name="Machine">Its machine.</param>
/// <param name="Family">Its machine's family in the template, which gives its environment.</param>
/// <param name="Defines">The defines it adds to the project's.</param>
internal sealed record ScaffoldTarget(string Name, CatalogMachine Machine, TemplateFamily Family, IReadOnlyList<KeyValuePair<string, long>> Defines);
