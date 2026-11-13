;; P-code for Apple Pascal (UCSD Pascal II.1): a macro for each p-code, which assembles to its bytes.
;;
;; The debug host keeps it in its SDK folder, so a source includes it as .include <Pascal/Pcode.asm>; the sources
;; --pascal disassemble writes do.
;;
;; They are defined under .cpu Pcode, and expand only under it: an assembled procedure in the same file is written
;; under .cpu Mos6502, where p-code's LDA, INC, NOP and STP are the 6502's again.

        .cpu Pcode

;; A standard procedure's number, for CSP.
.scope CSP
IOC = 0
NEW = 1
MVL = 2
MVR = 3
EXIT = 4
UREAD = 5
UWRITE = 6
IDS = 7
TRS = 8
TIM = 9
FLC = 10
SCN = 11
GSEG = 21
RSEG = 22
TNC = 23
RND = 24
SIN = 25
COS = 26
LOG = 27
ATAN = 28
LN = 29
EXP = 30
SQT = 31
MRK = 32
RLS = 33
IOR = 34
UBUSY = 35
POT = 36
UWAIT = 37
UCLEAR = 38
HLT = 39
MEMA = 40
code = 41
.endscope

;; The system segment's procedures, for CXP 0: the I/O, strings and screen that programs call.
.scope PASCALSY
FINIT = 3
FRESET = 4
FOPEN = 5
FCLOSE = 6
FGET = 7
FPUT = 8
FEOF = 10
FEOLN = 11
FREADINT = 12
FWRITEINT = 13
FREADCHAR = 16
FWRITECHAR = 17
FREADSTRING = 18
FWRITESTRING = 19
FWRITEBYTES = 20
FREADLN = 21
FWRITELN = 22
SCONCAT = 23
SINSERT = 24
SCOPY = 25
SDELETE = 26
SPOS = 27
FBLOCKIO = 28
FGOTOXY = 29
.endscope

;; PASCALIO, which the system loads for SEEK and reals' I/O.
.scope PASCALIO
Segment = 31
FSEEK = 2
FREADREAL = 3
FWRITEREAL = 4
.endscope

;; A "big" number: one byte below 128, otherwise two, the first with bit 7 set holding the high bits.
.macro Big value
.if (value) < 128
        .byte value
.else
        .byte ((value) >> 8) | $80, (value) & $FF
.endif
.endmacro

;; Loads a constant from 0 to 127.
.macro SLDC value
.if (value) < 0 || (value) > 127
        .error "SLDC takes 0 to 127."
.endif
        .byte value
.endmacro

;; Absolute value of an integer.
.macro ABI
        .byte 128
.endmacro

;; Absolute value of a real.
.macro ABR
        .byte 129
.endmacro

;; Add integers.
.macro ADI
        .byte 130
.endmacro

;; Add reals.
.macro ADR
        .byte 131
.endmacro

;; Logical and.
.macro LAND
        .byte 132
.endmacro

;; Set difference.
.macro DIF
        .byte 133
.endmacro

;; Divide integers.
.macro DVI
        .byte 134
.endmacro

;; Divide reals.
.macro DVR
        .byte 135
.endmacro

;; Check that an index is in its range.
.macro CHK
        .byte 136
.endmacro

;; Float the integer under the top of the stack.
.macro FLO
        .byte 137
.endmacro

;; Float the integer on top of the stack.
.macro FLT
        .byte 138
.endmacro

;; Test set membership.
.macro INN
        .byte 139
.endmacro

;; Set intersection.
.macro INT
        .byte 140
.endmacro

;; Logical or.
.macro LOR
        .byte 141
.endmacro

;; Integer remainder.
.macro MODI
        .byte 142
.endmacro

;; Multiply integers.
.macro MPI
        .byte 143
.endmacro

;; Multiply reals.
.macro MPR
        .byte 144
.endmacro

;; Negate an integer.
.macro NGI
        .byte 145
.endmacro

;; Negate a real.
.macro NGR
        .byte 146
.endmacro

;; Logical not.
.macro LNOT
        .byte 147
.endmacro

;; Build a subrange set.
.macro SRS
        .byte 148
.endmacro

;; Subtract integers.
.macro SBI
        .byte 149
.endmacro

;; Subtract reals.
.macro SBR
        .byte 150
.endmacro

;; Build a singleton set.
.macro SGS
        .byte 151
.endmacro

;; Square an integer.
.macro SQI
        .byte 152
.endmacro

;; Square a real.
.macro SQR
        .byte 153
.endmacro

;; Store indirect.
.macro STO
        .byte 154
.endmacro

;; Index a string, checking the index.
.macro IXS
        .byte 155
.endmacro

;; Set union.
.macro UNI
        .byte 156
.endmacro

;; Load a word of an intrinsic unit's data.
.macro LDE first, value
        .byte 157, first
        Big value
.endmacro

;; Call a standard procedure.
.macro CSP name
        .byte 158, CSP::name
.endmacro

;; Calls a standard procedure by number.
.macro CSPN number
        .byte 158, number
.endmacro

;; Load the constant nil.
.macro LDCN
        .byte 159
.endmacro

;; Adjust a set to a number of words.
.macro ADJ value
        .byte 160, value
.endmacro

;; Jump if false.
.macro FJP target
        .byte 161, (target) - (* + 1)
.endmacro

;; Jump if false, back through an entry of the procedure's jump table.
.macro FJPT entry
        .byte 161, ((entry) - Attributes) & $FF
.endmacro

;; Increment a field pointer.
.macro INC value
        .byte 162
        Big value
.endmacro

;; Load indirect from an offset.
.macro IND value
        .byte 163
        Big value
.endmacro

;; Index an array.
.macro IXA value
        .byte 164
        Big value
.endmacro

;; Load a global's address.
.macro LAO value
        .byte 165
        Big value
.endmacro

;; Load a string constant's address.
.macro LSA text
        .byte 166, .strlen(text), text
.endmacro

;; Load the address of an intrinsic unit's data.
.macro LAE first, value
        .byte 167, first
        Big value
.endmacro

;; Move words.
.macro MOV value
        .byte 168
        Big value
.endmacro

;; Load a global.
.macro LDO value
        .byte 169
        Big value
.endmacro

;; Assign a string.
.macro SAS value
        .byte 170, value
.endmacro

;; Store a global.
.macro SRO value
        .byte 171
        Big value
.endmacro

;; Case jump.
;; Then a self-relative word for each index from low to high: .word * - arm.
;; The UJP taken outside the range follows it, then the table.
.macro XJP low, high, pad
        .byte 172
        .align 2, pad
        .word (low) & $FFFF, (high) & $FFFF
.endmacro

;; Return from a procedure, leaving a function's result.
.macro RNP value
        .byte 173, value
.endmacro

;; Call an intermediate procedure.
.macro CIP value
        .byte 174, value
.endmacro

;; Compare for equal.
.macro EQU
        .byte 175
.endmacro

;; Compare for equal: real.
.macro EQUREAL
        .byte 175, 2
.endmacro

;; Compare for equal: str.
.macro EQUSTR
        .byte 175, 4
.endmacro

;; Compare for equal: bool.
.macro EQUBOOL
        .byte 175, 6
.endmacro

;; Compare for equal: powr.
.macro EQUPOWR
        .byte 175, 8
.endmacro

;; Compare for equal: arrays of a size.
.macro EQUBYT size
        .byte 175, 10
        Big size
.endmacro

;; Compare for equal: arrays of a size.
.macro EQUWORD size
        .byte 175, 12
        Big size
.endmacro

;; Compare for greater or equal.
.macro GEQ
        .byte 176
.endmacro

;; Compare for greater or equal: real.
.macro GEQREAL
        .byte 176, 2
.endmacro

;; Compare for greater or equal: str.
.macro GEQSTR
        .byte 176, 4
.endmacro

;; Compare for greater or equal: bool.
.macro GEQBOOL
        .byte 176, 6
.endmacro

;; Compare for greater or equal: powr.
.macro GEQPOWR
        .byte 176, 8
.endmacro

;; Compare for greater or equal: arrays of a size.
.macro GEQBYT size
        .byte 176, 10
        Big size
.endmacro

;; Compare for greater or equal: arrays of a size.
.macro GEQWORD size
        .byte 176, 12
        Big size
.endmacro

;; Compare for greater.
.macro GRT
        .byte 177
.endmacro

;; Compare for greater: real.
.macro GRTREAL
        .byte 177, 2
.endmacro

;; Compare for greater: str.
.macro GRTSTR
        .byte 177, 4
.endmacro

;; Compare for greater: bool.
.macro GRTBOOL
        .byte 177, 6
.endmacro

;; Compare for greater: powr.
.macro GRTPOWR
        .byte 177, 8
.endmacro

;; Compare for greater: arrays of a size.
.macro GRTBYT size
        .byte 177, 10
        Big size
.endmacro

;; Compare for greater: arrays of a size.
.macro GRTWORD size
        .byte 177, 12
        Big size
.endmacro

;; Load an intermediate variable's address.
.macro LDA first, value
        .byte 178, first
        Big value
.endmacro

;; Load a multiple-word constant.
;; Its words follow from the next word boundary; pad is the byte skipped to reach it.
.macro LDC count, pad
        .byte 179, count
        .align 2, pad
.endmacro

;; Compare for less or equal.
.macro LEQ
        .byte 180
.endmacro

;; Compare for less or equal: real.
.macro LEQREAL
        .byte 180, 2
.endmacro

;; Compare for less or equal: str.
.macro LEQSTR
        .byte 180, 4
.endmacro

;; Compare for less or equal: bool.
.macro LEQBOOL
        .byte 180, 6
.endmacro

;; Compare for less or equal: powr.
.macro LEQPOWR
        .byte 180, 8
.endmacro

;; Compare for less or equal: arrays of a size.
.macro LEQBYT size
        .byte 180, 10
        Big size
.endmacro

;; Compare for less or equal: arrays of a size.
.macro LEQWORD size
        .byte 180, 12
        Big size
.endmacro

;; Compare for less.
.macro LES
        .byte 181
.endmacro

;; Compare for less: real.
.macro LESREAL
        .byte 181, 2
.endmacro

;; Compare for less: str.
.macro LESSTR
        .byte 181, 4
.endmacro

;; Compare for less: bool.
.macro LESBOOL
        .byte 181, 6
.endmacro

;; Compare for less: powr.
.macro LESPOWR
        .byte 181, 8
.endmacro

;; Compare for less: arrays of a size.
.macro LESBYT size
        .byte 181, 10
        Big size
.endmacro

;; Compare for less: arrays of a size.
.macro LESWORD size
        .byte 181, 12
        Big size
.endmacro

;; Load an intermediate variable.
.macro LOD first, value
        .byte 182, first
        Big value
.endmacro

;; Compare for not equal.
.macro NEQ
        .byte 183
.endmacro

;; Compare for not equal: real.
.macro NEQREAL
        .byte 183, 2
.endmacro

;; Compare for not equal: str.
.macro NEQSTR
        .byte 183, 4
.endmacro

;; Compare for not equal: bool.
.macro NEQBOOL
        .byte 183, 6
.endmacro

;; Compare for not equal: powr.
.macro NEQPOWR
        .byte 183, 8
.endmacro

;; Compare for not equal: arrays of a size.
.macro NEQBYT size
        .byte 183, 10
        Big size
.endmacro

;; Compare for not equal: arrays of a size.
.macro NEQWORD size
        .byte 183, 12
        Big size
.endmacro

;; Store an intermediate variable.
.macro STR first, value
        .byte 184, first
        Big value
.endmacro

;; Jump.
.macro UJP target
        .byte 185, (target) - (* + 1)
.endmacro

;; Jump, back through an entry of the procedure's jump table.
.macro UJPT entry
        .byte 185, ((entry) - Attributes) & $FF
.endmacro

;; Load a packed field.
.macro LDP
        .byte 186
.endmacro

;; Store a packed field.
.macro STP
        .byte 187
.endmacro

;; Load words.
.macro LDM value
        .byte 188, value
.endmacro

;; Store words.
.macro STM value
        .byte 189, value
.endmacro

;; Load a byte.
.macro LDB
        .byte 190
.endmacro

;; Store a byte.
.macro STB
        .byte 191
.endmacro

;; Index a packed array.
.macro IXP first, second
        .byte 192, first, second
.endmacro

;; Return from a base procedure.
.macro RBP value
        .byte 193, value
.endmacro

;; Call a base procedure.
.macro CBP value
        .byte 194, value
.endmacro

;; Compare integers for equal.
.macro EQUI
        .byte 195
.endmacro

;; Compare integers for greater or equal.
.macro GEQI
        .byte 196
.endmacro

;; Compare integers for greater.
.macro GRTI
        .byte 197
.endmacro

;; Load a local's address.
.macro LLA value
        .byte 198
        Big value
.endmacro

;; Load a word constant.
.macro LDCI value
        .byte 199
        .word (value) & $FFFF
.endmacro

;; Compare integers for less or equal.
.macro LEQI
        .byte 200
.endmacro

;; Compare integers for less.
.macro LESI
        .byte 201
.endmacro

;; Load a local.
.macro LDL value
        .byte 202
        Big value
.endmacro

;; Compare integers for not equal.
.macro NEQI
        .byte 203
.endmacro

;; Store a local.
.macro STL value
        .byte 204
        Big value
.endmacro

;; Call a procedure in another segment.
.macro CXP first, second
        .byte 205, first, second
.endmacro

;; Call a local procedure.
.macro CLP value
        .byte 206, value
.endmacro

;; Call a global procedure.
.macro CGP value
        .byte 207, value
.endmacro

;; Load a packed array constant's address.
.macro LPA text
        .byte 208, .strlen(text), text
.endmacro

;; Store a word of an intrinsic unit's data.
.macro STE first, value
        .byte 209, first
        Big value
.endmacro

;; No operation (unused).
.macro NOP210
        .byte 210
.endmacro

;; Jump if not equal.
.macro EFJ target
        .byte 211, (target) - (* + 1)
.endmacro

;; Jump if not equal, back through an entry of the procedure's jump table.
.macro EFJT entry
        .byte 211, ((entry) - Attributes) & $FF
.endmacro

;; Jump if equal.
.macro NFJ target
        .byte 212, (target) - (* + 1)
.endmacro

;; Jump if equal, back through an entry of the procedure's jump table.
.macro NFJT entry
        .byte 212, ((entry) - Attributes) & $FF
.endmacro

;; Breakpoint.
.macro BPT value
        .byte 213
        Big value
.endmacro

;; Exit the system.
.macro XIT
        .byte 214
.endmacro

;; No operation.
.macro NOP
        .byte 215
.endmacro

;; Load local 1.
.macro SLDL1
        .byte 216
.endmacro

;; Load local 2.
.macro SLDL2
        .byte 217
.endmacro

;; Load local 3.
.macro SLDL3
        .byte 218
.endmacro

;; Load local 4.
.macro SLDL4
        .byte 219
.endmacro

;; Load local 5.
.macro SLDL5
        .byte 220
.endmacro

;; Load local 6.
.macro SLDL6
        .byte 221
.endmacro

;; Load local 7.
.macro SLDL7
        .byte 222
.endmacro

;; Load local 8.
.macro SLDL8
        .byte 223
.endmacro

;; Load local 9.
.macro SLDL9
        .byte 224
.endmacro

;; Load local 10.
.macro SLDL10
        .byte 225
.endmacro

;; Load local 11.
.macro SLDL11
        .byte 226
.endmacro

;; Load local 12.
.macro SLDL12
        .byte 227
.endmacro

;; Load local 13.
.macro SLDL13
        .byte 228
.endmacro

;; Load local 14.
.macro SLDL14
        .byte 229
.endmacro

;; Load local 15.
.macro SLDL15
        .byte 230
.endmacro

;; Load local 16.
.macro SLDL16
        .byte 231
.endmacro

;; Load global 1.
.macro SLDO1
        .byte 232
.endmacro

;; Load global 2.
.macro SLDO2
        .byte 233
.endmacro

;; Load global 3.
.macro SLDO3
        .byte 234
.endmacro

;; Load global 4.
.macro SLDO4
        .byte 235
.endmacro

;; Load global 5.
.macro SLDO5
        .byte 236
.endmacro

;; Load global 6.
.macro SLDO6
        .byte 237
.endmacro

;; Load global 7.
.macro SLDO7
        .byte 238
.endmacro

;; Load global 8.
.macro SLDO8
        .byte 239
.endmacro

;; Load global 9.
.macro SLDO9
        .byte 240
.endmacro

;; Load global 10.
.macro SLDO10
        .byte 241
.endmacro

;; Load global 11.
.macro SLDO11
        .byte 242
.endmacro

;; Load global 12.
.macro SLDO12
        .byte 243
.endmacro

;; Load global 13.
.macro SLDO13
        .byte 244
.endmacro

;; Load global 14.
.macro SLDO14
        .byte 245
.endmacro

;; Load global 15.
.macro SLDO15
        .byte 246
.endmacro

;; Load global 16.
.macro SLDO16
        .byte 247
.endmacro

;; Load indirect from offset 0.
.macro SIND0
        .byte 248
.endmacro

;; Load indirect from offset 1.
.macro SIND1
        .byte 249
.endmacro

;; Load indirect from offset 2.
.macro SIND2
        .byte 250
.endmacro

;; Load indirect from offset 3.
.macro SIND3
        .byte 251
.endmacro

;; Load indirect from offset 4.
.macro SIND4
        .byte 252
.endmacro

;; Load indirect from offset 5.
.macro SIND5
        .byte 253
.endmacro

;; Load indirect from offset 6.
.macro SIND6
        .byte 254
.endmacro

;; Load indirect from offset 7.
.macro SIND7
        .byte 255
.endmacro

