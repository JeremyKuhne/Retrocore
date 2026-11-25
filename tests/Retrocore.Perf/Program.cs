// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using BenchmarkDotNet.Running;

BenchmarkSwitcher.FromAssembly(typeof(Retrocore.Perf.SdkIndexBenchmarks).Assembly).Run(args);
