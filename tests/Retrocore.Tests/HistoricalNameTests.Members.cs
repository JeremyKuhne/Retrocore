// Copyright (c) 2025 Jeremy W Kuhne
// SPDX-License-Identifier: MIT
// See LICENSE file in the project root for full license information

using Retrocore.Assembler;
using Retrocore.Debug;
using Retrocore.Documentation;
using NativeAssembler = Retrocore.Assembler.Assembler;

namespace Retrocore.Tests;

// Historical names of the members of a .struct, .union or .enum, each documented by a ;; block of its own
// (docs/backlog/MemberDocumentation.md).
public sealed partial class HistoricalNameTests
{
    // The backlog item's probe: documented struct fields and enum members, with old names code uses.
    private const string Probe = """
        ; retrocore: style=strict
        ;; A probe.

        .cpu Mos6502
        .org $0300

        ;; An I/O block.
        .struct Iob
            ;; The block's type.
            ;; Also: IBTYPE (TEST)
            TYPE .byte
            ;; The command.
            ;; Also: IBCMD (TEST)
            COMMAND .byte
        .endstruct

        ;; The commands.
        .enum Command
            ;; Seek only.
            ;; Also: IBCNUL (TEST)
            SEEK
            ;; Read.
            ;; Also: IBCRTS (TEST)
            READ
        .endenum

        ;; Echoes <IBCMD> and <IBCRTS>.
        Echo:
            lda #IBCMD
            ldy #IBCRTS
            rts
        """;

    // The probe's union form: an anonymous union's members belong to the named type around it.
    private const string UnionProbe = """
        ; retrocore: style=strict
        ;; A probe.

        .cpu Mos6502
        .org $0300

        ;; An I/O block.
        .struct Iob
            ;; The block's type.
            ;; Also: IBTYPE (TEST)
            TYPE .byte
            .union
                ;; The command, before the call.
                ;; Also: IBCMD (TEST)
                COMMAND .byte
                ;; The status, after it.
                ;; Also: IBSTAT (TEST)
                STATUS .byte
            .endunion
            ;; The volume.
            VOLUME .byte
        .endstruct

        ;; Echoes <IBCMD>, <IBSTAT> and <Iob::VOLUME>.
        Echo:
            lda #IBCMD
            ldy #IBSTAT
            ldx #Iob::VOLUME
            rts
        """;

    /// <summary>
    ///  The probe: members' old names assemble to their offsets and values, each member's block is a topic named as
    ///  the assembler names it, links by old name reach it, and the strict file is clean.
    /// </summary>
    [TestMethod]
    public void TheMemberProbeWorks()
    {
        AssemblyResult result = AssembleProbe(Probe);
        result.Diagnostics.Should().BeEmpty();
        result.Sections[0].Bytes.Span[..5].ToArray().Should().Equal(0xA9, 1, 0xA0, 1, 0x60);

        DocumentationSet set = ProbeSet(Probe);
        DocumentationTopic command = Required(set.Find("Iob::COMMAND"));
        command.Kind.Should().Be(DocumentationKind.Member);
        DocumentationAlso.Of(command.Sections).Select(also => also.Name).Should().Equal("IBCMD");

        DocumentationResolver resolver = new(set) { Bibliography = DocumentationBibliography.Parse(Bibliography) };
        DocumentationTopic echo = Required(set.Find("Echo"));
        Required(resolver.Resolve(echo, "IBCMD").Topic).Name.Should().Be("Iob::COMMAND");
        Required(resolver.Resolve(echo, "IBCRTS").Topic).Name.Should().Be("Command::READ");
        resolver.Check().Should().BeEmpty();
    }

    /// <summary>
    ///  The union form: the members of an anonymous union inside a named type are the type's, in the documentation as
    ///  in the assembler, and the strict file is clean.
    /// </summary>
    [TestMethod]
    public void UnionMembersAreTheTypes()
    {
        AssemblyResult result = AssembleProbe(UnionProbe);
        result.Diagnostics.Should().BeEmpty();
        result.Sections[0].Bytes.Span[..7].ToArray().Should().Equal(0xA9, 1, 0xA0, 1, 0xA2, 2, 0x60);

        DocumentationSet set = ProbeSet(UnionProbe);
        Required(set.Find("Iob::COMMAND")).Kind.Should().Be(DocumentationKind.Member);
        Required(set.Find("Iob::STATUS")).Kind.Should().Be(DocumentationKind.Member);
        set.Find("COMMAND").Should().BeNull();
        TopicsMatchSymbols(set, result);

        DocumentationResolver resolver = new(set) { Bibliography = DocumentationBibliography.Parse(Bibliography) };
        DocumentationTopic echo = Required(set.Find("Echo"));
        Required(resolver.Resolve(echo, "IBSTAT").Topic).Name.Should().Be("Iob::STATUS");
        Required(resolver.Resolve(echo, "Iob::COMMAND").Topic).Name.Should().Be("Iob::COMMAND");
        resolver.Check().Should().BeEmpty();
    }

    /// <summary>
    ///  Members' old names assemble in every form a member takes: a struct field, an anonymous union's or struct's
    ///  field, an enum member, a field reserved with <c>.tag</c>, and a named nested struct's field.
    /// </summary>
    [TestMethod]
    public void MemberOldNamesAssemble()
    {
        string text = """
                lda #OLDFIRST
                lda #OLDCHOICE
                lda #OLDINNER
                lda #OLDWHERE
                lda #OLDDEEP
                lda #OLDREAD
                rts

            ;; A pair.
            .struct Pair
                ;; The low byte.
                LOW .byte
                ;; The high byte.
                HIGH .byte
            .endstruct

            ;; A record.
            .struct Record
                ;; The first byte.
                ;; Also: OLDFIRST (TEST)
                FIRST .byte
                .union
                    ;; A choice.
                    ;; Also: OLDCHOICE (TEST)
                    CHOICE .word
                    ;; The other.
                    OTHER .byte
                .endunion
                .struct
                    ;; Inside an anonymous struct.
                    ;; Also: OLDINNER (TEST)
                    INNER .byte
                .endstruct
                ;; Where.
                ;; Also: OLDWHERE (TEST)
                WHERE .tag Pair
                ;; A nested type.
                .struct Nested
                    ;; Deep inside it.
                    ;; Also: OLDDEEP (TEST)
                    DEEP .byte
                    ;; Deeper.
                    DEEPER .byte
                .endstruct
            .endstruct

            ;; The commands.
            .enum Command
                ;; Seek.
                SEEK
                ;; Read.
                ;; Also: OLDREAD (TEST)
                READ = 5
            .endenum
            """;

        AssemblyResult result = Assemble(text);
        result.Diagnostics.Should().BeEmpty();
        result.Sections[0].Bytes.Span[..13].ToArray().Should().Equal(
            0xA9, 0, 0xA9, 1, 0xA9, 3, 0xA9, 4, 0xA9, 0, 0xA9, 5, 0x60);

        result.Symbols["Record::Nested::DEEP"].Should().Be(0);
        result.Symbols.Should().NotContainKey("OLDDEEP");

        DocumentationSet set = Set(text);
        foreach (string name in (string[])["Record::FIRST", "Record::CHOICE", "Record::OTHER", "Record::INNER", "Record::WHERE",
            "Record::Nested::DEEP", "Record::Nested::DEEPER", "Command::SEEK", "Command::READ"])
        {
            Required(set.Find(name)).Kind.Should().Be(DocumentationKind.Member, name);
        }

        Required(set.Find("Record::Nested")).Kind.Should().Be(DocumentationKind.Struct);
        TopicsMatchSymbols(set, result);
        Required(set.Find("Record")).Primary.Members.Should().Equal("FIRST", "CHOICE", "OTHER", "INNER", "WHERE", "Nested");
    }

    /// <summary>
    ///  A definition of the same name wins over a member's old name.
    /// </summary>
    [TestMethod]
    public void DefinitionsWinOverMembersOldNames()
    {
        AssemblyResult result = Assemble("""
                lda #IBCMD
                rts
            IBCMD = 7

            ;; A block.
            .struct Iob
                ;; The type.
                TYPE .byte
                ;; The command.
                ;; Also: IBCMD (TEST)
                COMMAND .byte
            .endstruct
            """);

        result.Diagnostics.Should().BeEmpty();
        result.Sections[0].Bytes.Span[..2].ToArray().Should().Equal(0xA9, 7);
    }

    /// <summary>
    ///  A member's block gets the checks any definition's does: the <c>Also:</c> form and documents, another
    ///  definition's name, and an old name another member or definition has too. A member's own plain name may be
    ///  its old name, since it does not resolve outside the type, and members of the same plain name in two types do
    ///  not clash.
    /// </summary>
    [TestMethod]
    public void MembersAlsoSectionsAreChecked()
    {
        DocumentationSet set = Set("""
            ;; Something else.
            Other = 1

            ;; A constant.
            ;; Also: SHARED (TEST)
            Constant = 2

            ;; A block.
            .struct Iob
                ;; The command.
                ;; Also: COMMAND (TEST), Other (TEST), IBCMD (NOPE), PLAIN
                COMMAND .byte
                ;; The volume.
                ;; Also: OLDVOL (TEST), SHARED (TEST), COMMAND (TEST), Iob::VOL (TEST)
                VOLUME .byte
            .endstruct

            ;; The file manager's parameters.
            .struct FileParameters
                ;; The volume.
                ;; Also: OLDVOL (TEST)
                VOLUME .byte
            .endstruct

            ;; Uses <IBCMD>, <Iob::VOLUME> and <FileParameters::VOLUME>.
            Echo:
                rts
            """);

        DocumentationResolver resolver = new(set) { Bibliography = DocumentationBibliography.Parse(Bibliography) };
        resolver.Check().Select(diagnostic => diagnostic.Message).Should().BeEquivalentTo(
            "Also: Other is also a definition, which code reaches instead of Iob::COMMAND.",
            "Also: no document 'NOPE' in the bibliography.",
            "Also: say which document PLAIN comes from, as 'PLAIN (A2RM)'.",
            "Also: FileParameters::VOLUME has the historical name OLDVOL too.",
            "Also: Constant has the historical name SHARED too.",
            "Also: Iob::VOLUME has the historical name OLDVOL too.",
            "Also: Iob::VOLUME has the historical name SHARED too.",
            "Also: COMMAND is also Iob::COMMAND, a member of the same type, which it would not mean.",
            "Also: Iob::VOLUME has the historical name COMMAND too.",
            "Also: a historical name is a plain name, as a listing wrote it, not 'Iob::VOL (TEST)'.");
    }

    /// <summary>
    ///  A member documented by a block or a trailing comment of its own is not also listed in its type's
    ///  <c>Members:</c>, and a member cannot have both.
    /// </summary>
    [TestMethod]
    public void DocumentedMembersAreNotListed()
    {
        DocumentationSet set = Set("""
            ;; A block.
            ;; Members:
            ;;   TYPE = the type
            ;;   COMMAND = the command
            ;;   VOLUME = the volume
            ;;   status = the status
            .struct Iob
                ;; The type, documented here.
                TYPE .byte
                COMMAND .byte ;; The command, documented here.
                VOLUME .byte
                .union
                    ;; The status.
                    STATUS .byte
                .endunion
            .endstruct
            """);

        new DocumentationResolver(set).Check().Select(diagnostic => diagnostic.Message).Should().BeEquivalentTo(
            "TYPE has its own documentation; remove it from Members:",
            "COMMAND has its own documentation; remove it from Members:",
            "status has its own documentation; remove it from Members:");

        DocumentationParser.Parse("""
            ;; A block.
            .struct Iob
                ;; The command.
                COMMAND .byte ;; Also the command.
            .endstruct
            """, "test.asm").Diagnostics.Select(diagnostic => diagnostic.Message).Should().ContainSingle()
            .Which.Should().StartWith("A documentation comment cannot document a definition that has its own trailing documentation");
    }

    /// <summary>
    ///  Conditional assembly sees a member's old name, as it sees other definitions'.
    /// </summary>
    [TestMethod]
    public void ConditionsSeeMembersOldNames()
    {
        AssemblyResult result = Assemble("""
            ;; A block.
            .struct Iob
                ;; The type.
                TYPE .byte
                .union
                    ;; The command.
                    ;; Also: IBCMD (TEST)
                    COMMAND .byte
                .endunion
            .endstruct
            .ifdef IBCMD
            .if IBCMD = 1
                nop
            .endif
            .endif
            """);

        result.Diagnostics.Should().BeEmpty();
        result.Sections[0].Bytes.Span[0].Should().Be(0xEA);
    }

    /// <summary>
    ///  The debugger resolves a member's old name, in a watch or expression, to the member's value.
    /// </summary>
    [TestMethod]
    public void TheDebuggerResolvesMembersOldNames()
    {
        SourceMapModule module = new(AssembleProbe(UnionProbe), area: null);
        module.TryResolve("Iob::STATUS", out long qualified).Should().BeTrue();
        qualified.Should().Be(1);
        module.TryResolve("IBSTAT", out long old).Should().BeTrue();
        old.Should().Be(1);
        module.TryResolve("IBCRTS", out _).Should().BeFalse();
    }

    /// <summary>
    ///  The debugger resolves a label's and a <c>.set</c> variable's old names, the variable's to the value it had
    ///  where it was documented, and an old name ahead of a scoped member's plain name, as code does; a name two
    ///  definitions give resolves to neither.
    /// </summary>
    [TestMethod]
    public void TheDebuggerResolvesOldNamesAsCodeDoes()
    {
        AssemblyResult result = Assemble("""
                lda #STATUS
                rts
            ;; Prints.
            ;; Also: COUT (TEST)
            Print:
                rts
            ;; A count.
            ;; Also: OLDCOUNT (TEST)
            Counter .set 3
            Counter .set 4
            ;; An error code.
            ;; Also: STATUS (TEST), SHARED (TEST)
            ErrorCode = 9
            ;; Another.
            ;; Also: SHARED (TEST)
            Other = 8

            ;; A block.
            .struct Iob
                ;; The type.
                TYPE .byte
                ;; The status.
                STATUS .byte
            .endstruct
            """);

        result.Diagnostics.Should().BeEmpty();
        result.Sections[0].Bytes.Span[..2].ToArray().Should().Equal(0xA9, 9);
        result.HistoricalNames["OLDCOUNT"].Location?.Line.Should().Be(8);

        SourceMapModule module = new(result, area: null);
        module.TryResolve("COUT", out long print).Should().BeTrue();
        print.Should().Be(0x1003);
        module.TryResolve("OLDCOUNT", out long count).Should().BeTrue();
        count.Should().Be(3);
        module.TryResolve("STATUS", out long status).Should().BeTrue();
        status.Should().Be(9);
        module.TryResolve("SHARED", out _).Should().BeFalse();
    }

    /// <summary>
    ///  A member that opens a nested type (<c>INNER .struct Inner</c>) takes its old names; a named type's own
    ///  <c>Also:</c> names nothing, as a scope's does, and its hidden scope label is never published.
    /// </summary>
    [TestMethod]
    public void TypesHaveNoOldNamesButTheirMembersDo()
    {
        const string text = """
                lda #OINNER
                rts

            ;; An outer type.
            .struct Outer
                ;; The first byte.
                FIRST .byte
                ;; The nested part.
                ;; Also: OINNER (TEST)
                INNER .struct Inner
                    ;; Deep inside it.
                    DEEP .byte
                .endstruct
                ;; A nested type of its own.
                ;; Also: OLDIN (TEST)
                .struct Named
                    ;; Its byte.
                    BYTE .byte
                .endstruct
            .endstruct
            """;

        AssemblyResult result = Assemble(text);
        result.Diagnostics.Should().BeEmpty();
        result.Sections[0].Bytes.Span[..2].ToArray().Should().Equal(0xA9, 1);
        result.HistoricalNames.Keys.Should().Equal("OINNER");
        Required(Set(text).Find("Outer")).Primary.Members.Should().Equal("FIRST", "INNER", "Named");

        // The editor and links do not reach a type by its Also: either.
        Set(text).FindAlso("OLDIN").Should().BeEmpty();
        Required(Set(text).FindAlso("OINNER").SingleOrDefault()).Name.Should().Be("Outer::INNER");
        new DocumentationResolver(Set(text)).Check().Select(diagnostic => diagnostic.Message).Should().Equal(
            "Also: Outer::Named is a scope or type, which an old name cannot reach; give old names to its members.");

        Assemble("""
            ;; A type.
            ;; Also: OLDTYPE (TEST)
            .struct Named
                ;; Its byte.
                BYTE .byte
            .endstruct
                lda #OLDTYPE
            """).Diagnostics.Should().ContainSingle().Which.Message.Should().Contain("OLDTYPE");
    }

    /// <summary>
    ///  A member's own plain name may be its old name, which code outside the type reaches it by.
    /// </summary>
    [TestMethod]
    public void MembersOwnNamesCanBeOldNames()
    {
        const string text = """
                lda #COMMAND
                rts

            ;; A block.
            .struct Iob
                ;; The type.
                TYPE .byte
                ;; The command.
                ;; Also: COMMAND (TEST)
                COMMAND .byte
            .endstruct
            """;

        AssemblyResult result = Assemble(text);
        result.Diagnostics.Should().BeEmpty();
        result.Sections[0].Bytes.Span[..2].ToArray().Should().Equal(0xA9, 1);
        DocumentationSet set = Set(text);
        DocumentationResolver resolver = new(set) { Bibliography = DocumentationBibliography.Parse(Bibliography) };
        resolver.Check().Should().BeEmpty();
    }

    /// <summary>
    ///  Definitions inside an anonymous scope keep their old names: only a type's hidden scope label is passed over.
    /// </summary>
    [TestMethod]
    public void AnonymousScopesKeepOldNames()
    {
        AssemblyResult result = Assemble("""
                jmp OLDX
            .scope
            ;; Inner.
            ;; Also: OLDX (TEST)
            Inner:
                lda #OLDK
                rts
            ;; A constant.
            ;; Also: OLDK (TEST)
            KONST = 7
            .endscope
            """);

        result.Diagnostics.Should().BeEmpty();
        result.Sections[0].Bytes.Span[..6].ToArray().Should().Equal(0x4C, 0x03, 0x10, 0xA9, 7, 0x60);
    }

    /// <summary>
    ///  The debugger resolves the old names of definitions inside an anonymous scope.
    /// </summary>
    [TestMethod]
    public void TheDebuggerResolvesOldNamesInAnonymousScopes()
    {
        AssemblyResult result = Assemble("""
                rts
            .scope
            ;; Inner.
            ;; Also: OLDX (TEST)
            Inner:
                rts
            ;; A constant.
            ;; Also: OLDK (TEST)
            KONST = 7
            .endscope
            """);

        result.Diagnostics.Should().BeEmpty();
        SourceMapModule module = new(result, area: null);
        module.TryResolve("OLDX", out long inner).Should().BeTrue();
        inner.Should().Be(0x1001);
        module.TryResolve("OLDK", out long constant).Should().BeTrue();
        constant.Should().Be(7);
    }

    /// <summary>
    ///  A definition whose own name looks like a hidden scope label keeps its old names: only a type's .scope
    ///  statement is passed over.
    /// </summary>
    [TestMethod]
    public void NamesLikeHiddenLabelsKeepOldNames()
    {
        AssemblyResult result = Assemble("""
                lda #OLDREAL
                rts
            ;; A constant with a reserved-looking name.
            ;; Also: OLDREAL (TEST)
            __retro_scope_start = 5
            """);

        result.Diagnostics.Should().BeEmpty();
        result.Sections[0].Bytes.Span[..2].ToArray().Should().Equal(0xA9, 5);
    }

    // The probes set their own origin.
    private static AssemblyResult AssembleProbe(string text) =>
        new NativeAssembler().Assemble(
            new AssemblySource(text, "test.asm"),
            new AssemblyOptions(ProcessorVariant.Mos6502, origin: 0x0300, imageSize: 0x100));

    private static DocumentationSet ProbeSet(string text) =>
        DocumentationSet.Create([DocumentationParser.Parse(text, "test.asm")], AssembleProbe(text));

    // Each member's topic is named as the assembler names its symbol.
    private static void TopicsMatchSymbols(DocumentationSet set, AssemblyResult result)
    {
        foreach (DocumentationTopic topic in set.Topics.Where(topic => topic.Kind == DocumentationKind.Member))
        {
            result.Symbols.Should().ContainKey(topic.Name);
        }
    }
}
