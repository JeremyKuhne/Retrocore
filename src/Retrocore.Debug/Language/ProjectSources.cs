// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Debug.Project;
using System.Collections.Concurrent;

namespace Retrocore.Debug.Language;

/// <summary>
///  The editor's view of <c>retrocore.json</c> projects: which target a source is analyzed through, and the active
///  target the client chose.
/// </summary>
/// <remarks>
///  <para>
///   A source a project's target assembles is analyzed with the whole target, as <c>retrocore build</c> assembles it:
///   its platform folders, its sources, its SDK headers and its defines. The analysis's root is then a target root, a
///   path in the project's folder named <c>&lt;project&gt;.&lt;target&gt;.retrocore-target</c>, which no file has:
///   <see cref="Target"/> maps it back. A source in several targets is analyzed through the active target when that
///   assembles it, and otherwise through the first of the project's targets that does, in the order the file lists
///   them.
///  </para>
///  <para>
///   A project file is read again when it changes on disk; each target's source list is kept for a second, so a
///   source added to a folder a pattern names is found soon after.
///  </para>
/// </remarks>
internal static class ProjectSources
{
    /// <summary>
    ///  The extension of a target root's name.
    /// </summary>
    internal const string Extension = ".retrocore-target";

    private static readonly TimeSpan s_sourcesLife = TimeSpan.FromSeconds(1);

    private static readonly ConcurrentDictionary<string, (DateTime Written, IReadOnlyList<RetrocoreProject>? Projects)> s_projects =
        new(StringComparer.OrdinalIgnoreCase);

    private static readonly ConcurrentDictionary<string, (string File, string Target)> s_roots = new(StringComparer.OrdinalIgnoreCase);

    private static readonly ConcurrentDictionary<(string File, string Target), (long Read, HashSet<string> Files)> s_sources = new();

    private static volatile Tuple<string, string>? s_active;

    /// <summary>
    ///  Occurs when the active target changes, with the project file it is in, or null when none is active.
    /// </summary>
    internal static event Action<string?>? ActiveChanged;

    /// <summary>
    ///  Gets the active target: the project file, a project's own <c>retrocore.json</c>, and the target's name.
    /// </summary>
    internal static (string File, string Target)? Active => s_active is { } active ? (active.Item1, active.Item2) : null;

    /// <summary>
    ///  Sets the active target, which the client chose.
    /// </summary>
    /// <param name="project">A <c>retrocore.json</c> or its folder, or null to clear it.</param>
    /// <param name="target">
    ///  The target's name, or <c>project/target</c> for a project a root file lists; null clears it.
    /// </param>
    internal static void SetActive(string? project, string? target)
    {
        (string File, string Target)? active = null;
        if (project is not null && target is not null)
        {
            string file = Directory.Exists(project) ? Path.Join(project, RetrocoreProject.FileName) : project;
            file = Path.GetFullPath(file);
            string name = target;
            if (Projects(file) is { } projects)
            {
                foreach (RetrocoreProject candidate in projects)
                {
                    string prefix = candidate.Name + "/";
                    string own = target.StartsWith(prefix, StringComparison.Ordinal) ? target[prefix.Length..] : target;
                    if (candidate.Targets.Any(each => each.Name == own))
                    {
                        (file, name) = (candidate.File, own);
                        break;
                    }
                }
            }

            active = (file, name);
        }

        (string File, string Target)? previous = Active;
        s_active = active is { } set ? Tuple.Create(set.File, set.Target) : null;
        if (previous != active)
        {
            if (previous is { } old) { ActiveChanged?.Invoke(old.File); }
            if (active is { } now) { ActiveChanged?.Invoke(now.File); }
        }
    }

    /// <summary>
    ///  Gets the target root a source is analyzed through.
    /// </summary>
    /// <param name="path">The source's full path.</param>
    /// <returns>The target root, or null when no project's target assembles it.</returns>
    internal static string? RootOf(string path)
    {
        if (path.EndsWith(Extension, StringComparison.OrdinalIgnoreCase)) { return path; }
        if (ProjectFileOf(path) is not { } file || Projects(file) is not { } projects) { return null; }
        string full = Path.GetFullPath(path);
        (string File, string Target)? active = Active;
        ProjectTarget? first = null;
        foreach (RetrocoreProject project in projects)
        {
            foreach (ProjectTarget target in project.Targets)
            {
                if (!Assembles(target, full)) { continue; }
                if (active is { } chosen && string.Equals(chosen.File, project.File, StringComparison.OrdinalIgnoreCase) && chosen.Target == target.Name)
                {
                    return RootFor(target);
                }

                first ??= target;
            }
        }

        return first is null ? null : RootFor(first);
    }

    /// <summary>
    ///  Gets every target root of the projects in a folder and its subfolders, one for each target.
    /// </summary>
    /// <param name="folder">The folder.</param>
    /// <returns>The target roots.</returns>
    internal static List<string> RootsIn(string folder)
    {
        List<string> roots = [];
        foreach (string file in Directory.EnumerateFiles(folder, RetrocoreProject.FileName, SearchOption.AllDirectories))
        {
            // A root file's projects have their own files, found in their own folders.
            string full = Path.GetFullPath(file);
            foreach (RetrocoreProject project in (Projects(full) ?? []).Where(project => string.Equals(project.File, full, StringComparison.OrdinalIgnoreCase)))
            {
                roots.AddRange(project.Targets.Select(RootFor));
            }
        }

        return roots;
    }

    /// <summary>
    ///  Gets the target a target root names.
    /// </summary>
    /// <param name="root">The target root.</param>
    /// <returns>The target, or null when the root names none, or its project no longer has it.</returns>
    internal static ProjectTarget? Target(string root)
    {
        if (!root.EndsWith(Extension, StringComparison.OrdinalIgnoreCase) || !s_roots.TryGetValue(root, out var named))
        {
            return null;
        }

        return Projects(named.File)?.FirstOrDefault(project => string.Equals(project.File, named.File, StringComparison.OrdinalIgnoreCase))
            ?.Targets.FirstOrDefault(target => target.Name == named.Target);
    }

    /// <summary>
    ///  Gets the target root of a target.
    /// </summary>
    /// <param name="target">The target.</param>
    /// <returns>The root's path, in the project's folder.</returns>
    internal static string RootFor(ProjectTarget target)
    {
        string root = Path.Join(target.Project.Directory, $"{target.Project.Name}.{target.Name}{Extension}");
        s_roots[root] = (target.Project.File, target.Name);
        return root;
    }

    // Whether a target assembles a file: its platform folders' and sources' files, as the build lists them.
    private static bool Assembles(ProjectTarget target, string path)
    {
        (string File, string Target) key = (target.Project.File, target.Name);
        long now = Environment.TickCount64;
        if (!s_sources.TryGetValue(key, out var sources) || now - sources.Read > s_sourcesLife.TotalMilliseconds)
        {
            HashSet<string> files = [with(StringComparer.OrdinalIgnoreCase)];
            try
            {
                files.UnionWith(target.SourceFiles().Select(file => file.Path));
            }
            catch (Exception exception) when (exception is ProjectException or IOException or UnauthorizedAccessException)
            {
                // A target whose sources are missing still has the ones that exist analyzed alone.
            }

            s_sources[key] = sources = (now, files);
        }

        return sources.Files.Contains(path);
    }

    // The nearest retrocore.json at or above a file's folder.
    private static string? ProjectFileOf(string path)
    {
        for (string? folder = Path.GetDirectoryName(Path.GetFullPath(path)); folder is not null; folder = Path.GetDirectoryName(folder))
        {
            string file = Path.Join(folder, RetrocoreProject.FileName);
            if (File.Exists(file)) { return file; }
        }

        return null;
    }

    // A project file's projects, read again when it changes on disk; null when it cannot be read or has errors.
    private static IReadOnlyList<RetrocoreProject>? Projects(string file)
    {
        DateTime written;
        try
        {
            written = File.GetLastWriteTimeUtc(file);
        }
        catch (Exception exception) when (exception is IOException or UnauthorizedAccessException)
        {
            return null;
        }

        if (s_projects.TryGetValue(file, out var known) && known.Written == written) { return known.Projects; }
        IReadOnlyList<RetrocoreProject>? projects;
        try
        {
            projects = RetrocoreProject.LoadAll(file);
        }
        catch (Exception exception) when (exception is ProjectException or IOException or UnauthorizedAccessException or ArgumentException)
        {
            projects = null;
        }

        s_projects[file] = (written, projects);
        return projects;
    }
}
