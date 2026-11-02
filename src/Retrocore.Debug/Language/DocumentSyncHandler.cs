// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Debug.Language;

/// <summary>
///  Keeps the workspace's copy of each open document current.
/// </summary>
internal sealed class DocumentSyncHandler
{
    private readonly LanguageWorkspace _workspace;
    private readonly BasicDocuments _basic;

    /// <summary>
    ///  Creates the handler.
    /// </summary>
    /// <param name="workspace">The workspace.</param>
    /// <param name="basic">The open BASIC documents.</param>
    public DocumentSyncHandler(LanguageWorkspace workspace, BasicDocuments basic)
    {
        _workspace = workspace;
        _basic = basic;
    }

    /// <inheritdoc/>
    /// <summary>
    ///  Handles <c>textDocument/didOpen</c>.
    /// </summary>
    /// <remarks>
    ///  <para>
    ///   BASIC documents need not be files, such as the machine's program, so they are kept apart by URI.
    ///  </para>
    /// </remarks>
    /// <param name="request">The request's params.</param>
    public void Open(LspParams request)
    {
        if (LanguageHost.IsBasic(request.TextDocument.LanguageId))
        {
            _basic.Update(request.TextDocument.Uri, request.TextDocument.LanguageId, request.TextDocument.Text);
        }
        else
        {
            _workspace.Update(LanguageHost.PathOf(request.TextDocument.Uri), request.TextDocument.Text);
        }
    }

    /// <summary>
    ///  Handles <c>textDocument/didChange</c>: with full sync, the last change is the whole text.
    /// </summary>
    /// <param name="request">The request's params.</param>
    public void Change(LspParams request)
    {
        // Full synchronization: the last change holds the whole text.
        if (request.ContentChanges.LastOrDefault() is { } change && !_basic.Change(request.TextDocument.Uri, change))
        {
            _workspace.Update(LanguageHost.PathOf(request.TextDocument.Uri), change);
        }
    }

    /// <summary>
    ///  Handles <c>textDocument/didClose</c>.
    /// </summary>
    /// <param name="request">The request's params.</param>
    public void Close(LspParams request)
    {
        if (!_basic.Close(request.TextDocument.Uri))
        {
            _workspace.Close(LanguageHost.PathOf(request.TextDocument.Uri));
        }
    }
}
