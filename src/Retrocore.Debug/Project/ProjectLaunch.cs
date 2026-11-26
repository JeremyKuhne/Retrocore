// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using System.Text.Json.Nodes;

namespace Retrocore.Debug.Project;

/// <summary>
///  A launch with <c>project</c> and <c>target</c>: builds the target as <c>retrocore build</c> does and gives the
///  launch the machine it runs on.
/// </summary>
/// <remarks>
///  <para>
///   <c>project</c> is a <c>retrocore.json</c> or its folder, a root file's included, and <c>target</c> a target's
///   name, or <c>project/target</c> where a root file's projects share one. The project replaces <c>source</c>,
///   <c>program</c>, <c>debugFile</c>, <c>basic</c>, <c>executable</c> and <c>basicSource</c>, and decides
///   <c>dialect</c>, <c>linkerConfiguration</c>, <c>loadAddress</c>, <c>entryAddress</c> and <c>dos</c>, so the
///   launch must leave all of them out.
///  </para>
///  <para>
///   The target supplies the launch's <c>machine</c>, <c>model</c> and <c>rom</c>, which replace any the launch
///   gives, and its <c>options</c>, which the launch's own attributes of the same name override, so a launch
///   configuration can still turn the sound off. Its <c>cards</c> go in after the machine is built,
///   and a saved machine's over them. The launch's response gives the machine it started, as <c>project</c>. The memory
///   marks and names Retrocore Memory keeps default to <c>&lt;name&gt;.&lt;target&gt;.hints.json</c> beside the
///   project file. Breakpoints, <c>stopOnEntry</c> and <c>checkContracts</c> stay the launch's. On the Apple II the
///   ROM runs for <c>bootSeconds</c> (a quarter of a second unless the launch says) as the machine is built,
///   before the cards and a saved machine's media go in and before the program loads, so the Monitor has set up the routines a bare program calls, such as COUT.
///  </para>
/// </remarks>
internal static class ProjectLaunch
{
    /// <summary>
    ///  The launch attributes a project launch cannot give, as the project decides them.
    /// </summary>
    internal static readonly string[] Replaced =
    [
        "source", "program", "debugFile", "basic", "executable", "basicSource", "dialect", "linkerConfiguration",
        "loadAddress", "entryAddress", "dos"
    ];

    /// <summary>
    ///  Builds a project launch's target and gives the launch its machine and options.
    /// </summary>
    /// <param name="args">The launch's arguments, with <c>project</c>.</param>
    /// <returns>The arguments the machine launches with, and the build to load.</returns>
    /// <exception cref="ProjectException">
    ///  The launch gives what the project replaces or no target, the project is malformed, or the target does not
    ///  build.
    /// </exception>
    internal static (JsonObject Arguments, TargetBuild Build) Prepare(JsonObject args)
    {
        string path = args.String("project") ?? throw new ProjectException("A project launch gives project.");
        if (Replaced.FirstOrDefault(args.ContainsKey) is { } replaced)
        {
            throw new ProjectException(
                $"A project launch builds its target, so it cannot give '{replaced}'; leave out {string.Join(", ", Replaced)}.");
        }

        string name = args.String("target")
            ?? throw new ProjectException("A project launch names its target: give target, one of the targets its retrocore.json lists.");

        ProjectTarget target;
        try
        {
            target = BuildCommand.Select(RetrocoreProject.LoadAll(path), name, all: false)[0];
        }
        catch (Exception exception) when (exception is ArgumentException or IOException or UnauthorizedAccessException)
        {
            throw new ProjectException($"{path}: {exception.Message}");
        }

        TargetBuild build;
        try
        {
            build = ProjectBuild.Build(target);
        }
        catch (Exception exception) when (exception is IOException or UnauthorizedAccessException or ArgumentException)
        {
            throw new ProjectException($"{target.Project.File}: target {target.Name}: {exception.Message}");
        }

        JsonObject launch = (JsonObject)args.DeepClone();
        launch.Remove("model");
        launch.Remove("rom");
        launch["machine"] = target.Machine.Machine;
        if (target.Machine.Model is { } model) { launch["model"] = model; }
        if (target.Machine.Rom is { } rom) { launch["rom"] = rom; }
        foreach ((string option, JsonNode? value) in target.Options)
        {
            if (!launch.ContainsKey(option)) { launch[option] = value?.DeepClone(); }
        }

        target.Built?.Launch(target, launch);
        if (!launch.ContainsKey("hints"))
        {
            launch["hints"] = Path.Join(target.Project.Directory, $"{target.Project.Name}.{target.Name}.hints.json");
        }

        return (launch, build);
    }
}
