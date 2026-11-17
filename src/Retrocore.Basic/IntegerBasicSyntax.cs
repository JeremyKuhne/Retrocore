// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Basic;

/// <summary>
///  Integer BASIC's tokenizer, and Apple-1 BASIC's: their syntax tables, matched against a typed line exactly as
///  the ROM's tokenizer ($E3ED-$E51A, the same in both) matches them.
/// </summary>
/// <remarks>
///  <para>
///   Integer BASIC checks a line's syntax as it tokenizes it, and a keyword's token is the place in the syntax tables
///   where it matched, so tokenizing takes the grammar itself. This is the ROM's backtracking matcher step for step,
///   over the ROM's own table bytes ($EC00-$EDFF, and SYNTABLNDX at $F197), with the page-zero locations it shares
///   with the rest of BASIC modeled where the ROM keeps them, so even its overlaps behave as they do on the machine.
///   A test compares the tables with the SDK's build of the ROM, and the tokens with the ROM's own tokenizing.
///  </para>
///  <para>
///   Two things are added for the editor: letters outside strings and remarks are matched as capitals, as the Apple
///   II's keyboard types them, and each token records the character it was made from.
///  </para>
/// </remarks>
internal static class IntegerBasicSyntax
{
    /// <summary>
    ///  The most characters a line can have: the tokens follow the text in the 256-byte input buffer, so a long line
    ///  is TOO LONG sooner.
    /// </summary>
    internal const int MaximumLength = 255;


    /// <summary>
    ///  Integer BASIC's syntax tables, $EC00-$EDFF, and SYNTABLNDX at $F197, from the ROM.
    /// </summary>
    internal static IntegerSyntaxTables Integer { get; } = new(
        Convert.FromHexString("""
        50204FC0F4A1E4AFADF2AFE4AEA1F0A5B4B3EFB4EEA5A8B45C800040608D608B7F1D207E8C3300006003BF124783AEA9
        6783B2B0E5A3A1B2B479B0B3A469B0B3A4E5A3A1B2B4AFAE79B0B3A4AFAE69B0B3A4AFAEF0AFB0F4B3A9AC608C20B4B3
        A9AC004089C9479D17689D0A587B67A2A1B4B667B4A1078C07AEA9ACB667B4A1078C07AEA9ACA8678C07B4AFACB0679D
        B2AFACAFA3678C07A5ABAFB0F4AEA9B2B07F0E27B4AEA9B2B07F0E28B4AEA9B2B06407A6A967AFB4AFA778B4A5AC6B7F
        02ADA5B267A2B5B3AFA7EEB2B5B4A5B27E8C39B4B8A5AE67B0A5B4B327AFB4079D19B2AFA67F0537B4B5B0AEA97F0528
        B4B5B0AEA97F052AB4B5B0AEA9E4AEA50047A2A1B47F0D30ADA9A47F0D23ADA9A467ACACA1A3F2A7F4B8A5B4004DCC67
        8C688CDB679B689B508C638C7F01510788298480C419577107881471078C0788AEB2A3B3710888A3B3A1710888AEA5AC
        688308689D087107886075B4AFAE758D758B51078819B8A4AEB2ECA4B0F3A2A1EEA7B3E4AEB2EBA5A5B05107883981C1
        4F7F0F2F0051068829C20C82578C6A8C42AEA5A8B460AEA5A8B44F7E1E358C27510788098BFEE4AFADF2AFE4AEA1DCDE
        9CDD9CDEDD9EC3DDCFCACDCB00479AADA5ADAFAC679AADA5ADA9A8EEA1AD608C20AFB4B5A1F2ACA3F7A5AE608C20ACA5
        A4EEB5B260AEB5B2EEAFA3E5B6A1B3E4A1AFAC7A7E9A2220006003BF6003BF1F
        """.ReplaceLineEndings(string.Empty)),
        Convert.FromHexString("C1007FD1CCC7CFCEC59A988D969593BFB232120FBCB0ACBE350C6130100BDDFB"),
        IndexStart: 0xF197,
        ReservedWords: true);

    /// <summary>
    ///  Apple-1 BASIC's syntax table, $EC00-$EDFF, with SYNTABLNDX inside it at $EC20, from the tape.
    /// </summary>
    /// <remarks>
    ///  <para>
    ///   Apple-1 BASIC has no reserved words: a name is a letter and a digit at most, so a keyword cannot run on
    ///   from one, and its tokenizer writes a matched keyword's token whatever its number.
    ///  </para>
    /// </remarks>
    internal static IntegerSyntaxTables Apple1 { get; } = Apple1Tables();

    /// <summary>
    ///  Tokenizes a typed line as Integer BASIC's command loop does.
    /// </summary>
    /// <param name="text">
    ///  The line's units, as <see cref="BasicText.Parse(string, List{int})"/> gives them: typed characters, and raw
    ///  bytes marked with <see cref="BasicText.Raw"/>.
    /// </param>
    /// <returns>The tokens, or the error the ROM reports.</returns>
    internal static IntegerSyntaxResult Tokenize(ReadOnlySpan<int> text) => Tokenize(text, Integer);

    /// <summary>
    ///  Tokenizes a typed line as a BASIC of the Integer BASIC family's command loop does, with its tables.
    /// </summary>
    /// <param name="text">The line's units.</param>
    /// <param name="tables">The BASIC's syntax tables.</param>
    /// <returns>The tokens, or the error the BASIC reports.</returns>
    internal static IntegerSyntaxResult Tokenize(ReadOnlySpan<int> text, IntegerSyntaxTables tables)
    {
        if (text.Length > MaximumLength) { return new([], [], IntegerSyntaxError.TooLong, Column: text.Length); }

        return new IntegerSyntaxMatcher(text, tables).Run();
    }

    private static IntegerSyntaxTables Apple1Tables()
    {
        byte[] table = Convert.FromHexString("""
            502013ECD015200BECD0102082E7206FE750032082E72059E756504C36E7FFFFC1FF7FD1CCC7CFCEC59A988B969593BF
            B2322D2BBCB0ACBE358E61FFFFFFDDFB20C9EF154F100520C9EF354F955010CB4CC9EF40608D608B007E8C3300006003
            BF12004089C9479D17689D0A0040608D608B007E8C3C00006003BF1B4B67B4A1078C07AEA9ACA8678C07B4AFACB0679D
            B2AFACAFA3678C07A5ABAFB0F4AEA9B2B07F0E27B4AEA9B2B07F0E28B4AEA9B2B06407A6A967AFB4AFA778B4A5AC787F
            02ADA5B267A2B5B3AFA7EEB2B5B4A5B27E8C39B4B8A5AE67B0A5B4B327AFB4079D19B2AFA67F0537B4B5B0AEA97F0528
            B4B5B0AEA97F052AB4B5B0AEA9E4AEA500FFFF47A2A1B47F0D30ADA9A47F0D23ADA9A467ACACA1A3004080C0C1800047
            8C688CDB679B689B508C638C7F01510788298480C4805771078814EDA5ADAFACEDA5ADA9A8F2AFACAFA3710888AEA5AC
            688308689D087107886076B4AFAE768D768B51078819B8A4AEB2F2B3B5F3A2A1EEA7B3E4AEB2EBA5A5B05107883981C1
            4F7F0F2F0051068829C20C82578C6A8C42AEA5A8B460AEA5A8B44F7E1E358C27510788098BFEE4AFADF2AFE4AEA1DCDE
            9CDD9CDEDD9EC3DDCFCACDCB00479DADA5ADAFAC769DADA5ADA9A8E6A6AF608C20AFB4B5A1F2ACA3F2A3B3608C20ACA5
            A4EEB5B260AEB5B2F4B3A9AC608C20B4B3A9AC7A7E9A2220006003BF6003BF1F
            """.ReplaceLineEndings(string.Empty));

        return new(table, table[0x20..0x40], IndexStart: 0xEC20, ReservedWords: false);
    }
}
