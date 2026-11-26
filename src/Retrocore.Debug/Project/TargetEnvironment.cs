// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Debug.Project;

/// <summary>
///  An environment a target's program runs in: how it is loaded and started, and the file and image it is built as.
/// </summary>
/// <remarks>
///  <para>
///   The build assembles every environment's program the same way, at its memory map's load address, and writes the
///   binary; the environment then writes its own file and its image beside it (<see cref="Write"/>). Each says which
///   of a target's <c>files</c>, <c>image</c> and <c>bootImage</c> it takes, and a build that gives one it does not
///   take fails naming it.
///  </para>
/// </remarks>
internal abstract class TargetEnvironment
{
    private static readonly TargetEnvironment[] s_built = [new BareEnvironment(), new WozmonEnvironment()];

    /// <summary>
    ///  Gets the environment's name, one of <see cref="ProjectTarget.Environments"/>.
    /// </summary>
    internal abstract string Name { get; }

    /// <summary>
    ///  Gets whether the environment puts a target's <c>files</c> beside its program, on a disk.
    /// </summary>
    internal virtual bool TakesFiles => false;

    /// <summary>
    ///  Gets whether the environment builds an image, which a target's <c>"image": false</c> leaves out.
    /// </summary>
    internal virtual bool BuildsImage => false;

    /// <summary>
    ///  Gets whether the environment can start its image from a template disk, a target's <c>image.template</c>.
    /// </summary>
    internal virtual bool TakesTemplate => false;

    /// <summary>
    ///  Gets whether the environment boots from media that is not an SDK source, which a target's <c>bootImage</c> can
    ///  name.
    /// </summary>
    internal virtual bool TakesBootImage => false;

    /// <summary>
    ///  Gets the environments that build, by name.
    /// </summary>
    internal static IEnumerable<string> Built => s_built.Select(environment => environment.Name);

    /// <summary>
    ///  Finds an environment that builds.
    /// </summary>
    /// <param name="name">The environment's name.</param>
    /// <returns>The environment, or null when it does not build yet.</returns>
    internal static TargetEnvironment? Find(string name) => s_built.FirstOrDefault(environment => environment.Name == name);

    /// <summary>
    ///  Gets what a target gives that its environment does not take, as phrases that end a build's error.
    /// </summary>
    /// <param name="target">The target.</param>
    /// <returns>The problems; none when the environment takes all of it.</returns>
    internal IEnumerable<string> Problems(ProjectTarget target)
    {
        if (target.Files.Count != 0 && !TakesFiles)
        {
            yield return $"the '{Name}' environment has no disk to put 'files' on";
        }

        if (target.ImageGiven && !BuildsImage)
        {
            yield return $"the '{Name}' environment builds no image, so it takes no 'image'";
        }
        else if (target.ImageTemplate is not null && !TakesTemplate)
        {
            yield return $"the '{Name}' environment's image does not start from a template";
        }

        if (target.BootImage is not null && !TakesBootImage)
        {
            yield return $"the '{Name}' environment boots from the SDK's sources, so it takes no 'bootImage'";
        }
    }

    /// <summary>
    ///  Writes the environment's file and its image for a built target, beside its binary.
    /// </summary>
    /// <param name="build">The build, whose binary is written.</param>
    /// <returns>What it wrote.</returns>
    /// <exception cref="ProjectException">
    ///  The program or its files do not fit the environment's file or image.
    /// </exception>
    /// <exception cref="IOException">A file cannot be read or written.</exception>
    /// <exception cref="UnauthorizedAccessException">A file cannot be read or written.</exception>
    internal abstract TargetMedia Write(TargetBuild build);

    /// <summary>
    ///  Gets the path of a file the environment writes beside a build's binary, by its extension.
    /// </summary>
    /// <param name="build">The build.</param>
    /// <param name="extension">The extension, with its dot.</param>
    /// <returns>The path.</returns>
    protected static string Beside(TargetBuild build, string extension) => Path.ChangeExtension(build.Binary, extension);
}
