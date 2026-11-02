// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using System.Text.Json.Nodes;

namespace Retrocore.Debug.Language;

/// <summary>
///  A symbol the workspace defines, for Go to Symbol in Workspace.
/// </summary>
internal sealed class WorkspaceSymbol
{
    /// <summary>
    ///  Gets the name.
    /// </summary>
    public required string Name { get; init; }

    /// <summary>
    ///  Gets what it is.
    /// </summary>
    public SymbolKind Kind { get; init; }

    /// <summary>
    ///  Gets the file it is in, shown beside it.
    /// </summary>
    public string? ContainerName { get; init; }

    /// <summary>
    ///  Gets where it is defined.
    /// </summary>
    public required LspLocation Location { get; init; }

    /// <summary>
    ///  Writes the symbol.
    /// </summary>
    /// <returns>Its JSON.</returns>
    public JsonObject ToJson()
    {
        JsonObject symbol = new() { ["name"] = Name, ["kind"] = (int)Kind, ["location"] = Location.ToJson() };
        if (ContainerName is not null) { symbol["containerName"] = ContainerName; }
        return symbol;
    }
}
