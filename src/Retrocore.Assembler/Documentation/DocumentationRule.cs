// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Documentation;

/// <summary>
///  A documentation or style lint rule, named by the ID its diagnostics carry and an <c>ignore=</c> exclusion names.
/// </summary>
/// <param name="Id">The rule's ID: a short lowercase name with hyphens, such as <c>line-length</c>.</param>
/// <param name="Description">What the rule checks, for the editor's hover.</param>
/// <param name="TakesNames">Whether the rule reports a name, which an exclusion may narrow it to.</param>
/// <param name="Ignorable">Whether an exclusion may turn the rule off: not one that only reports errors.</param>
public sealed record DocumentationRule(string Id, string Description, bool TakesNames, bool Ignorable);
