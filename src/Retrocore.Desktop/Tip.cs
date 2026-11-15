// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Avalonia.Controls;
using Avalonia.Controls.Documents;
using Avalonia.Media;
using System.Text;
using Touki.Text;

namespace Retrocore.Desktop;

/// <summary>
///  Tooltips as VS Code's hovers draw them: Markdown, with bold, italic and code, paragraphs and bullet lists, so the
///  views' tooltips read as the extension's do.
/// </summary>
internal static class Tip
{
    /// <summary>
    ///  Escapes text shown in a tooltip's Markdown, as the extension's <c>escape</c> does.
    /// </summary>
    /// <param name="text">The text.</param>
    /// <returns>The text with <c>\</c>, <c>`</c>, <c>*</c> and <c>_</c> escaped.</returns>
    internal static string Escape(string text)
    {
        using ValueStringBuilder builder = new(stackalloc char[256]);
        foreach (char character in text)
        {
            if (character is '\\' or '`' or '*' or '_') { builder.Append('\\'); }
            builder.Append(character);
        }

        return builder.ToString();
    }

    /// <summary>
    ///  Sets a control's tooltip from Markdown.
    /// </summary>
    /// <param name="control">The control.</param>
    /// <param name="markdown">The tooltip, or null or empty for none.</param>
    internal static void Set(Control control, string? markdown)
    {
        if (string.IsNullOrEmpty(markdown))
        {
            ToolTip.SetTip(control, value: null);
            return;
        }

        ToolTip.SetTip(control, Render(markdown));
        ToolTip.SetShowDelay(control, 500);
    }

    /// <summary>
    ///  Draws Markdown as text.
    /// </summary>
    /// <param name="markdown">The Markdown.</param>
    /// <returns>A text block of it.</returns>
    internal static TextBlock Render(string markdown)
    {
        TextBlock block = new()
        {
            TextWrapping = TextWrapping.Wrap,
            MaxWidth = 500,
            FontSize = 13,
            LineHeight = 19,
        };

        InlineCollection inlines = block.Inlines ??= [];
        string[] paragraphs = markdown.Replace("\r\n", "\n", StringComparison.Ordinal)
            .Split("\n\n", StringSplitOptions.RemoveEmptyEntries);

        for (int index = 0; index < paragraphs.Length; index++)
        {
            if (index > 0)
            {
                inlines.Add(new LineBreak());
                inlines.Add(new Run(" ") { FontSize = 6 });
                inlines.Add(new LineBreak());
            }

            string[] lines = paragraphs[index].Split('\n', StringSplitOptions.RemoveEmptyEntries);
            for (int line = 0; line < lines.Length; line++)
            {
                if (line > 0) { inlines.Add(new LineBreak()); }
                string text = lines[line];
                if (text.StartsWith("- ", StringComparison.Ordinal))
                {
                    inlines.Add(new Run("  •  "));
                    text = text[2..];
                }

                AddInline(inlines, text);
            }
        }

        return block;
    }

    // Bold (**), italic (*) and code (`), with \ escaping the next character.
    private static void AddInline(InlineCollection inlines, string text)
    {
        StringBuilder run = new();
        bool bold = false;
        bool italic = false;
        bool code = false;

        void Flush()
        {
            if (run.Length == 0) { return; }
            Run piece = new(run.ToString());
            if (bold) { piece.FontWeight = FontWeight.SemiBold; }
            if (italic) { piece.FontStyle = FontStyle.Italic; }
            if (code)
            {
                piece.FontFamily = new FontFamily("Cascadia Mono, Consolas, Courier New, monospace");
                piece.FontSize = 12;
            }

            inlines.Add(piece);
            run.Clear();
        }

        for (int index = 0; index < text.Length; index++)
        {
            char character = text[index];
            if (character == '\\' && index + 1 < text.Length)
            {
                run.Append(text[++index]);
            }
            else if (character == '`')
            {
                Flush();
                code = !code;
            }
            else if (!code && character == '*' && index + 1 < text.Length && text[index + 1] == '*')
            {
                Flush();
                bold = !bold;
                index++;
            }
            else if (!code && character == '*')
            {
                Flush();
                italic = !italic;
            }
            else
            {
                run.Append(character);
            }
        }

        Flush();
    }
}