# MBASIC: naming log

`src/Retrocore.Machines.Kaypro/Roms/Mbasic/`: Microsoft's BASIC-80 5.21 for CP/M, `MBASIC.COM`, in 19 modules and
`Equates.asm`, assembling byte for byte to the program (`KayproTests.MbasicSourceMatchesMbasicCom`). Its labels are
**named but not yet converted** to the maintained style: each is Microsoft's own name where one is known, not a
current name with the old one in `Also:` ([ConvertingSources.md](../ConvertingSources.md)). This log records where
each name came from, so that the conversion can cite the right document for each `Also:`, and knows which names are
the SDK's and which Microsoft names are in doubt.

## Sources and citations

- **GW**: [GW-BASIC's MIT-licensed source](https://github.com/microsoft/GW-BASIC), Microsoft's 8086 BASIC, translated
  from the same 8080 source as MBASIC, whose routines it holds in nearly the same order under the same names. MBASIC
  lacks GW-BASIC's graphics, sound and PC hardware code.
- **L2**: [Level2.asm](../../src/Retrocore.Machines.Trs80/Roms/Level2.asm), the SDK's TRS-80 Level II BASIC: Z80
  Microsoft BASIC of the same family, with its math package and much of its interpreter the same code. It supplied
  names where the GW files read (below) lost them: the math package's, EDIT's and the FAC's parts.
- **Memory**: names recalled from Microsoft's 8080 source, found in neither GW nor L2. They are listed under
  [Microsoft names in doubt](#microsoft-names-in-doubt) until a source confirms them.
- **SDK**: descriptive names made for this source, in Microsoft's style (uppercase, at most six or so letters), where
  no Microsoft name was found.

**Only part of GW was read.** The naming used 17 of GW's files: GWMAIN, GWEVAL, GWLIST and GWSTS (MBASIC's BINTRP),
BIMISC, BISTRS, BIPTRG, BIPRTU, MATH1, MATH2, NEXT86, DSKCOM, FIVEO, GWDATA, GWRAM, GWINIT and IBMRES. The repository
has more, among them these, which hold MBASIC's routines: GIO86 (PRINT and the file-number routines), GIODSK and GIOCOM (disk files),
CALL86 (CALL), SCNEDT (the line editor's entries), and GIOCON and GIOLPT (console and printer). The review of this log
searched all of GW for every name below, and the tables say where a name the naming took from L2 or memory, or made
itself, is in GW too; what that search cannot do is match the unread files' routines to MBASIC's. Names in those files that were never matched to MBASIC's code are the first
[open question](#open-questions).

## How it was done

The source was first disassembled with the SDK's hints and named only where the dialect and the debugger needed names
(the tables, the statement and function handlers, the error entries and the interpreter's core). It was then split
by GW-BASIC's modules into 19 files, and each group of one or two was named and documented by its own agent, in its own
copy, with one brief: Microsoft's names by matching the code against GW and L2, descriptive ones where neither has a
name, every routine documented, operands that are addresses made symbols, and the bytes unchanged after every step.
Integration merged the groups' rename maps, settled the names they clashed on (MN4), moved routines that fall into
the next module, and named the tokens, error codes and crunched constants in `Equates.asm`.

## Decisions

The IDs are MN.

- MN1. Microsoft's name wherever GW has the routine or variable at that place in the code; L2's where the GW files
  read have no counterpart (the math package, EDIT, the FAC's bytes).
- MN2. Statement and function handlers are named for their keyword, `ST_FOR` and `FN_LEFT`, as in Level2.asm, not by
  Microsoft's names for them (`FOR`, `LEFT$`, `CALLS`), which are not valid labels or clash with the tokens.
- MN3. A label inside a routine that Microsoft did not name is named after its routine, `FN_CINT_4`, the SDK's rule.
  These are not listed below.
- MN4. Where two modules both have a Microsoft local of the same name, it stays in the module it is most known for and
  the other takes a variant:
  - `STR1` stays in Strings.asm (BISTRS's `STR$1`, with the `$` dropped as in MN5); CRUNCH's in Interpreter.asm is `KRNSTR`, after CRUNCH's other K labels.
  - `FCERRG` stays in List.asm (DELETE's); CHAIN's check in Chain.asm is `CHNFCG`.
  - `NOTSPC` stays in Console.asm (PRINT USING's); LINE INPUT #'s in Disk1.asm is `NTSPCI`.
  - `FOUTFX` stays the routine in Math3.asm (L2's); the variable in Storage.asm that selects FOUT's fixed-notation pass
    is `FOUFIX`. GW's order suggests `FLGSCN` (GWDATA) at that address, unconfirmed.
- MN5. One label where GW has several at one address: `HOCFIN` (Evaluator.asm) stands for GW's `HEXFIN`, `OCTFIN` and
  `HOCFIN`, and `NXTDO` (Misc.asm) for `NXTDO` and `NXTDOA`. GW's `ISMID$` is `ISMID`, as `$` is not a label's
  character.
- MN6. `STPEND` is at `$4416`, where Microsoft (and L2) have it: Control-C's entry from INPUT, LINE INPUT and
  RANDOMIZE's prompt for a seed. The first naming had put it on `$440C`, which is Microsoft's `CONSTP`.
- MN7. The debugger looks up `NEWSTT`, `GONE`, `READY`, `ERROR`, `ST_RUN`, `ST_CONT`, `CONSTP`, `STPEND` and `ENDCON`
  ([KayproDebugTarget.Basic.cs](../../src/Retrocore.Debug/KayproDebugTarget.Basic.cs)); a conversion that renames
  them changes it too.
- MN8. Code nothing reaches keeps its label when Microsoft named it or when the label carries documentation: `DATAH`
  (Statements.asm), `CONSOL` (Evaluator.asm), and the unused constants `IN2PI` (GW's `$IN2PI`) and `FR4` (Math3.asm).
  Unlabelled dead code is commented as such: Level II's `MLDVEX` and the `LD HL,OVERR` FRCINT left in Math1.asm, the
  `DEC B` in LineInput.asm, and the "Owned by Microsoft" text in Init.asm that nothing prints.
- MN9. Tokens, function numbers and error codes are `TK_`, `TF_` and `ERR_` constants, as Level2.asm names its tokens
  and errors, with GW's suffixes for the errors (`ERRSN` is `ERR_SN`). The crunched constants' types keep GW's names,
  `OCTCON` to `DBLCON`. The BDOS functions take Digital Research's names (`F_OPEN`, `S_BDOSVER`). The file data
  block's offsets (`FD_`) are the SDK's; GW uses Microsoft's for several (`F_BREM`, with `NMLOFS=F_BREM` in DSKCOM,
  `FD_SIZ`, `FD_OPS`, `F_MODE`, `F_FCB`) without defining them in the published files, an open question below.

## Names that are not Microsoft's

SDK names, by module, with why no Microsoft name was found. Internal `_n` labels (MN3) are left out.

| Module | Names | Why |
| --- | --- | --- |
| Tables.asm | `USRCNV` | The two words at `$0103` that give a USR routine FRCINT's and MAKINT's addresses. |
| Storage.asm | `MAXSAV`, `RNDWRT`, `FILPT0`, `KBUFCOLON`, `MAXREC`, `FOUFIX`, `NULSTR` | Variables the GW files read do not have, or have under a name not found. `RNDWRT`'s meaning (write the random-record sector, rather than read it) is likely but not certain. |
| Storage.asm | `FILNAM_EXTENT`, `CONHI`, `ARYTA2_HI`, `TEMPA_HI`, `ARG_ROUND_BYTE` | Bytes inside a Microsoft variable, which GW uses as offsets (`CONLO+2`, `TEMPA+1`) where it uses them at all (it has no `FILNAM+12` or `ARYTA2+1`); a conversion may turn them back into offsets. |
| Equates.asm | `BIOSWB`, `FD_MODE` to `FD_FIELD` | CP/M's warm boot vector, which INIT reads to find the BIOS; the file data block's layout (MN9). |
| Interpreter.asm | `PUTGOS` | The `LD A` of GOSUB's token that GO TO with two or more spaces reaches. |
| Evaluator.asm | `CLMCAL`, `INPORT`, `OUTPRT`, `WAITPT` | WIDTH's last-zone calculation, and the operands INP, OUT and WAIT patch into their own instructions. |
| Variables.asm | `NAMCMP` | MBASIC's name comparison; GW-BASIC compares with `REP CMPSB` inside `LOPTOP` and `LOPFD0`. |
| Math1.asm | `LOG2` | LOG's base-2 step. |
| Math2.asm | `MLDVOV`, `FACOVP`, `FACOVF`, `UNPOVP`, `UNPOVF`, `FDIV0S`, `DDIV0S` | MBASIC's soft overflow and division by zero, which Level II lacks and GW rewrote. |
| Math2.asm | `INFP`, `INFM` | The largest numbers, after GW's `$INFPD` and `$INFMD`. |
| Math2.asm | `DTENTH`, `DADDFB`, `DHALVE`, `ARGD16`, `PSHARG`, `POPARG`, `DADDAA`, `DADDA` | Double-precision helpers with no counterpart; `DADDAA` and `DADDA` follow L2's `DADD` family for MBASIC's one self-modifying add and subtract. |
| Math3.asm | `FOUFRF`, `FOUTDZ` | MBASIC's additions to FOUT: the free-format body `FOUFRV` calls, and the variant of `FOUTED` that writes `.000` before a small number. |
| Math3.asm | `RNDADI`, `RNDMLI`, `RNDMUL`, `RNDADD`, `RNDINI`, `RNDSED`, `RNDXM` | RND's state and tables; `RNDXM` could become `RNDX+1`. |
| Console.asm | `RUBED`, `LPCRLF`, `OUTCON`, `LPTOUT`, `CHARCG` | The CP/M console and printer layer, which the GW files read replace; `RUBED` is EDIT's rubout, which Level II lacks. `CHARCG`'s note does not say clearly whether it is Microsoft's. GIOCON and GIOLPT were not read. |
| Console.asm | `FRECHK` | Checks the memory left. GW has a `FRECHK` (BIMISC) for another job, freeing an event request. |
| Console.asm | `CSTSVC`, `CSTKVC`, `CONIVC`, `CONOVC`, `LISTVC` | The call operands INIT patches with the BIOS's CONST, CONIN, CONOUT and LIST addresses. |
| Misc.asm | `INIFIL` | Marks the files closed before NEW at start-up. |
| LineInput.asm | `INLINC`, `INLEDT`, `RUBOUT`, `ECHOBS`, `INLCAN`, `INLNEW`, `INLCHR`, `GOODCH`, `INLEND` | The CP/M line editor, which GW replaced with its screen editor. Its entries `QINLIN`, `INLIN`, `SINLIN` and `SCNSEM` are Microsoft's (SCNEDT, and L2 for `QINLIN` and `INLIN`), as is `FININL` (Console.asm), which it ends through. |
| Chain.asm | `CALLS_1` to `CALLS_4`, `GETPTR_1` | Points inside CALL and `GETPTR`. GW's CALL86 has CALL's own labels (`CALLS`, `CALLSL`, `CALLS1`, `CALLST`, `GETPAR`, `ENDPAR`), not matched yet. |
| Disk1.asm | `OUTSEC` | Writes a data block's sector buffer. |
| Disk2.asm | `SEQOUT`, `RNDREC`, `MOV128`, `INDSKB`, `REDPTR`, `REDREC`, `SETDMA`, `NAMDOT`, `NAMERR`, `STARQ`, `FILLQ`, `CPMRW`, `RECLEN`, `PHYGET`, `PHYPUT`, `BLKMOV`, `RNDOUT`, `RNDIN`, `RNDFOV`, `GETRLN`, `NXTFPS`, `FLDCHK`, `PROENC`, `FILOUT` | MBASIC's CP/M file layer, the `DCPM.MAC` GW's DSKCOM refers to. The GW files read have no counterparts; GIODSK and GIOCOM, which hold GW's own disk layer, were not read, and GIODSK's `GETFSZ` has `GETRLN`'s shape. `FILOUT` was taken for Microsoft's, but neither GW nor L2 has it. |
| Init.asm | `FILDB0`, `CMDDON`, `WASMF`, `FLDPTR`, `SECPTR`, `PUTFLG`, `BYTFRE` | Start-up. GWRAM's `PUTFLG` is another byte, graphics PUT's and GET's. GWDATA has four variables, `RECRD`, `LBUFF`, `PBUFF` and `PGTFLG`, in the order and sizes of `TEMPB`, `FLDPTR`, `SECPTR` and `PUTFLG` at `$5D6F`-`$5D75`; they are likely the same and were not used, an open question below. |

## Names from Level2.asm

Where the GW files read have no counterpart, these are L2's names (MN1); a few turned out to be GW's too, as noted. The math package's names are L2's throughout,
apart from those listed above and GW's where noted in the module headers.

| Module | Names |
| --- | --- |
| Storage.asm | `CHARC`, and the FAC's and ARG's bytes `FAC_ROUND_BYTE`, `DFAC_MID`, `FACHI`, `FAC_SIGN_TEMP` and `ARGHI` (GW writes these as offsets from `DFACLO`, `FAC` and `ARG`) |
| PrintInput.asm | `ISTTY`, `ISCTTY`, `TTYIST` (PRINT's other names, `PRINTC`, `NEWCHR`, `STRDON`, `TABER` and the rest, are GW's too, in GIO86) |
| Console.asm | EDIT's command handlers (GW has a screen editor instead) |
| Variables.asm | `LOPFDA` (GW's equivalent, `ISARY`, names the subscript code here) |
| Math1.asm | `FMLTT1` and `FMLTT2`, the multiply's patched operands (GWDATA has both too) |
| Math2.asm | `DADDFO`, `DADDS`, `DADDL`, `DADDOP`, the `DADD` family on MBASIC's merged add and subtract |
| Math3.asm | `FOUFRV`, FOUT's type dispatch |

## Microsoft names in doubt

Microsoft's names whose place in MBASIC is inferred, or which came from memory (Memory) rather than a source. A
conversion should confirm each before citing it.

| Name | Module | Doubt |
| --- | --- | --- |
| `MRGFLG`, `CHNFLG` | Storage.asm | GWDATA's names, matched by the order ERROR clears them (GW: `MRGFLG` then `CHNFLG`); the two may be swapped. |
| `RUNFLG` | Storage.asm | GWDATA's name for LOAD's run flag; GW DSKCOM's comments suggest the 8080 source called it `LSTFRE`, which may belong to `$079E` or `$079F` (`MAXSAV`). |
| `ISIT`, `LENMAT` | Variables.asm | GW's closest names; MBASIC compares a name's characters in another order. |
| `FDIVC`, `FDIVB`, `FDIVA`, `FDIVG` | Math1.asm | Memory: the divide's patched operands. L2's `FDIVC` is another thing, the RAM copy of the division routine. |
| `DIV0S`, `OVFLS` | Math2.asm | GW's `$DIV0S` and `$OVFLS`, for the same job, but MBASIC's code is not GW's. |
| `EXP100`, `EXP110`, `EXP115`, `EXP200` | Math3.asm | GW's labels inside EXP, matched by role to MBASIC's new EXP. |
| `RNDCNT` | Math3.asm | GWDATA's name in RND's state; the 8080 source may give it to another of the three counter bytes. |
| `FILINP`, `FILGET`, `FILSET`, `FILSCN`, `FILIDX`, `GDFILM`, `FILID2`, `GETPTR` | Chain.asm | GW's names (GIO86 defines each), but placed from memory before GIO86 was read; each needs checking against GIO86's routine. |
| `FILFRM` | Chain.asm | Memory: GW has it only in a DSKCOM title comment. |
| `NAMFIL`, `GETFPS` | Disk2.asm | GW's names (GIODSK), which MBASIC's routines match in shape, but not checked against GIODSK when named. |
| `INDSKC`, `PRGFIL`, `PROSAV`, `PROLOD`, `PRODIR`, `PROCHK`, `FILOU3`, `CPMEXT` | Disk2.asm | GW's names (GIO86, GIODSK, GWDATA), placed by what the code does; `FILOU3`, given to SAVE's byte writer, is the least certain. |
| `CLSFIL` | Disk1.asm | GW's name (GIO86), placed by what the code does. |
| `FILNA2` | Storage.asm | GWDATA's name, placed by what the code does. |

## Open questions

- The GW files not read (above): matching their routines to MBASIC's may give Microsoft's names for the SDK's in
  Console.asm, LineInput.asm, Chain.asm (CALL) and Disk2.asm, and confirm the names placed from memory.
- Init.asm's `FLDPTR`, `SECPTR` and `PUTFLG` against GWDATA's `LBUFF`, `PBUFF` and `PGTFLG` (and `TEMPB` against
  `RECRD`): taking GWDATA's names needs only a check of how GW uses them. (GWRAM's `PUTFLG` is graphics', not this.)
- `MRGFLG` and `CHNFLG`: which is which, from how CHAIN MERGE sets them.
- `RUNFLG` or `LSTFRE` for `$079E`.
- The file data block's offsets under Microsoft's names (`F_BREM`, `FD_SIZ`, `FD_OPS` and the rest).
- The conversion itself: current names, with the names here in `Also:` citing GW, L2 or Memory.
