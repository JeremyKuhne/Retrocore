// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Desktop;

/// <summary>
///  An action on a row or a section: an icon and a title, as a VS Code command contributes them.
/// </summary>
/// <param name="Icon">The Codicon, or null in a menu.</param>
/// <param name="Title">What the action is called, which its tooltip and menu item show.</param>
/// <param name="Run">What it does.</param>
internal sealed record TreeAction(string? Icon, string Title, Action Run);