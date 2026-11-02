;; APPLE IIE EQUATES: PAGE ZERO, LOW MEMORY, SOFT SWITCHES AND KEYS
;;
;; The IIe's page-zero locations, low-memory vectors and buffers, soft switches and I/O locations, and keyboard
;; characters, with the names Apple's documentation gives them. The Monitor, both models' internal firmware, the Disk II
;; boot ROM and DOS include this file, so each name here is defined and documented once, and each of those sources
;; defines only the names that are its own. The Monitor's entry points, which the Monitor defines as labels, are in
;; MonitorEntries.asm for the others.
;;
;; Three Monitor names are not here: LOC1 and CV, which DOS uses for names of its own, are in Monitor.asm and
;; FirmwareEquates.asm, and CLRROM, a label in the Enhanced IIe's firmware, is in Monitor.asm and Firmware.Original.asm.

; Page zero: the Monitor's text window, cursor, lo-res graphics, hooks, addresses and saved registers.
;; The low byte of a pointer the Monitor borrows for short jobs.
;;
;; <Monitor:PWRUP> points <LOC0>/<Monitor:LOC1> at each slot's $Cn00 page in turn while it looks for a disk controller,
;; then jumps through them to the one it finds. <Monitor:IOPRT> stores a hook through <LOC0>,X with X = <CSWL> or
;; <KSWL>, and the self-tests in the internal firmware use it as a working pointer.
;; See: <Monitor:LOC1>, <Monitor:PWRUP>, <Monitor:IOPRT>
LOC0 = $00

;; The column where the text window starts, 0 for a full screen.
;;
;; <Monitor:SETWND> clears it, and <Monitor:VTABZ> adds it to <BASL>, so <CH> counts columns from the window's left
;; edge. In 80 columns, <Firmware:VTAB80> adds half of it, since each byte of a line then holds two columns.
;; See: <WNDWDTH>, <WNDTOP>, <WNDBTM>, <Monitor:SETWND>
WNDLFT = $20

;; The width of the text window in columns: 40, or 80 when the 80-column firmware is active.
;;
;; <Monitor:ADVANCE> starts a new line when <CH> reaches it, and <Monitor:BS> moves to the column before it on the line
;; above. The internal firmware sets it when it sets the window (<Monitor:SETWND>) or switches between 40 and 80
;; columns.
;; See: <WNDLFT>, <CH>, <Monitor:SETWND>
WNDWDTH = $21

;; The first line of the text window, 0-23.
;;
;; <Monitor:SETWND> sets it from A: <Monitor:SETTXT> gives 0, a full screen, and <Monitor:SETGR> 20, the four text lines
;; below mixed graphics. <Monitor:UP> stops at it, and <Monitor:HOME> and <Monitor:SCROLL> start there.
;; See: <WNDBTM>, <Monitor:CV>, <Monitor:SETWND>
WNDTOP = $22

;; The line below the text window, 1-24: 24 for a window that reaches the bottom of the screen.
;;
;; <Monitor:LF> scrolls the window instead of moving <Monitor:CV> to it. The internal firmware sets it to 24 when it
;; sets the window (<Monitor:SETWND>).
;; See: <WNDTOP>, <Monitor:CV>, <Monitor:LF>, <Monitor:SCROLL>
WNDBTM = $23

;; The cursor's column, counted from the window's left edge, <WNDLFT>.
;;
;; <Monitor:STORADV> stores each character at (<BASL>),Y with Y = <CH>, and <Monitor:ADVANCE>, <Monitor:BS> and
;; <Monitor:CR> move it. The 80-column firmware keeps its own column in <Firmware:OURCH>, copies it here after each
;; character, and takes up a new value a program stores here (<Firmware:SYNCCH>).
;; See: <Monitor:CV>, <BASL>, <WNDWDTH>, <Firmware:OURCH>
CH = $24

;; The low byte of the address of the text line that holds the lo-res row being drawn.
;;
;; <Monitor:GBASCALC> sets <GBASL>/<GBASH> from a row number: each text line holds two lo-res rows, one in each nibble.
;; <Monitor:PLOT1> and <Monitor:SCRN> then read and write (<GBASL>),Y with Y = the column.
;; See: <GBASH>, <Monitor:GBASCALC>, <Monitor:PLOT>, <Monitor:SCRN>
GBASL = $26

;; The high byte of the lo-res line address at <GBASL>.
;;
;; <Monitor:GBASCALC> sets it to $04-$07, the text and lo-res page one.
;; See: <GBASL>, <Monitor:GBASCALC>
GBASH = $27

;; The low byte of the address of the text line the cursor is on, plus the window's left edge.
;;
;; <Monitor:BASCALC> sets <BASL>/<BASH> from a line number, and <Monitor:VTAB> sets them for <Monitor:CV>, adding
;; <WNDLFT>. <Monitor:STORADV> then stores each character at (<BASL>),Y with Y = <CH>. On the Enhanced IIe,
;; <Monitor:VTABZ> has the internal firmware's <Firmware:VTAB80> compute them.
;; See: <BASH>, <Monitor:BASCALC>, <Monitor:VTAB>, <Monitor:CV>, <CH>
BASL = $28

;; The high byte of the text line address at <BASL>.
;;
;; <Monitor:BASCALC> sets it to $04-$07, text page one.
;; See: <BASL>, <Monitor:BASCALC>
BASH = $29

;; The low byte of a second text line address, the line a scroll copies from.
;;
;; The internal firmware's scroll routines set <BAS2L> and <BAS2H> to the line below the one at <BASL> and copy it up.
;; On the Enhanced IIe, <Monitor:CLREOLZ> and <Monitor:INSDS2> also pass a value to the firmware here: the column to
;; clear from, or the opcode to decode.
;; See: <BASL>, <BAS2H>, <Monitor:SCROLL>, <Monitor:CLREOLZ>
BAS2L = $2A

;; The high byte of the second text line address at <BAS2L>, the line a scroll copies from.
;;
;; The scroll routines set it with <BAS2L>. The original IIe's 40/80-column conversion also counts columns here while it
;; copies the screen.
;; See: <BAS2L>, <BASH>
BAS2H = $2B

;; The rightmost column of a horizontal lo-res line.
;;
;; <Monitor:HLINE> plots from the column in Y to <H2>. The disassembler's <Monitor:PRNTBL> uses it while it unpacks a
;; mnemonic.
;; See: <V2>, <Monitor:HLINE>
H2 = $2C

;; The bottom row of a vertical lo-res line.
;;
;; <Monitor:VLINE> plots from the row in A down to <V2>, and <Monitor:CLRSCR> and <Monitor:CLRTOP> set it to clear the
;; screen. The disassembler's <Monitor:PRNTBL> uses it while it unpacks a mnemonic.
;; See: <H2>, <Monitor:VLINE>, <Monitor:CLRSCR>
V2 = $2D

;; The nibble a lo-res plot changes: $0F for an even row, $F0 for an odd one.
;;
;; <Monitor:PLOT> sets it and <Monitor:PLOT1> uses it, so <Monitor:PLOT1> can plot again on the same row. The
;; disassembler's <Monitor:INSDS2> also leaves an instruction's operand format here for <Monitor:PRADR2>, the cassette
;; <Monitor:READ> keeps its checksum here, and the Enhanced IIe's mini-assembler uses it too.
;; See: <Monitor:PLOT>, <Monitor:PLOT1>, <COLOR>, <Monitor:INSDS2>
MASK = $2E

;; The number of operand bytes of the instruction being disassembled, 0-2.
;;
;; <Monitor:INSDS2> sets it from the opcode, and <Monitor:INSTDSP> and <Monitor:PCADJ> use it to print the bytes and
;; step to the next instruction. The cassette routines keep the last input level here while they read a bit.
;;
;; On the Enhanced IIe, the internal firmware's <Firmware:CXINSDS2> sets it for <Monitor:INSDS2>, and its
;; <Firmware:RDTAPE2BIT> keeps the cassette input level. DOS's relocator, <Dos33:DOSREL>, calls <Dos33:INSDS2> on each
;; instruction and reads the instruction's length here to step to the next.
;; See: <Monitor:INSDS2>, <Monitor:PCADJ>, <PCL>, <MASK>
LENGTH = $2F

;; The lo-res color to plot, the same color in both nibbles.
;;
;; <Monitor:SETCOL> sets it from a color number (0-15) and <Monitor:NXTCOL> steps to the next. <Monitor:PLOT1> merges it
;; into the screen through <MASK>, and <Monitor:CLRSCR> and <Monitor:CLRTOP> set it to 0, black.
;; See: <Monitor:SETCOL>, <Monitor:NXTCOL>, <Monitor:PLOT>, <MASK>
COLOR = $30

;; The Monitor command that is waiting for its second number: ".", ":", "+" or "-", or 0 for none.
;;
;; <Monitor:SETMODE> sets it from the command character, and <Monitor:STOR> keeps it at ":" so each number after a colon
;; is stored. While it is not 0, <Monitor:NXTBAS> does not copy a new number to <A1L> and <A3L>. <Monitor:TOSUB> passes
;; it to each command in A, and <Monitor:ZMODE> clears it.
;; See: <Monitor:SETMODE>, <Monitor:ZMODE>, <Monitor:TOSUB>, <Monitor:NXTITM>
MODE = $31

;; The mask <Monitor:COUT1> ands with each printable character: $FF for normal text, $3F for inverse, $7F for flashing.
;;
;; <Monitor:SETNORM> and <Monitor:SETINV> set it, and <Monitor:RESET> restores normal text. The 80-column firmware tests
;; only its bit 7, showing inverse text when it is clear. The original IIe's <Monitor:GETLN> sets it to $FF while it
;; echoes input.
;; See: <Monitor:SETNORM>, <Monitor:SETINV>, <Monitor:COUT1>
INVFLG = $32

;; The character <Monitor:GETLN> prints before it reads a line.
;;
;; The Monitor sets "*" (<Monitor:MONZ>), and the Enhanced IIe's mini-assembler "!". Applesoft sets "]" and Integer
;; BASIC ">". DOS watches its output for this character to spot an input line (<Dos33:COS0>), and <Dos33:TSTRUN> takes
;; "]" to mean that Applesoft is not running a program.
;;
;; DOS changes it too: its command scanner (<Dos33:SYN1>) stores a value other than "]" for RUN, and <Dos33:ASRUN1> and
;; <Dos33:ASRUN2> store 0, so that <Dos33:TSTRUN> sees a program running.
;; See: <Monitor:GETLN>, <Monitor:MONZ>, <Dos33:TSTRUN>
PROMPT = $33

;; Where the Monitor's command line resumes: the index in <IN> after the last command character.
;;
;; <Monitor:NXTITM> saves Y here after <Monitor:GETNUM>, and <Monitor:SETMODE> and the loop in <Monitor:CHRSRCH> read it
;; back. <Monitor:BL1> counts it down so that Return alone shows the next eight bytes. The Enhanced IIe's mini-assembler
;; uses it too.
;; See: <Monitor:NXTITM>, <Monitor:GETNUM>, <IN>
YSAV = $34

;; Y, saved by <Monitor:COUTZ> while it prints a character.
;;
;; <Monitor:COUTZ> stores Y here first and reloads it at the end, so <Monitor:COUT1> keeps Y. The internal firmware's
;; 80-column output reads it, and the Enhanced IIe's mini-assembler uses it as scratch.
;; See: <Monitor:COUTZ>, <Monitor:COUT1>
YSAV1 = $35

;; The low byte of the output hook: the address of the routine <Monitor:COUT> sends each character to.
;;
;; <Monitor:COUT> jumps through <CSWL>/<CSWH>. <Monitor:SETVID> points it at <Monitor:COUT1>, the screen, and
;; <Monitor:OUTPORT> (PR#) at a slot's $Cn00. DOS keeps the hook pointed at itself (<Dos33:OUTSW>) and passes characters
;; on.
;; See: <Monitor:COUT>, <Monitor:SETVID>, <Monitor:OUTPORT>, <KSWL>, <CSWH>
CSWL = $36

;; The high byte of the output hook at <CSWL>.
;;
;; PR#3 and the 80-column firmware's start-up point the hook at <Firmware:BASICOUT@Enhanced> ($C307). On the Enhanced
;; IIe, quitting the firmware with Control-U points it back at <Monitor:COUT1>.
;; See: <CSWL>, <Monitor:COUT>
CSWH = $37

;; The low byte of the input hook: the address of the routine <Monitor:RDKEY> reads each key from.
;;
;; <Monitor:RDKEY> jumps through <KSWL>/<KSWH>. <Monitor:SETKBD> points it at <Monitor:KEYIN>, the keyboard, and
;; <Monitor:INPORT> (IN#) at a slot's $Cn00. DOS keeps the hook pointed at itself (<Dos33:INSW>) and passes keys on.
;; See: <Monitor:RDKEY>, <Monitor:SETKBD>, <Monitor:INPORT>, <CSWL>, <KSWH>
KSWL = $38

;; The high byte of the input hook at <KSWL>.
;;
;; The 80-column firmware's start-up points the hook at <Firmware:BASICIN@Enhanced> ($C305). On the Enhanced IIe,
;; quitting the firmware with Control-U points it back at <Monitor:KEYIN>.
;; See: <KSWL>, <Monitor:RDKEY>
KSWH = $39

;; The low byte of the Monitor's program counter, the address the disassembler and G work from.
;;
;; <Monitor:BREAK> sets <PCL>/<PCH> from the return address a BRK pushed, and <Monitor:A1PC> copies a typed address to
;; them. <Monitor:INSTDSP> disassembles the instruction there, <Monitor:LIST> steps through, and <Monitor:GO> jumps
;; through them. The Enhanced IIe's mini-assembler works from it too: <Firmware:MINIREL> computes a branch's offset from
;; it.
;; See: <PCH>, <Monitor:INSTDSP>, <Monitor:LIST>, <Monitor:GO>, <Monitor:BREAK>
PCL = $3A

;; The high byte of the Monitor's program counter at <PCL>.
;; See: <PCL>
PCH = $3B

;; The low byte of the Monitor's first address: the start of the range a command works on.
;;
;; <Monitor:NXTBAS> copies each number typed to <A1L>/<A1H> unless <MODE> holds a command, and <Monitor:NXTA1> steps it
;; through the range up to <A2L>. Examine, <Monitor:MOVE>, <Monitor:VFY>, the cassette routines and the firmware's
;; <Firmware:AUXMOVE@Enhanced> all start there.
;; See: <A1H>, <A2L>, <Monitor:NXTA1>, <Monitor:XAM>
A1L = $3C

;; The high byte of the Monitor's first address at <A1L>.
;; See: <A1L>
A1H = $3D

;; The low byte of the Monitor's second address: the number just typed, and the end of a range.
;;
;; <Monitor:GETNUM> builds each number in <A2L>/<A2H>, and <Monitor:NXTBAS> copies it to <A1L> and <A3L>.
;; <Monitor:NXTA1> ends a range there, and <Monitor:OUTPORT> and <Monitor:INPORT> take the slot from it.
;; See: <A2H>, <A1L>, <Monitor:GETNUM>, <Monitor:NXTA1>
A2L = $3E

;; The high byte of the Monitor's second address at <A2L>.
;; See: <A2L>
A2H = $3F

;; The low byte of the Monitor's third address: where the next byte typed after a colon is stored.
;;
;; <Monitor:NXTBAS> sets <A3L>/<A3H> with <A1L>, and <Monitor:STOR> stores each number there and advances it.
;; <Monitor:RGDSP1> borrows it to point at the saved registers.
;; See: <A3H>, <Monitor:STOR>, <Monitor:NXTBAS>
A3L = $40

;; The high byte of the Monitor's third address at <A3L>.
;; See: <A3L>
A3H = $41

;; The low byte of the Monitor's fourth address: the destination of a move or verify.
;;
;; The < command (<Monitor:LT>) copies <A2L>/<A2H> here and to <A5L>. <Monitor:MOVE> and <Monitor:VFY> step it with
;; <Monitor:NXTA4> along with <A1L>, and the firmware's <Firmware:AUXMOVE@Enhanced> uses it the same way. The Enhanced
;; IIe's search, <Monitor:MEMFIND>, takes the bytes to find from <A4L> and <A4H> instead.
;; See: <A4H>, <Monitor:LT>, <Monitor:MOVE>, <Monitor:VFY>, <Monitor:NXTA4>
A4L = $42

;; The high byte of the Monitor's fourth address at <A4L>.
;; See: <A4L>
A4H = $43

;; The low byte of the Monitor's fifth address, a copy of the destination the < command sets.
;;
;; <Monitor:LT> copies <A2L>/<A2H> to <A4L> and here. The Enhanced IIe's interrupt handler leaves the memory state it
;; found here for a BRK, and its mini-assembler collects an operand's address mode in it.
;; See: <A5H>, <Monitor:LT>, <A4L>
A5L = $44

;; The accumulator, saved when the Monitor takes a BRK or IRQ or calls <Monitor:SAVE>.
;;
;; <Monitor:IRQ> and <Monitor:SAVE> store A here and <Monitor:RESTORE> reloads it. It is the first of the five saved
;; registers, ahead of <XREG>, <YREG>, <STATUS> and <SPNT>, which <Monitor:REGDSP> shows in that order.
;; See: <Monitor:SAVE>, <Monitor:RESTORE>, <Monitor:REGDSP>, <XREG>
A5H = $45

;; The X register, saved by <Monitor:SAVE>.
;;
;; <Monitor:SAV1> stores X here and <Monitor:RESTORE> reloads it before <Monitor:GO> runs a program. <Monitor:REGDSP>
;; shows it as X=.
;; See: <A5H>, <YREG>, <Monitor:SAVE>, <Monitor:RESTORE>
XREG = $46

;; The Y register, saved by <Monitor:SAVE>.
;;
;; <Monitor:SAV1> stores Y here and <Monitor:RESTORE> reloads it before <Monitor:GO> runs a program. <Monitor:REGDSP>
;; shows it as Y=.
;; See: <A5H>, <XREG>, <Monitor:SAVE>, <Monitor:RESTORE>
YREG = $47

;; The processor status, P, saved by <Monitor:SAVE>.
;;
;; <Monitor:SAV1> stores P here and <Monitor:RESTORE> pulls it into P before <Monitor:GO> runs a program. <Monitor:INIT>
;; clears it, and <Monitor:REGDSP> shows it as P=.
;; See: <A5H>, <SPNT>, <Monitor:SAVE>, <Monitor:RESTORE>
STATUS = $48

;; The stack pointer, S, saved by <Monitor:SAVE>.
;;
;; <Monitor:SAV1> stores S here for <Monitor:REGDSP> to show as S=. <Monitor:RESTORE> does not reload it.
;; See: <A5H>, <STATUS>, <Monitor:SAVE>
SPNT = $49

;; The low byte of a count that runs while the firmware waits for a key, a seed for random numbers.
;;
;; The keyboard input routines increment <RNDL>/<RNDH> on every pass of their wait loop, so the count depends on how
;; long the user takes to type. Programs read it to seed their random numbers.
;; See: <RNDH>, <Monitor:KEYIN>
RNDL = $4E

;; The high byte of the key-wait count at <RNDL>.
;;
;; The Enhanced IIe's 40-column key wait also blinks the cursor each time bit 6 of it changes.
;; See: <RNDL>
RNDH = $4F

; Pages 2 to 7: the input buffer, the vectors in page 3, text page one and the screen hole for the $C800 ROM.
IN = $0200                          ;; the input line buffer, $0200-$02FF, that the Monitor's GETLN fills
BRKV = $03F0                        ;; BRK handler vector
SOFTEV = $03F2                      ;; reset vector
PWREDUP = $03F4                     ;; reset vector check byte
USRADR = $03F8                      ;; ctrl-Y vector
NMI = $03FB                         ;; NMI vector (a JMP placed by the program)
IRQLOC = $03FE                      ;; IRQ vector
LINE1 = $0400                       ;; text page one
MSLOT = $07F8                       ;; slot whose $C800 ROM is selected

; Soft switches and I/O locations.
;; The keyboard: bit 7 is set when a key has been typed, and bits 0-6 are its code. Writing turns 80STORE off.
;;
;; The key stays here, bit 7 set, until a program clears the strobe by touching <KBDSTRB>. <Monitor:KEYIN> waits on it,
;; and <Monitor:VIDWAIT> looks here for Control-S. A write (CLR80STORE) turns 80STORE off; <SET80STORE> turns it on, and
;; <RD80STORE> reports it.
;; See: <KBDSTRB>, <Monitor:KEYIN>, <RD80STORE>, <SET80STORE>
KBD = $C000

;; Writing it turns 80STORE on: PAGE2 then maps main or auxiliary memory at the text page instead of choosing the
;; displayed page.
;;
;; With 80STORE on, <HISCR> maps auxiliary memory at $0400-$07FF and <LOWSCR> main memory, and while HIRES is on, at
;; $2000-$3FFF too; <RDMAINRAM> and its partners then leave those pages alone. The 80-column firmware turns it on to
;; reach the even columns, which are in auxiliary memory. Writing <KBD> turns it off, and <RD80STORE> reports it.
;; See: <KBD>, <RD80STORE>, <HISCR>, <LOWSCR>
SET80STORE = $C001

;; Writing it turns RAMRD off: reads from $0200-$BFFF come from main memory.
;;
;; <RDCARDRAM> reads auxiliary memory instead, and <RDRAMRD> reports the switch. With 80STORE on, the text page follows
;; PAGE2 instead. <Firmware:AUXMOVE@Enhanced> and the Enhanced IIe's interrupt handler set it.
;; See: <RDCARDRAM>, <RDRAMRD>, <WRMAINRAM>, <Firmware:AUXMOVE@Enhanced>
RDMAINRAM = $C002

;; Writing it turns RAMRD on: reads from $0200-$BFFF come from auxiliary memory.
;;
;; <RDMAINRAM> reads main memory again, and <RDRAMRD> reports the switch. Writes still follow RAMWRT (<WRCARDRAM>).
;; <Firmware:AUXMOVE@Enhanced> and <Firmware:XFER@Enhanced> use it to copy from auxiliary memory.
;; See: <RDMAINRAM>, <RDRAMRD>, <WRCARDRAM>, <Firmware:AUXMOVE@Enhanced>, <Firmware:XFER@Enhanced>
RDCARDRAM = $C003

;; Writing it turns RAMWRT off: writes to $0200-$BFFF go to main memory.
;;
;; <WRCARDRAM> writes auxiliary memory instead, and <RDRAMWRT> reports the switch. With 80STORE on, the text page
;; follows PAGE2 instead. <Firmware:AUXMOVE@Enhanced> and the Enhanced IIe's interrupt handler set it.
;; See: <WRCARDRAM>, <RDRAMWRT>, <RDMAINRAM>, <Firmware:AUXMOVE@Enhanced>
WRMAINRAM = $C004

;; Writing it turns RAMWRT on: writes to $0200-$BFFF go to auxiliary memory.
;;
;; <WRMAINRAM> writes main memory again, and <RDRAMWRT> reports the switch. Reads still follow RAMRD (<RDCARDRAM>).
;; <Firmware:AUXMOVE@Enhanced> and <Firmware:XFER@Enhanced> use it to copy to auxiliary memory.
;; See: <WRMAINRAM>, <RDRAMWRT>, <RDCARDRAM>, <Firmware:AUXMOVE@Enhanced>, <Firmware:XFER@Enhanced>
WRCARDRAM = $C005

;; Writing it maps the peripheral cards' ROMs at $C100-$CFFF, turning SLOTCXROM on.
;;
;; <SETINTCXROM> maps the IIe's internal ROM there instead, and <RDCXROM> reports which is mapped in bit 7. Slot 3's
;; page, $C300, shows the card's ROM only while SLOTC3ROM is on too (<SETSLOTC3ROM>). The Monitor writes it on its way
;; back from the internal firmware, as in <Monitor:SLOTRTS>.
;; See: <SETINTCXROM>, <RDCXROM>, <Monitor:GOTOCX>, <Monitor:SLOTRTS>
SETSLOTCXROM = $C006

;; Writing it maps the IIe's internal ROM at $C100-$CFFF, turning SLOTCXROM off.
;;
;; <Monitor:GOTOCX> writes it before it enters the internal firmware at $C100, and the Enhanced IIe's cassette and
;; mini-assembler entries write it too. <SETSLOTCXROM> maps the peripheral cards' ROMs back, and <RDCXROM> reports which
;; is mapped in bit 7.
;; See: <SETSLOTCXROM>, <RDCXROM>, <Monitor:GOTOCX>
SETINTCXROM = $C007

;; Writing it turns ALTZP off: page zero, the stack and the language card area come from main memory.
;;
;; ALTZP switches $0000-$01FF and $D000-$FFFF together, so a program switching it keeps its own stack pointer for each.
;; <SETALTZP> uses auxiliary memory instead, and <RDALTZP> reports the switch. <Firmware:XFER@Enhanced> and the Enhanced
;; IIe's interrupt handler set it.
;; See: <SETALTZP>, <RDALTZP>, <Firmware:XFER@Enhanced>
SETSTDZP = $C008

;; Writing it turns ALTZP on: page zero, the stack and the language card area come from auxiliary memory.
;;
;; <SETSTDZP> uses main memory again, and <RDALTZP> reports the switch. <Firmware:XFER@Enhanced> sets it when asked to,
;; and the self-tests use it to test auxiliary memory.
;; See: <SETSTDZP>, <RDALTZP>, <Firmware:XFER@Enhanced>
SETALTZP = $C009

;; Writing it maps the IIe's internal ROM at $C300-$C3FF, turning SLOTC3ROM off.
;;
;; The internal page holds the 80-column firmware's entry points (<Firmware:BASICINT@Enhanced>,
;; <Firmware:BASICIN@Enhanced>, <Firmware:BASICOUT@Enhanced>), and running code there also maps the internal $C800 ROM.
;; <SETSLOTC3ROM> maps slot 3's card instead; the reset code chooses between them by what it finds in slot 3.
;; See: <SETSLOTC3ROM>, <SETINTCXROM>, <Firmware:BASICINT@Enhanced>
SETINTC3ROM = $C00A

;; Writing it maps the ROM of the card in slot 3 at $C300-$C3FF, turning SLOTC3ROM on.
;;
;; It takes effect only while <SETSLOTCXROM> maps the slots' ROMs. <SETINTC3ROM> maps the internal firmware there again.
;; See: <SETINTC3ROM>, <SETSLOTCXROM>
SETSLOTC3ROM = $C00B

;; Writing it turns 80COL off: the display shows 40 columns.
;;
;; <SET80VID> turns 80 columns on, and <RD80VID> reports the switch. The firmware writes it when it changes to 40
;; columns.
;; See: <SET80VID>, <RD80VID>
CLR80VID = $C00C

;; Writing it turns 80COL on: the display shows 80 columns, interleaving auxiliary and main memory.
;;
;; Each line's even columns come from auxiliary memory and its odd columns from main memory. The 80-column firmware
;; writes it when it starts and when it changes to 80 columns; <CLR80VID> turns it off, and <RD80VID> reports it.
;; See: <CLR80VID>, <RD80VID>, <SET80STORE>
SET80VID = $C00D

;; Writing it turns ALTCHAR off: text shows the primary character set, with flashing characters.
;;
;; <SETALTCHAR> chooses the alternate set, and <RDALTCHAR> reports the switch. The firmware writes it when the 80-column
;; firmware quits.
;; See: <SETALTCHAR>, <RDALTCHAR>
CLRALTCHAR = $C00E

;; Writing it turns ALTCHAR on: text shows the alternate character set, with inverse lowercase instead of flashing.
;;
;; On the Enhanced IIe, the alternate set also holds the MouseText symbols. The 80-column firmware turns it on when it
;; starts, and <CLRALTCHAR> turns it off; <RDALTCHAR> reports it.
;; See: <CLRALTCHAR>, <RDALTCHAR>
SETALTCHAR = $C00F

;; Reading or writing it clears the keyboard strobe, bit 7 of <KBD>; reading it reports in bit 7 whether a key is down.
;;
;; <Monitor:KEYIN> clears the strobe after it takes a key, so the next read of <KBD> waits for a new one.
;; <Monitor:RESET>, <Monitor:VIDWAIT> and <Monitor:KBDWAIT> clear it too.
;; See: <KBD>, <Monitor:KEYIN>, <Monitor:KBDWAIT>
KBDSTRB = $C010

;; Reading it reports in bit 7 which language card bank is at $D000-$DFFF: 1 for bank 2, 0 for bank 1.
;;
;; The bank-switching reads (<ROMIN>, <LCBANK2>, <LCBANK1> and the rest) choose it. The Enhanced IIe's interrupt handler
;; reads it to restore the bank afterwards.
;; See: <RDLCRAM>, <LCBANK1>, <LCBANK2>
RDLCBNK2 = $C011

;; Reading it reports in bit 7 whether $D000-$FFFF reads come from language card RAM (1) or ROM (0).
;;
;; The bank-switching reads (<ROMIN>, <LCROM>, <LCBANK2>, <LCBANK1>) set it. The Enhanced IIe's interrupt handler reads
;; it, with <RDLCBNK2>, so that it can restore the language card.
;; See: <RDLCBNK2>, <ROMIN>, <LCBANK2>
RDLCRAM = $C012

;; Reading it reports in bit 7 whether RAMRD is on, reads of $0200-$BFFF coming from auxiliary memory.
;;
;; <RDCARDRAM> turns it on and <RDMAINRAM> off. <Firmware:AUXMOVE@Enhanced> and the Enhanced IIe's interrupt handler
;; read it.
;; See: <RDCARDRAM>, <RDMAINRAM>, <RDRAMWRT>
RDRAMRD = $C013

;; Reading it reports in bit 7 whether RAMWRT is on, writes to $0200-$BFFF going to auxiliary memory.
;;
;; <WRCARDRAM> turns it on and <WRMAINRAM> off. <Firmware:AUXMOVE@Enhanced> and the Enhanced IIe's interrupt handler
;; read it.
;; See: <WRCARDRAM>, <WRMAINRAM>, <RDRAMRD>
RDRAMWRT = $C014

;; Reading it reports in bit 7 which ROM is at $C100-$CFFF: 1 for the IIe's internal ROM, 0 for the cards'.
;;
;; <Monitor:GOTOCX> pushes the state, through BIT and PHP, before it switches internal ROM in, and the firmware's return
;; pulls it to decide whether to switch slot ROM back (<Monitor:SLOTRTS>). <SETSLOTCXROM> and <SETINTCXROM> set the
;; switch. On the Enhanced IIe, the interrupt handler, <Firmware:IRQHANDLER>, reads it first, so that it can restore the
;; ROM the interrupted program was using.
;; See: <SETSLOTCXROM>, <SETINTCXROM>, <Monitor:GOTOCX>
RDCXROM = $C015

;; Reading it reports in bit 7 whether ALTZP is on: page zero, the stack and the language card area in auxiliary memory.
;;
;; <SETALTZP> turns it on and <SETSTDZP> off. The Enhanced IIe's interrupt handler reads it to switch to the main stack.
;; See: <SETALTZP>, <SETSTDZP>
RDALTZP = $C016

;; Reading it reports in bit 7 whether SLOTC3ROM is on, slot 3's card ROM mapped at $C300-$C3FF.
;;
;; <SETSLOTC3ROM> turns it on and <SETINTC3ROM> off. The original IIe's self-test reads it to check that the switch
;; works.
;; See: <SETSLOTC3ROM>, <SETINTC3ROM>, <Firmware:SELFTEST@Original>
RDC3ROM = $C017

;; Reading it reports in bit 7 whether 80STORE is on.
;;
;; With 80STORE on, <HISCR> and <LOWSCR> pick auxiliary or main memory for text page one instead of picking the
;; displayed page. Writing <KBD> turns it off and <SET80STORE> on. The original IIe's <Monitor:VIDSYNC> reads it to tell
;; how to restore the page.
;; See: <KBD>, <SET80STORE>, <RDPAGE2>, <HISCR>
RD80STORE = $C018

;; Reading it reports in bit 7 whether the display is drawing the screen: 0 during vertical blanking.
;;
;; The Enhanced IIe's self-test reads it between passes to vary its test patterns a little, since the time of each pass
;; against the display is not fixed.
;; See: <Firmware:SELFTEST@Enhanced>, <Firmware:RAMTEST@Enhanced>
RDVBLBAR = $C019

;; Reading it reports in bit 7 whether TEXT is on, the display showing only text.
;;
;; <TXTSET> turns it on and <TXTCLR> off. When the 80-column firmware sets a full window, it reads it to start the
;; window at line 20, below the graphics, while graphics are shown.
;; See: <TXTSET>, <TXTCLR>
RDTEXT = $C01A

;; Reading it reports in bit 7 whether MIXED is on, four lines of text below the graphics.
;;
;; <MIXSET> turns it on and <MIXCLR> off. The original IIe's self-test reads it to check that the switch works.
;; See: <MIXSET>, <MIXCLR>, <Firmware:SELFTEST@Original>
RDMIXED = $C01B

;; Reading it reports in bit 7 whether PAGE2 is on.
;;
;; <LOWSCR> turns PAGE2 off and <HISCR> on. With 80STORE on, PAGE2 on means text page one is mapped to auxiliary memory
;; rather than page two being displayed. The original IIe's interrupt return code reads it to put the page back.
;; See: <LOWSCR>, <HISCR>, <RD80STORE>
RDPAGE2 = $C01C

;; Reading it reports in bit 7 whether HIRES is on, graphics shown in hi-res.
;;
;; <HIRES> turns it on and <LORES> off. The original IIe's self-test reads it to check that the switch works.
;; See: <HIRES>, <LORES>, <Firmware:SELFTEST@Original>
RDHIRES = $C01D

;; Reading it reports in bit 7 whether ALTCHAR is on, the alternate character set shown.
;;
;; <SETALTCHAR> turns it on and <CLRALTCHAR> off. The firmware reads it to choose the screen codes it stores for inverse
;; and normal characters, which differ between the two sets.
;; See: <SETALTCHAR>, <CLRALTCHAR>
RDALTCHAR = $C01E

;; Reading it reports in bit 7 whether the 80-column display, 80COL, is on.
;;
;; <SET80VID> turns it on and <CLR80VID> off. The Enhanced Monitor's <Monitor:CLREOP> and <Monitor:NXTCHAR> read it, and
;; the internal firmware reads it throughout to choose its 40- or 80-column code.
;; See: <SET80VID>, <CLR80VID>
RD80VID = $C01F

;; Reading it toggles the cassette output.
;;
;; The cassette write routines, <Monitor:HEADR> and <Monitor:WRITE>, toggle it at timed intervals to write tones; each
;; half cycle is one read. On the Enhanced IIe they are in the internal firmware (<Firmware:TAPEHEADR>).
;; See: <TAPEIN>, <Monitor:HEADR>, <Monitor:WRITE>
TAPEOUT = $C020

;; Reading it toggles the speaker, a click.
;;
;; <Monitor:BELL1> toggles it every 0.5 ms or so for about 0.1 seconds to ring the bell. Repeated toggles at a steady
;; rate make a tone.
;; See: <Monitor:BELL1>, <Monitor:BELL>
SPKR = $C030

;; Reading or writing it shows graphics instead of text, turning TEXT off.
;;
;; <MIXSET> keeps four lines of text below the graphics, and <LORES> and <HIRES> choose the kind. <Monitor:SETGR> uses
;; it for lo-res, and <TXTSET> turns text back on.
;; See: <TXTSET>, <MIXSET>, <LORES>, <Monitor:SETGR>, <RDTEXT>
TXTCLR = $C050

;; Reading or writing it shows text instead of graphics, turning TEXT on.
;;
;; <Monitor:SETTXT> and <Monitor:INIT> use it. <TXTCLR> turns graphics back on, and <RDTEXT> reports the switch in bit
;; 7. With 80COL on (<SET80VID>), the text is 80 columns wide.
;; See: <TXTCLR>, <Monitor:SETTXT>, <RDTEXT>, <SET80VID>
TXTSET = $C051

;; Reading or writing it shows the graphics on the whole screen, turning MIXED off.
;;
;; It matters only while graphics are shown (<TXTCLR>). <MIXSET> keeps four lines of text below them, and <RDMIXED>
;; reports the switch. The original IIe's RAM test uses it to show memory as full-screen hi-res graphics.
;; See: <MIXSET>, <RDMIXED>, <Firmware:RAMTEST@Original>
MIXCLR = $C052

;; Reading or writing it shows four lines of text below the graphics, turning MIXED on.
;;
;; It matters only while graphics are shown (<TXTCLR>): the bottom four lines, 20-23, show text. <Monitor:SETGR> uses
;; it, and <MIXCLR> turns it off for full-screen graphics.
;; See: <TXTCLR>, <Monitor:SETGR>, <MIXCLR>
MIXSET = $C053

;; Reading or writing it turns PAGE2 off: page one is displayed, or main memory is used for text page one.
;;
;; With 80STORE off, it shows page one of text or graphics. With 80STORE on, it maps main memory at text page one
;; ($0400-$07FF), and at hi-res page one too while HIRES is on. <Monitor:INIT> uses it, and <RDPAGE2> reports it.
;; See: <HISCR>, <RDPAGE2>, <RD80STORE>
LOWSCR = $C054

;; Reading or writing it turns PAGE2 on: page two is displayed, or auxiliary memory is used for text page one.
;;
;; With 80STORE off, it shows page two of text or graphics. With 80STORE on, it maps auxiliary memory at text page one
;; ($0400-$07FF), and at hi-res page one too while HIRES is on: the 80-column firmware uses it to reach the even
;; columns. <LOWSCR> turns it off, and <RDPAGE2> reports it.
;; See: <LOWSCR>, <RDPAGE2>, <RD80STORE>
HISCR = $C055

;; Reading or writing it chooses lo-res graphics, turning HIRES off.
;;
;; It matters only while graphics are shown (<TXTCLR>). <Monitor:INIT> uses it so that later graphics are lo-res, and
;; <HIRES> chooses hi-res.
;; See: <TXTCLR>, <Monitor:INIT>, <HIRES>
LORES = $C056

;; Reading or writing it chooses hi-res graphics, turning HIRES on.
;;
;; It matters only while graphics are shown (<TXTCLR>). With 80STORE on, it also lets PAGE2 choose main or auxiliary
;; memory at hi-res page one. <LORES> chooses lo-res, and <RDHIRES> reports the switch. The original IIe's RAM test uses
;; it to show memory as it tests it.
;; See: <LORES>, <RDHIRES>, <Firmware:RAMTEST@Original>
HIRES = $C057

;; Reading or writing it turns annunciator 0 off.
;;
;; The annunciators are four outputs on the game I/O connector; each has an off and an on address, the next one up, and
;; none can be read back. <Monitor:RESET> turns annunciators 0 and 1 off.
;; See: <CLRAN1>, <Monitor:RESET>
CLRAN0 = $C058

;; Reading or writing it turns annunciator 1 off.
;;
;; The next address, $C05B, turns it on. <Monitor:RESET> turns it off along with annunciator 0.
;; See: <CLRAN0>, <Monitor:RESET>
CLRAN1 = $C05A

;; Reading or writing it turns annunciator 2 on, despite its name; $C05C turns it off.
;;
;; The reset function reads it, along with <CLRAN3>.
;; See: <CLRAN3>, <CLRAN0>
CLRAN2 = $C05D

;; Reading or writing it turns annunciator 3 on, despite its name; $C05E turns it off.
;;
;; While IOUDIS is on, the same addresses turn double hi-res off ($C05F) and on ($C05E) instead. The reset function
;; reads it, along with <CLRAN2>.
;; See: <CLRAN2>, <CLRAN0>
CLRAN3 = $C05F

;; Reading it reports the cassette input in bit 7.
;;
;; The cassette read routine, <Monitor:READ>, times the changes of bit 7 to tell zeros from ones. On the Enhanced IIe it
;; is in the internal firmware (<Firmware:RDTAPE2BIT>).
;; See: <TAPEOUT>, <Monitor:READ>
TAPEIN = $C060

;; Reading it reports in bit 7 whether button 0, the Open Apple key, is down.
;;
;; At reset, with Open Apple down, the firmware writes over part of every page of RAM, so that a program in memory does
;; not survive. With both Apple keys down at the end of the self-test, the test runs again.
;; See: <BUTN1>, <Firmware:SELFTEST@Enhanced>
BUTN0 = $C061

;; Reading it reports in bit 7 whether button 1, the Solid Apple key, is down.
;;
;; At reset, with Solid Apple down, the firmware runs its self-test (<Firmware:SELFTEST@Enhanced>) instead of starting
;; up.
;; See: <BUTN0>, <Firmware:SELFTEST@Enhanced>
BUTN1 = $C062

;; Reading it reports in bit 7 whether paddle 0's timer is still running; PADDL0 + n does paddle n, 0-3.
;;
;; Touching <PTRIG> starts all four timers, setting bit 7, and each runs for a time that grows with its paddle's
;; position, up to about 3 milliseconds. <Monitor:PREAD> counts until bit 7 clears.
;; See: <PTRIG>, <Monitor:PREAD>
PADDL0 = $C064

;; Reading or writing it starts the four paddle timers.
;;
;; Each paddle's bit 7, at <PADDL0> + n, then stays set for a time that grows with the paddle's position.
;; <Monitor:PREAD> touches it, then counts.
;; See: <PADDL0>, <Monitor:PREAD>
PTRIG = $C070

; Language card switches.
;; Reading it maps language card RAM bank 2 at $D000-$FFFF for reading, with writes off.
;;
;; <LCBANK2> also write-enables the bank when read twice, and <LCRAM1> maps bank 1. The original IIe's
;; <Firmware:COPYROM> reads it to put back a bank 2 RAM it found selected.
;; See: <LCBANK2>, <LCRAM1>, <Firmware:COPYROM>, <RDLCRAM>
LCRAM2 = $C080

;; Reading it maps ROM at $D000-$FFFF; reading it twice in a row also write-enables language card RAM bank 2.
;;
;; A single read, or a write, maps the ROM for reading without enabling writes. <LCROM> maps the ROM with writes off,
;; and <RDLCRAM> reports which is read. The Enhanced IIe's interrupt handler selects it so that the Monitor is in place.
;; See: <LCROM>, <LCBANK2>, <RDLCRAM>
ROMIN = $C081

;; Reading it maps ROM at $D000-$FFFF and write-protects the language card RAM.
;;
;; <ROMIN> maps the ROM while allowing writes to bank 2, and <RDLCRAM> reports which is read. The original IIe's
;; self-test reads it to put the ROM back.
;; See: <ROMIN>, <LCBANK2>, <RDLCRAM>
LCROM = $C082

;; Reading it maps language card RAM bank 2 at $D000-$FFFF; reading it twice in a row also write-enables it.
;;
;; Bank 2 holds $D000-$DFFF and the RAM at $E000-$FFFF is shared by both banks. <LCBANK1> maps bank 1 instead, and
;; <RDLCBNK2> and <RDLCRAM> report the choice.
;; See: <LCBANK1>, <ROMIN>, <RDLCBNK2>, <RDLCRAM>
LCBANK2 = $C083

;; Reading it maps language card RAM bank 1 at $D000-$FFFF for reading, with writes off.
;;
;; <LCBANK1> also write-enables the bank when read twice, and <LCRAM2> maps bank 2. The original IIe's
;; <Firmware:COPYROM> reads it to put back a bank 1 RAM it found selected.
;; See: <LCBANK1>, <LCRAM2>, <Firmware:COPYROM>, <RDLCBNK2>
LCRAM1 = $C088

;; Reading it maps ROM at $D000-$FFFF and selects bank 1; reading it twice in a row also write-enables bank 1.
;;
;; <ROMIN> does the same with bank 2. The original IIe's <Firmware:COPYROM> reads it once to put back ROM with bank 1
;; selected.
;; See: <ROMIN>, <LCRAM1>, <Firmware:COPYROM>
ROMIN1 = $C089

;; Reading it maps language card RAM bank 1 at $D000-$FFFF; reading it twice in a row also write-enables it.
;;
;; Bank 1 holds $D000-$DFFF and the RAM at $E000-$FFFF is shared by both banks. <LCBANK2> maps bank 2 instead, and
;; <RDLCBNK2> and <RDLCRAM> report the choice.
;; See: <LCBANK2>, <RDLCBNK2>, <RDLCRAM>
LCBANK1 = $C08B

; Characters, with bit 7 set as the keyboard and COUT use them.
KEY_CTRL_B = $82                    ;; Control-B: start BASIC, clearing its program
KEY_CTRL_C = $83                    ;; Control-C: continue BASIC; left in the latch when it ends a Control-S pause
KEY_CTRL_E = $85                    ;; Control-E: show the registers
KEY_BELL = $87                      ;; Control-G
KEY_BS = $88                        ;; Control-H, the left arrow
KEY_LF = $8A                        ;; Control-J, the down arrow
KEY_CTRL_K = $8B                    ;; the up arrow; as output, clears to the end of the window
KEY_CR = $8D                        ;; Control-M, Return
KEY_CTRL_P = $90                    ;; Control-P: send output to a slot (PR#)
KEY_CTRL_S = $93                    ;; Control-S; pauses output at the next carriage return until a key is typed
KEY_RIGHT = $95                     ;; Control-U, the right arrow
KEY_CTRL_X = $98                    ;; cancels an input line
KEY_CTRL_Y = $99                    ;; Control-Y: jump to the user's routine (USRADR)
KEY_ESC = $9B                       ;; Escape; on input, starts escape mode (cursor movement)
