// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Pascal.Source;
using System.Security.Cryptography;
using System.Text;

namespace Retrocore.Tests;

/// <summary>
///  The shape of a Pascal program's code: what it compiles to, without what doesn't change that.
/// </summary>
/// <remarks>
///  <para>
///   The program's tokens in its order, each include's where the include is, without comments but with the options
///   other than includes, which change the code (in capitals, their blanks one space); each name as the
///   number of the declaration it is or refers to, so that renaming leaves the shape as it was; and a field's use as
///   one token, as which record's field it is depends on the record's type, which the model doesn't follow. A change
///   to the code changes the shape, so a test pins it where Apple's disks aren't there to compile it.
///  </para>
/// </remarks>
internal static class PascalCodeShape
{
    /// <summary>
    ///  Gets a program's shape as a SHA-256 digest.
    /// </summary>
    /// <param name="program">The program.</param>
    /// <returns>The digest, in hexadecimal.</returns>
    public static string Digest(PascalProgram program)
    {
        Dictionary<PascalToken, int> declared = [with(ReferenceEqualityComparer.Instance)];
        for (int index = 0; index < program.Declarations.Count; index++)
        {
            declared[program.Declarations[index].Token] = index;
        }

        Dictionary<PascalToken, int> used = [with(ReferenceEqualityComparer.Instance)];
        foreach (PascalReference reference in program.References)
        {
            if (program.Resolve(reference) is { } found)
            {
                used.TryAdd(reference.Token, found.Declaration.Kind == PascalDeclarationKind.Field ? -1 : declared[found.Declaration.Token]);
            }
        }

        Dictionary<PascalToken, string> includes = [with(ReferenceEqualityComparer.Instance)];
        foreach (PascalInclude include in program.Includes)
        {
            if (include.Path is { } path) { includes[include.Token] = path; }
        }

        using IncrementalHash shape = IncrementalHash.CreateHash(HashAlgorithmName.SHA256);
        IEnumerable<PascalToken> tokens = Expand(program, program.Files[0], includes, [with(StringComparer.OrdinalIgnoreCase)]);
        foreach (PascalToken token in tokens.Where(token => !token.IsComment || IsCodeOption(token, program)))
        {
            string text = token.Kind switch
            {
                PascalTokenKind.Identifier when declared.TryGetValue(token, out int at) => $"#{at}",
                PascalTokenKind.Identifier when used.TryGetValue(token, out int at) => at < 0 ? "F" : $"#{at}",
                PascalTokenKind.Identifier or PascalTokenKind.Keyword => token.Text.ToUpperInvariant(),
                PascalTokenKind.Option => string.Join(separator: ' ', token.Text.ToUpperInvariant().Split(separator: (char[]?)null, StringSplitOptions.RemoveEmptyEntries)),
                _ => token.Text
            };

            shape.AppendData(Encoding.UTF8.GetBytes(text + " "));
        }

        return Convert.ToHexString(shape.GetHashAndReset());
    }

    // An option that isn't an include, such as (*$I-*), (*$R ROUTINE*) or (*$S++*).
    private static bool IsCodeOption(PascalToken token, PascalProgram program) =>
        token.Kind == PascalTokenKind.Option && !program.Includes.Any(include => ReferenceEquals(include.Token, token));

    // A file's tokens, each include's file's in its place; a file already being expanded, included again inside
    // itself, is left out, as the model reads it once. Paths compare without case, as the model's files do.
    private static IEnumerable<PascalToken> Expand(
        PascalProgram program,
        PascalSourceFile file,
        Dictionary<PascalToken, string> includes,
        HashSet<string> expanding)
    {
        expanding.Add(file.Path);
        foreach (PascalToken token in file.Tokens)
        {
            if (includes.TryGetValue(token, out string? path)
                && !expanding.Contains(path)
                && program.File(path) is { } included)
            {
                foreach (PascalToken inner in Expand(program, included, includes, expanding)) { yield return inner; }
            }
            else
            {
                yield return token;
            }
        }

        expanding.Remove(file.Path);
    }
}
