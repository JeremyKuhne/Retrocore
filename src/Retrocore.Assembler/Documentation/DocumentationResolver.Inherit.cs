// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Documentation;

public sealed partial class DocumentationResolver
{
    private readonly Dictionary<DocumentationTopic, DocumentationTopic> _effective = [];
    private readonly HashSet<DocumentationTopic> _resolving = [];

    /// <summary>
    ///  Gets a topic with its <c>Inherit:</c> and <c>Include:</c> documentation merged in.
    /// </summary>
    /// <param name="topic">The topic.</param>
    /// <returns>The complete topic; the topic itself when it inherits nothing, or on a cycle.</returns>
    /// <remarks>
    ///  <para>
    ///   As with <c>&lt;inheritdoc&gt;</c>, the topic's own summary and sections win, each inherited part is taken
    ///   whole, and the topic's remarks follow the inherited ones.
    ///  </para>
    /// </remarks>
    public DocumentationTopic Effective(DocumentationTopic topic)
    {
        if (_effective.TryGetValue(topic, out DocumentationTopic? done)) { return done; }
        if (!_resolving.Add(topic)) { return topic; }
        try
        {
            DocumentationTopic result = topic;
            if (topic.Section("Include") is { } include && Included(topic, include) is { } included)
            {
                result = Combine(result, included, sections: []);
            }

            if (topic.Section("Inherit") is { } inherit && InheritTarget(topic, inherit) is { } target)
            {
                result = Combine(result, Effective(target), inherit.Items);
            }

            _effective[topic] = result;
            return result;
        }
        finally
        {
            _resolving.Remove(topic);
        }
    }

    /// <summary>
    ///  Finds the topic an <c>Inherit:</c> section names: its link, or by default the routine the topic is an
    ///  entry into.
    /// </summary>
    private DocumentationTopic? InheritTarget(DocumentationTopic topic, DocumentationSection inherit)
    {
        List<DocumentationLink> links = DocumentationText.Links(inherit.Text);
        if (links.Count != 0)
        {
            return Resolve(topic, links[0].Target).Topic;
        }

        return topic.Set.Topics.FirstOrDefault(candidate => !ReferenceEquals(candidate, topic)
            && candidate.EntryLabels.Contains(topic.Name, StringComparer.Ordinal));
    }

    /// <summary>
    ///  Reads the topic an <c>Include:</c> section names, as <c>path#Title</c>.
    /// </summary>
    private DocumentationTopic? Included(DocumentationTopic topic, DocumentationSection include)
    {
        List<DocumentationLink> links = DocumentationText.Links(include.Text);
        string target = links.Count != 0 ? links[0].Target : include.Text;
        int hash = target.IndexOf('#');
        string file = hash < 0 ? target : target[..hash];
        string? title = hash < 0 ? null : target[(hash + 1)..];
        if (FindFile(topic.Path, file) is not { } path || _readText(path) is not { } text) { return null; }
        IReadOnlyList<DocumentationComment> topics = DocumentationParser.ParseTopics(text, path);
        DocumentationComment? found = title is null
            ? topics.FirstOrDefault()
            : topics.FirstOrDefault(candidate => candidate.Name.Equals(title, StringComparison.OrdinalIgnoreCase));

        return found is null
            ? null
            : new DocumentationTopic
            {
                Name = found.Name,
                Kind = DocumentationKind.Topic,
                Set = topic.Set,
                Comments = [found],
                Summary = found.Summary,
                Remarks = found.Remarks,
                Sections = found.Sections
            };
    }

    private static DocumentationTopic Combine(DocumentationTopic local, DocumentationTopic inherited, IReadOnlyList<string> sections)
    {
        bool Wanted(DocumentationSection section) =>
            sections.Count == 0 || sections.Contains(section.Name, StringComparer.OrdinalIgnoreCase);

        List<DocumentationSection> merged = [];
        foreach (DocumentationSection section in inherited.Sections)
        {
            bool overridden = local.Sections.Any(own => own.Name.Equals(section.Name, StringComparison.OrdinalIgnoreCase));
            if (!overridden && Wanted(section) && section.Name is not ("Inherit" or "Include")) { merged.Add(section); }
        }

        merged.AddRange(local.Sections.Where(section => section.Name is not ("Inherit" or "Include")));
        List<string> remarks = [.. inherited.Remarks];
        if (remarks.Count != 0 && local.Remarks.Count != 0) { remarks.Add(""); }
        remarks.AddRange(local.Remarks);
        return new DocumentationTopic
        {
            Name = local.Name,
            Kind = local.Kind,
            Set = local.Set,
            Comments = local.Comments,
            Summary = local.Summary.Length != 0 ? local.Summary : inherited.Summary,
            Remarks = remarks,
            Sections = merged,
            Value = local.Value,
            InheritedFrom = inherited
        };
    }
}
