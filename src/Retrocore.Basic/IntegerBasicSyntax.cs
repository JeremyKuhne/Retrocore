// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

namespace Retrocore.Basic;

/// <summary>
///  Integer BASIC's tokenizer: its syntax tables, matched against a typed line exactly as the ROM's tokenizer
///  ($E3ED-$E51A) matches them.
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
    ///  The syntax tables, $EC00-$EDFF, from the ROM.
    /// </summary>
    internal static readonly byte[] s_table = Convert.FromHexString("""
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
        """.ReplaceLineEndings(string.Empty));

    /// <summary>
    ///  Where each of the 32 rules starts (SYNTABLNDX, $F197), from the ROM.
    /// </summary>
    internal static readonly byte[] s_index = Convert.FromHexString("C1007FD1CCC7CFCEC59A988D969593BFB232120FBCB0ACBE350C6130100BDDFB");

    /// <summary>
    ///  Tokenizes a typed line as Integer BASIC's command loop does.
    /// </summary>
    /// <param name="text">
    ///  The line's units, as <see cref="BasicText.Parse(string, List{int})"/> gives them: typed characters, and raw
    ///  bytes marked with <see cref="BasicText.Raw"/>.
    /// </param>
    /// <returns>The tokens, or the error the ROM reports.</returns>
    internal static IntegerSyntaxResult Tokenize(ReadOnlySpan<int> text)
    {
        if (text.Length > MaximumLength) { return new([], [], IntegerSyntaxError.TooLong, Column: text.Length); }

        return new IntegerSyntaxMatcher(text).Run();
    }
}
