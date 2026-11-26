// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Debug.Project;

/// <summary>
///  A step as <see cref="ProjectSteps.Run"/> left it.
/// </summary>
/// <param name="Step">The step.</param>
/// <param name="Ran">Whether it ran; false when it was up to date.</param>
/// <param name="Output">What the tool printed, when it ran.</param>
internal sealed record StepResult(ProjectStep Step, bool Ran, string Output);
