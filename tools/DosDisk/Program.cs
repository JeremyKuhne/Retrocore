// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using ConsoleAppFramework;
using Retrocore.DiskTool;

ConsoleApp.ConsoleAppBuilder app = ConsoleApp.Create();
app.Add("", DiskCommands.Build);
app.Run(args);
