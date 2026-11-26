// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

/// <summary>
///  An action of the game: the words it answers, or 0 and a chance for one that happens on its own, its conditions
///  and the codes of what it does.
/// </summary>
/// <param name="Verb">The verb, or 0.</param>
/// <param name="Noun">The noun, 0 for any; for verb 0, the chance in 100 that it happens each turn.</param>
/// <param name="Conditions">The five conditions.</param>
/// <param name="Codes">The four action codes.</param>
internal sealed record GameAction(int Verb, int Noun, List<GameCondition> Conditions, List<int> Codes);
