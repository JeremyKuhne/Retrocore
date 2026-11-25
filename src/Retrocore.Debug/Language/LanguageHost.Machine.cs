// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Debug.Language;

internal static partial class LanguageHost
{
    // A machine set up while it is off, for the Machine and Drives views with no debug session.
    static partial void ServeMachine(JsonRpcServer server)
    {
        server.OnRequest("retrocore/machine/describe", parameters => OffMachine.Describe(parameters ?? []));
        server.OnRequest("retrocore/machine/change", parameters => OffMachine.Change(parameters ?? []));
    }
}
