// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using System.Text;
using System.Text.Json;

namespace Retrocore.Debug.Project;

/// <summary>
///  <c>retrocore new</c>, which starts a repository from a template, and <c>retrocore init</c>, which adds a project
///  to one that is there, as <see cref="ProjectScaffold"/> writes them.
/// </summary>
/// <remarks>
///  <para>
///   <c>retrocore new &lt;template&gt; &lt;name&gt; [--machines list] [--output folder]</c> writes the project and its
///   repository's files in a new folder, <c>./&lt;name&gt;</c> unless <c>--output</c> names another, which must be
///   empty if it is there. <c>retrocore init &lt;template&gt; [--name name] [--machines list] [--output folder]</c>
///   writes the project in a folder that is there, the current one unless <c>--output</c> names another, named for
///   the folder unless <c>--name</c> says, and adds to the repository's files at the root of the Git repository the
///   folder is in. <c>--machines</c> is a comma-separated list of families or catalog ids; without it, every family
///   the template has. <c>retrocore new --list</c> lists the templates and their machines, and with <c>--json</c>
///   writes them as JSON, for tools such as an editor's New Project command.
///  </para>
/// </remarks>
internal static class NewCommand
{
    private const string NewUsage = "Usage: retrocore new <template> <name> [--machines list] [--output folder], or retrocore new --list [--json]";
    private const string InitUsage = "Usage: retrocore init <template> [--name name] [--machines list] [--output folder]";

    /// <summary>
    ///  Runs <c>new</c> or <c>init</c>.
    /// </summary>
    /// <param name="init">True for <c>init</c>.</param>
    /// <param name="args">The arguments after the command.</param>
    /// <param name="output">Where the files written and what to do next go.</param>
    /// <param name="error">Where errors go.</param>
    /// <param name="templates">The templates folder; the SDK's beside the host by default.</param>
    /// <returns>
    ///  0 when the project was written or the list given; 1 when it could not be; 2 for wrong arguments.
    /// </returns>
    internal static int Run(bool init, string[] args, TextWriter output, TextWriter error, string? templates = null)
    {
        string usage = init ? InitUsage : NewUsage;
        List<string> positional = [];
        string? name = null;
        string? folder = null;
        List<string> machines = [];
        bool list = false;
        bool json = false;
        for (int index = 0; index < args.Length; index++)
        {
            switch (args[index])
            {
                case "--machines" when index + 1 < args.Length:
                    machines.AddRange(args[++index].Split(',', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries));
                    break;
                case "--output" when index + 1 < args.Length:
                    folder = args[++index];
                    break;
                case "--name" when init && index + 1 < args.Length:
                    name = args[++index];
                    break;
                case "--list" when !init:
                    list = true;
                    break;
                case "--json" when !init:
                    json = true;
                    break;
                case "--sdk-roms" when index + 1 < args.Length:
                    // Program reads it for every command.
                    index++;
                    break;
                default:
                    if (args[index].StartsWith("--", StringComparison.Ordinal))
                    {
                        error.WriteLine($"{args[index]}: unknown or incomplete option.");
                        error.WriteLine(usage);
                        return 2;
                    }

                    positional.Add(args[index]);
                    break;
            }
        }

        templates ??= ProjectTemplate.DefaultRoot;
        try
        {
            List<ProjectTemplate> all = ProjectTemplate.LoadAll(templates);
            if (list)
            {
                if (positional.Count != 0 || machines.Count != 0 || folder is not null)
                {
                    error.WriteLine(usage);
                    return 2;
                }

                if (json) { WriteJson(all, output); } else { WriteList(all, output); }
                return 0;
            }

            if (json || positional.Count != (init ? 1 : 2))
            {
                error.WriteLine(usage);
                return 2;
            }

            ProjectTemplate template = all.FirstOrDefault(template => template.Name == positional[0])
                ?? throw new ProjectException(
                    $"There is no template '{positional[0]}'; the templates are {string.Join(", ", all.Select(template => template.Name))}.");

            string repository;
            if (init)
            {
                folder = Path.TrimEndingDirectorySeparator(Path.GetFullPath(folder ?? Directory.GetCurrentDirectory()));
                if (!Directory.Exists(folder))
                {
                    throw new ProjectException($"{folder} is not a folder; retrocore init adds a project to one that is there.");
                }

                name ??= Path.GetFileName(folder);
                repository = RepositoryRoot(folder);
            }
            else
            {
                name = positional[1];
                folder = Path.TrimEndingDirectorySeparator(Path.GetFullPath(folder ?? name));
                if (File.Exists(folder) || (Directory.Exists(folder) && Directory.EnumerateFileSystemEntries(folder).Any()))
                {
                    throw new ProjectException($"{folder} is already there and not empty; retrocore new starts a repository in a new folder. To add a project to a repository, use retrocore init.");
                }

                repository = folder;
            }

            if (!RetrocoreProject.IsFileName(name))
            {
                throw new ProjectException(
                    $"'{name}' cannot name a project: use letters, digits, '-', '_' and '.'{(init ? ", or give --name" : "")}.");
            }

            List<ScaffoldTarget> targets = ProjectScaffold.Targets(template, machines);
            if (targets.Any(target => target.Family.Environment == "dos33") && Dos33Environment.ProgramName(name) == "HELLO")
            {
                throw new ProjectException(
                    $"'{name}' would name the program HELLO on the Apple II's DOS 3.3 disk, the name of the program that starts it; give the project another name.");
            }

            string common = Path.Join(templates, ProjectTemplate.CommonFolder);
            List<ScaffoldFile> files = ProjectScaffold.Plan(template, common, name, targets, folder, repository);
            ProjectScaffold.Write(files);

            string here = Directory.GetCurrentDirectory();
            foreach (ScaffoldFile file in files)
            {
                output.WriteLine($"{Path.GetRelativePath(here, file.Path).Replace('\\', '/')}: {file.What}");
            }

            output.WriteLine();
            output.WriteLine($"{name}: {targets.Count} {(targets.Count == 1 ? "target" : "targets")}, {string.Join(", ", targets.Select(target => target.Name))}. Build them with:");
            string relativeRepository = Path.GetRelativePath(here, repository);
            if (relativeRepository != ".") { output.WriteLine($"  cd {relativeRepository}"); }
            output.WriteLine("  dotnet tool restore");
            string relativeProject = Path.GetRelativePath(repository, folder).Replace('\\', '/');
            output.WriteLine($"  dotnet retrocore build --all{(relativeProject == "." ? "" : $" --project {relativeProject}")}");
            output.WriteLine($"retrocore {ProjectScaffold.ToolVersion} is published nowhere yet. Until it is, make its package in Retrocore with");
            output.WriteLine("dotnet pack src/Retrocore.Debug -c Release -o <folder>, then restore it with dotnet tool restore --add-source <folder>.");
            return 0;
        }
        catch (Exception exception)
            when (exception is ProjectException
                or ArgumentException
                or IOException
                or UnauthorizedAccessException
                or NotSupportedException
                or JsonException
                or InvalidOperationException
                or FormatException)
        {
            error.WriteLine(exception.Message);
            return 1;
        }
    }

    /// <summary>
    ///  Finds the root of the Git repository a folder is in: the nearest folder with a <c>.git</c>, at or above it.
    /// </summary>
    /// <param name="folder">The folder.</param>
    /// <returns>The root, or the folder itself when it is in no repository.</returns>
    internal static string RepositoryRoot(string folder)
    {
        for (string? current = Path.GetFullPath(folder); current is not null; current = Path.GetDirectoryName(current))
        {
            string git = Path.Join(current, ".git");
            if (Directory.Exists(git) || File.Exists(git)) { return current; }
        }

        return Path.GetFullPath(folder);
    }

    private static void WriteList(List<ProjectTemplate> templates, TextWriter output)
    {
        foreach (ProjectTemplate template in templates)
        {
            output.WriteLine($"{template.Name}: {template.Description}");
            foreach (TemplateFamily family in template.Families)
            {
                string machines = string.Join(", ", CatalogMachine.All.Where(machine => machine.Family == family.Name).Select(machine => machine.Id));
                output.WriteLine($"  {family.Name}: {family.Name}-{family.Suffix} ({family.Machine}, {family.Environment}); machines {machines}");
            }
        }
    }

    // The templates as JSON, for tools to read.
    private static void WriteJson(List<ProjectTemplate> templates, TextWriter output)
    {
        using MemoryStream stream = new();
        using (Utf8JsonWriter writer = new(stream, new JsonWriterOptions { Indented = true, NewLine = "\n" }))
        {
            writer.WriteStartObject();
            writer.WriteString("version", ProjectScaffold.ToolVersion);
            writer.WriteStartArray("templates");
            foreach (ProjectTemplate template in templates)
            {
                writer.WriteStartObject();
                writer.WriteString("name", template.Name);
                writer.WriteString("description", template.Description);
                writer.WriteString("cpu", template.Cpu);
                writer.WriteStartArray("families");
                foreach (TemplateFamily family in template.Families)
                {
                    writer.WriteStartObject();
                    writer.WriteString("name", family.Name);
                    writer.WriteString("machine", family.Machine);
                    writer.WriteString("environment", family.Environment);
                    writer.WriteString("target", $"{family.Name}-{family.Suffix}");
                    writer.WriteStartArray("machines");
                    foreach (CatalogMachine machine in CatalogMachine.All.Where(machine => machine.Family == family.Name))
                    {
                        writer.WriteStringValue(machine.Id);
                    }

                    writer.WriteEndArray();
                    writer.WriteEndObject();
                }

                writer.WriteEndArray();
                writer.WriteEndObject();
            }

            writer.WriteEndArray();
            writer.WriteEndObject();
        }

        output.WriteLine(Encoding.UTF8.GetString(stream.ToArray()));
    }
}
