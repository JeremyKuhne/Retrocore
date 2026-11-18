;; The NFS's paged ROM header, service calls and file server conversation ($8000-$8840).
;;
;; - The paged ROM header, whose title and copyright string also hold the names of *NET and *ROFF, and the table of
;;   routines <NFS_DISPATCH> enters by number: the service calls, the OS procedure calls that arrive through the
;;   language entry, the filing system control calls, the file server's command replies and OSBYTE &32-&35.
;; - <NFS_SERVICE>, which offers each service call to the DFS before or after the NFS as the start-up options say,
;;   starts the Tube (copying the Tube host code to RAM), claims the NFS's workspace, and starts the NFS at BREAK
;;   or for *NET: the "Econet Station n" message, the vectors, and the boot, which logs on as BOOT.
;; - The conversation with the file server: the control blocks, sending a request on port &99 and waiting for the
;;   reply on port &90 (<FS_COMMAND>), and raising the error a reply carries. Transmitting (<TRANSMIT>), waiting
;;   for a reception (<AWAIT_RECEPTION>) and the NFS's own errors (<NFS_ERRORS>).
;; - The filing system calls that are here: OSBGET and OSBPUT, OSFILE's load and save, and the helpers the NFS's
;;   other calls share: the handle and access conversions, the file name, and printing inline text.
;; - *I AM, *BYE and *ROFF, and the OS procedure calls that a controlling station's *REMOTE makes.

; ---------------------------------------------------------------------------------------------------------------------
; Constants
; ---------------------------------------------------------------------------------------------------------------------

; The paged ROM service calls this part handles or issues (in A, or X for OSBYTE &8F).

ABSOLUTE_WORKSPACE_SERVICE = $01    ;; service 1: claim absolute workspace; Y = the top page claimed so far
STATIC_WORKSPACE_SERVICE = $0A      ;; service &0A: claim the static workspace from &0E00
VECTORS_CLAIMED_SERVICE = $0F       ;; service &0F: a filing system has claimed the vectors
INITIALISE_FS_SERVICE = $12         ;; service &12: initialise the filing system whose number is in Y
TUBE_POST_INIT_SERVICE = $FE        ;; service &FE: Tube system post initialisation; Y = nonzero with a Tube
TUBE_MAIN_INIT_SERVICE = $FF        ;; service &FF: Tube system main initialisation

NFS_FILING_SYSTEM = 5               ;; the NFS's filing system number, which service &12 gives in Y
NFS_FSC_NEW_FS = 6                  ;; FSCV 6: a new filing system is about to take over

; How <NFS_DISPATCH> numbers its routines: each kind of call takes a run of <NFS_DISPATCH_LOW>'s entries, and the
; caller passes the entry for call 0 less one in Y.

NFS_SERVICE_ENTRIES = 1             ;; the entry for service 0; services 0-&0C take entries 1-13
NFS_SERVICE_COUNT = $0D             ;; the services in the table; service &12 for the NFS takes the next entry, 14
NFS_PROCEDURE_ENTRIES = 15          ;; the entry for OS procedure 0; procedures 0-4 take entries 15-19
NFS_PROCEDURE_COUNT = 5             ;; the OS procedures
NFS_FSC_ENTRIES = 20                ;; the entry for FSCV 0; FSCV 0-7 take entries 20-27
NFS_FSC_COUNT = 8                   ;; the filing system control calls the NFS handles
NFS_REPLY_ENTRIES = 24              ;; where command code 0 would be; codes 1-9 of a reply take entries 25-33
NFS_OSBYTE_ENTRIES = 34             ;; the entry for OSBYTE &32; OSBYTE &32-&35 take entries 34-37
NFS_FIRST_OSBYTE = $32              ;; the first of the NFS's OSBYTE calls, &32-&35
NFS_OSBYTE_COUNT = 4                ;; the NFS's OSBYTE calls

; The OSBYTE calls this part makes.

NFS_OSBYTE_EXPLODE_FONT = $14       ;; OSBYTE &14: explode the soft character definitions; X = 6 for all of them
NFS_OSBYTE_CLOSE_SPOOL_EXEC = $77   ;; OSBYTE &77: close the *SPOOL and *EXEC files
NFS_OSBYTE_WRITE_KEYS_PRESSED = $78 ;; OSBYTE &78: write the keys-pressed information from X and Y
NFS_OSBYTE_SCAN_KEYBOARD = $7A      ;; OSBYTE &7A: scan the keyboard from key 16; X = the key pressed, or &FF
NFS_OSBYTE_ACKNOWLEDGE_ESCAPE = $7E ;; OSBYTE &7E: acknowledge an ESCAPE condition
NFS_OSBYTE_SERVICE = $8F            ;; OSBYTE &8F: issue the paged ROM service call in X, with Y
NFS_OSBYTE_INSERT_INPUT = $99       ;; OSBYTE &99: insert Y into the input buffer X, checking for ESCAPE
NFS_OSBYTE_EXTENDED_VECTORS = $A8   ;; OSBYTE &A8: read the address of the extended vectors
NFS_OSBYTE_EXEC_HANDLE = $C6        ;; OSBYTE &C6: read or write the *EXEC handle; Y comes back as the *SPOOL handle
NFS_OSBYTE_KEYBOARD_DISABLE = $C9   ;; OSBYTE &C9: read or write the Econet keyboard disable flag
NFS_OSBYTE_OS_INTERCEPT = $CE       ;; OSBYTE &CE: read or write the Econet OS call interception status
NFS_OSBYTE_WRCH_INTERCEPT = $D0     ;; OSBYTE &D0: read or write the Econet OSWRCH interception status
NFS_OSBYTE_LAST_BREAK = $FD         ;; OSBYTE &FD: read the type of the last reset; X = 0 after a soft BREAK

NFS_KEY_N = $55                     ;; the internal key number of N, which selects the NFS at BREAK
NFS_INTERCEPT = %10000000           ;; the bit OSBYTE &CE-&D0 set to make the MOS pass calls to NETV

; The file server's ports, and the functions a request asks for (in its second byte).

NFS_FS_COMMAND_LINE = 0             ;; function 0: interpret a command line
NFS_FS_SAVE = 1                     ;; function 1: save a file
NFS_FS_LOAD = 2                     ;; function 2: load a file
NFS_FS_GET_BYTE = 8                 ;; function 8: read a byte from an open file
NFS_FS_PUT_BYTE = 9                 ;; function 9: write a byte to an open file
NFS_FS_BYE = $17                    ;; function &17: log off

; Error numbers.

NFS_ERROR_LINE_JAMMED = $A0         ;; error &A0, "Line Jammed"
NFS_ERROR_NET_ERROR = $A1           ;; error &A1, "Net Error"
NFS_ERROR_NOT_LISTENING = $A2       ;; error &A2, "Not listening"
NFS_ERROR_NO_CLOCK = $A3            ;; error &A3, "No Clock"
NFS_ERROR_ESCAPE = $11              ;; error &11, "Escape"
NFS_ERROR_BAD_OPTION = $CB          ;; error &CB, "Bad Option"
NFS_ERROR_NO_REPLY = $A5            ;; error &A5, "No reply"
NFS_ERROR_FIRST_FS = $A8            ;; the lowest error number a file server error is given
NFS_ERROR_NOT_FOUND = $D6           ;; error &D6, "Not found", which <FS_COMMAND_IF_FOUND> can return instead

; The indexes of <NFS_ERROR_OFFSETS>.

NFS_ERROR_INDEX_ESCAPE = 6          ;; the index <NFS_CHECK_ESCAPE> raises "Escape" with (4 and 5 give it too)
NFS_ERROR_INDEX_NO_REPLY = 8        ;; the index of "No reply"

; The 68B54's status bits the NFS reads.

NFS_ADLC_SR1_ODD = %11101101        ;; status register 1's bits other than 1 and 4: any set means no ADLC is fitted
NFS_ADLC_SR2_ODD = %11011011        ;; status register 2's bits other than 2 and 5: any set means no ADLC is fitted
NFS_ADLC_NO_CLOCK = %00100000       ;; status register 2's bit 5, set when the network has no clock

; Starting the Tube host code, which the ROM holds after the NFS's calls (Tube.asm) and service &FF copies to RAM.

NFS_TUBE_ZERO_PAGE_COPY = $60       ;; the last offset <START_TUBE> copies to zero page: &61 bytes, to &0076
NFS_TUBE_INTERRUPTS = %10001110     ;; written to the Tube's register 1 status: sets the Tube ULA's flags 1-3

; ---------------------------------------------------------------------------------------------------------------------
; The NFS's workspace, as this part uses it
; ---------------------------------------------------------------------------------------------------------------------


; Offsets in the first private page, at (NFS_WORKSPACE_PAGE),Y.

NFS_REMOTE_STATE = $04              ;; nonzero while another station controls this one through *REMOTE
NFS_SAVED_STATE = $15               ;; &15-&1D, a copy of <NFS_FS_STATION> kept while another filing system is current
NFS_SAVED_STATE_END = $1D           ;; the last byte of NFS_SAVED_STATE
NFS_CALLER_STATION = $80            ;; the station and network that sent the last OS procedure call
NFS_CALLER_DATA = $82               ;; the first byte of data that came with it

; Offsets in the second private page, at (NFS_BLOCKS_PAGE),Y: eighteen receive control blocks of twelve bytes.

NFS_CONTROLLER = $0E                ;; receive block 1's station and network: the station controlling this one

; The service calls, in the MOS's command workspace.

NFS_SERVICE_Y = OS_COMMAND_WORKSPACE ;; the service call's Y while the NFS carries it out; bit 7 set stops a boot
NFS_BLOCK_NUMBER = OS_COMMAND_WORKSPACE ;; the receive control block service 2 is marking free

; The command line and calls, in the filing systems' scratch space.

NFS_INLINE_POINTER = FS_SCRATCH     ;; the pointer <NFS_PRINT_INLINE> walks through its text, then jumps through
NFS_NUMBER = FS_SCRATCH + 2         ;; the number <NFS_READ_DECIMAL> is reading
NFS_DIGIT = FS_SCRATCH + 3          ;; the digit <NFS_READ_DECIMAL> is adding
NFS_BIT_SOURCE = FS_SCRATCH + 8     ;; the bits <CONVERT_ACCESS> has still to convert
NFS_BYTE_HANDLE = FS_SCRATCH + 10   ;; the handle OSBGET or OSBPUT was called with

; The control block for the file server, in the filing system's workspace, as <FS_CONTROL_BLOCK_TEMPLATE> lays it out.

NFS_BYTE_MASK = FS_WORKSPACE + 15   ;; the file server's handle for OSBGET and OSBPUT

; The NFS's variables in pages &0D-&0F (the DFS uses the same addresses for its own while it is current).

NFS_FS_NETWORK = $0E01              ;; the file server's network
NFS_FILE_NAME = $0E30               ;; the file name <NFS_READ_FILE_NAME> reads, ending in a carriage return
NFS_SAVE_LOAD = NFS_REQUEST_DATA    ;; a save request's load address, then its execution address
NFS_SAVE_LENGTH = $0F0D             ;; a save request's length, three bytes
NFS_SAVE_NAME = $0F10               ;; a save request's file name
NFS_LOAD_LENGTH = $0F0D             ;; a load reply's length, three bytes, after the load and execution addresses
NFS_LOAD_ACCESS = $0F10             ;; a load reply's access byte, then the date in two bytes
NFS_BYTE_REQUEST = $0FDC            ;; an OSBGET or OSBPUT request, and its reply: the port, or the command code,
NFS_BYTE_FUNCTION = $0FDD           ;; the function, or the return code,
NFS_BYTE_DATA = $0FDE               ;; the handle, or the byte read,
NFS_BYTE_FLAGS = $0FDF              ;; the byte written, or the flags: bit 7 at the end, bit 6 past it
NFS_BYTE_ERROR = $0FE0              ;; where <NFS_BYTE_TRANSFER> moves a reply that holds an error

; The offsets of an OSFILE control block.

NFS_OSFILE_BLOCK_LOAD = $02               ;; the load address, four bytes
NFS_OSFILE_EXEC = $06               ;; the execution address, four bytes
NFS_OSFILE_START = $0A              ;; the start address for a save, or the length
NFS_OSFILE_END = $0E                ;; the end address for a save, or the attributes

; ---------------------------------------------------------------------------------------------------------------------
; Macros
; ---------------------------------------------------------------------------------------------------------------------

;; Gives the extended vector entry in the MOS (&FF00 + 3n) for the vector at a page two address.
;; Parameters:
;;   vector = the vector, such as FILEV
.define NFS_EXTENDED_ENTRY(vector) (EXTENDED_VECTOR_ENTRIES + ((vector) - USERV) / 2 * 3)

;; Gives the offset of a vector's extended vector, three bytes for each vector from USERV.
;; Parameters:
;;   vector = the vector, such as FILEV
.define NFS_EXTENDED_OFFSET(vector) (((vector) - USERV) / 2 * 3)

;; Lays out one of <NFS_VECTOR_HANDLERS>: a routine's address and a byte <NFS_SET_EXTENDED_VECTORS> overwrites.
;; Parameters:
;;   routine = the routine
;;   filler = the third byte, which the copy replaces with the ROM's number
.macro NFS_VECTOR_HANDLER routine, filler
    .word routine
    .byte filler
.endmacro

;; Emits an entry of <NFS_DISPATCH_LOW>: the low byte of a routine's address less one.
;; Parameters:
;;   routine = the routine
.macro NFS_DISPATCH_LOW_BYTE routine
    .byte <(routine-1)
.endmacro

;; Emits an entry of <NFS_DISPATCH_HIGH>: the high byte of a routine's address less one.
;; Parameters:
;;   routine = the routine
.macro NFS_DISPATCH_HIGH_BYTE routine
    .byte >(routine-1)
.endmacro

;; Lists the routines <NFS_DISPATCH> enters, in order, as the entries 1-37 of <NFS_DISPATCH_LOW> and
;; <NFS_DISPATCH_HIGH>.
;; Parameters:
;;   emit = the macro that emits one byte of an entry: <NFS_DISPATCH_LOW_BYTE> or <NFS_DISPATCH_HIGH_BYTE>
.macro NFS_DISPATCH_ENTRIES emit
    emit NFS_NO_OPERATION                         ; 1: service 0, no operation
    emit NFS_SERVICE_ABSOLUTE_WORKSPACE     ; 2: service 1, absolute workspace claim
    emit NFS_SERVICE_PRIVATE_WORKSPACE      ; 3: service 2, private workspace claim
    emit NFS_SERVICE_AUTO_BOOT              ; 4: service 3, auto-boot
    emit NFS_SERVICE_UNRECOGNISED_COMMAND   ; 5: service 4, unrecognised command (*ROFF and *NET)
    emit SERVICE_UNRECOGNISED_INTERRUPT                              ; 6: service 5, unrecognised interrupt
    emit NFS_NO_OPERATION                         ; 7: service 6, BRK
    emit NFS_SERVICE_UNRECOGNISED_OSBYTE    ; 8: service 7, unrecognised OSBYTE (&32-&35)
    emit SERVICE_UNRECOGNISED_OSWORD                              ; 9: service 8, unrecognised OSWORD
    emit NFS_SERVICE_HELP                   ; 10: service 9, *HELP
    emit NFS_NO_OPERATION                         ; 11: service &0A, claim static workspace
    emit NFS_SERVICE_NMI_RELEASE                              ; 12: service &0B, NMI release
    emit NFS_SERVICE_NMI_CLAIM                              ; 13: service &0C, NMI claim
    emit NFS_COMMAND                        ; 14: service &12 with Y = 5, initialise the NFS
    emit PROCEDURE_INSERT_KEY               ; 15: OS procedure 0, put a character into the keyboard buffer
    emit PROCEDURE_START_REMOTE             ; 16: OS procedure 1, come under another station's *REMOTE control
    emit READ_SCREEN_STATE                              ; 17: OS procedure 2
    emit PROCEDURE_ABANDON                  ; 18: OS procedure 3, raise error 0 to stop the current program
    emit PROCEDURE_REMOTE_KEY               ; 19: OS procedure 4, a key from the controlling station
    emit NFS_OPT                              ; 20: FSCV 0, *OPT
    emit NFS_EOF                              ; 21: FSCV 1, end of file
    emit NFS_RUN                              ; 22: FSCV 2, */
    emit NFS_UNRECOGNISED_COMMAND                              ; 23: FSCV 3, unrecognised * command
    emit NFS_RUN                              ; 24: FSCV 4, *RUN
    emit NFS_CAT                              ; 25: FSCV 5, *CAT; and command code 1 of a reply
    emit NFS_FSC_NEW_FILING_SYSTEM          ; 26: FSCV 6, a new filing system takes over; and command code 2
    emit NFS_FSC_HANDLES                    ; 27: FSCV 7, the range of file handles; and command code 3
    emit PRINT_REPLY_LIST                              ; 28: command code 4: print the reply's text
    emit NFS_LOG_ON                              ; 29: command code 5: take the handles and boot option, and boot
    emit NFS_SET_HANDLES                              ; 30: command code 6: take the handles
    emit NFS_SET_DIRECTORY                              ; 31: command code 7: take the current directory's handle
    emit NFS_RUN_COMMAND                              ; 32: command code 8: run the file the command names
    emit NFS_SET_LIBRARY                              ; 33: command code 9: take the library's handle
    emit NFS_OSBYTE_POLL_TRANSMIT ; 34: OSBYTE &32, read the transmit control block's status
    emit NFS_OSBYTE_POLL_RECEIVE                              ; 35: OSBYTE &33, read a receive control block's status
    emit NFS_OSBYTE_DELETE_RECEIVE                              ; 36: OSBYTE &34, free a receive control block
    emit ROFF_COMMAND                       ; 37: OSBYTE &35, end *REMOTE control
.endmacro

; ---------------------------------------------------------------------------------------------------------------------
; The paged ROM header
; ---------------------------------------------------------------------------------------------------------------------

;; The language entry, which the NFS uses for its OS procedure calls.
;;
;; The ROM type has no language bit, so the MOS never enters the ROM here; the Econet code calls it with JSR when
;; another station sends immediate operation &85, an OS procedure call.
;; See: <NFS_PROCEDURE_CALL>
NFS_LANGUAGE_ENTRY:
    jmp NFS_PROCEDURE_CALL
    .assert NFS_LANGUAGE_ENTRY = LANGUAGE_ENTRY, "The NFS's language entry is the paged ROM's."

;; The service entry, which the MOS calls with each paged ROM service call.
;; See: <NFS_SERVICE>
NFS_SERVICE_ENTRY:
    jmp NFS_SERVICE
    .assert NFS_SERVICE_ENTRY = SERVICE_ENTRY, "The NFS's service entry is the paged ROM's."

;; The ROM type: a service entry (bit 7) and 6502 code (type 2), with no language and no relocation address.
NFS_ROM_TYPE:
    .byte %10000010
    .assert NFS_ROM_TYPE = ROM_TYPE, "The ROM type is at &8006."

;; The offset of the copyright string, the zero that ends the title.
NFS_COPYRIGHT_OFFSET:
    .byte NFS_COPYRIGHT - NFS_LANGUAGE_ENTRY
    .assert NFS_COPYRIGHT_OFFSET = COPYRIGHT_OFFSET, "The copyright offset is at &8007."

;; The binary version number, &83; also the base <NFS_MATCH_COMMAND_NAME> finds the names of *NET and *ROFF from.
NFS_ROM_VERSION:
    .byte $83

;; The title, "DFS,NET", whose last three letters are the name of *NET.
NFS_ROM_TITLE:
    .byte "DFS,"
    .assert NFS_ROM_TITLE = ROM_TITLE, "The title is at &8009."

;; The name *NET is matched against, ending at the zero that ends the title.
NFS_NET_NAME:
    .byte "NET"

;; The copyright string, a zero then "(C)", which goes on as the name of *ROFF.
NFS_COPYRIGHT:
    .byte 0, "(C)"

;; The name *ROFF is matched against, ending at the first of <NFS_ERROR_OFFSETS>, a zero, which also ends the
;; copyright string.
NFS_ROFF_NAME:
    .byte "ROFF"

;; The offset in <NFS_ERRORS> of each error the NFS raises itself, by index.
;;
;; Indexes 0-7 are the low three bits of a failed control block's status, as <NFS_TRANSMIT_ERROR> takes them; 8 is
;; "No reply". The first entry, zero, also ends the copyright string and the name of *ROFF.
;; See: <NFS_ERROR_ANY>
NFS_ERROR_OFFSETS:
    .byte LINE_JAMMED_MESSAGE - NFS_ERRORS      ; 0: Line Jammed
    .byte NFS_ERROR_MESSAGE - NFS_ERRORS        ; 1: Net Error
    .byte NOT_LISTENING_MESSAGE - NFS_ERRORS    ; 2: Not listening
    .byte NO_CLOCK_MESSAGE - NFS_ERRORS         ; 3: No Clock
    .byte ESCAPE_MESSAGE - NFS_ERRORS           ; 4: Escape
    .byte ESCAPE_MESSAGE - NFS_ERRORS           ; 5: Escape
    .byte ESCAPE_MESSAGE - NFS_ERRORS           ; 6: Escape, which <NFS_CHECK_ESCAPE> raises
    .byte BAD_OPTION_MESSAGE - NFS_ERRORS       ; 7: Bad Option
    .byte NO_REPLY_MESSAGE - NFS_ERRORS         ; 8: No reply
    .assert LINE_JAMMED_MESSAGE = NFS_ERRORS, "Error offset 0 is the zero that ends the copyright string."

;; Four bytes nothing in the ROM reads: 1, 0, &60 and 3.
;;
;; The last two read as &0360, the NFS's version, 3.60, as *HELP prints it; the last is also the place of an entry 0
;; in <NFS_DISPATCH_LOW>, which no call uses.
NFS_UNUSED_BYTES:
    .byte $01, $00, $60, $03

;; The low bytes of the addresses, less one, of the routines <NFS_DISPATCH> enters: entries 1-37.
;;
;; The entries are listed in <NFS_DISPATCH_ENTRIES>: the service calls, the OS procedure calls, the filing system
;; control calls, the command codes of the file server's replies to a command line, and OSBYTE &32-&35. The last
;; entry is also the place of an entry 0 in <NFS_DISPATCH_HIGH>.
;; See: <NFS_DISPATCH>, <NFS_DISPATCH_HIGH>
NFS_DISPATCH_LOW:
    NFS_DISPATCH_ENTRIES NFS_DISPATCH_LOW_BYTE

;; The high bytes of the addresses, less one, of the routines <NFS_DISPATCH> enters.
;; See: <NFS_DISPATCH_LOW>
NFS_DISPATCH_HIGH:
    NFS_DISPATCH_ENTRIES NFS_DISPATCH_HIGH_BYTE
    .assert NFS_DISPATCH_HIGH - NFS_DISPATCH_LOW = 37, "The dispatch table has 37 entries."

; ---------------------------------------------------------------------------------------------------------------------
; Dispatching calls
; ---------------------------------------------------------------------------------------------------------------------

;; Service 7, an unrecognised OSBYTE: carries out OSBYTE &32-&35, the NFS's own.
;;
;; The call's number is in OS_A; carry is clear, as the service dispatch leaves it, so the SBC takes &32 off.
;; In: Y = the OSBYTE's Y, as the service call gives it
;; Out: NFS_SERVICE_RESULT = 0 when the call is the NFS's
;; See: <NFS_DISPATCH>
NFS_SERVICE_UNRECOGNISED_OSBYTE:
    lda OS_A
    sbc #NFS_FIRST_OSBYTE - 1       ; carry is clear: A = the OSBYTE number less &32
    cmp #NFS_OSBYTE_COUNT
    bcs NFS_PROCEDURE_CALL_CHECK    ; not one of the NFS's: leave the call unclaimed
    tax
    lda #0
    sta NFS_SERVICE_RESULT          ; claim the call
    tya
    ldy #NFS_OSBYTE_ENTRIES - 1
    bne NFS_DISPATCH                ; always

I_AM_COMMAND_SKIP:
    iny
;; *I AM: logs on to the file server, after taking the file server's number from the command if it gives one.
;;
;; A number before the user name, "station" or "network.station", chooses the file server (a station of 0 leaves
;; it as it was). The whole command line goes to the file server; if it holds a colon, the last colon and what
;; follows are replaced by a password, typed after the colon is printed and read without being echoed. The
;; command table in NetCommands.asm enters here, with the command after the name.
;; In: Y = the offset of the text after the command's name at (NFS_CALL_XY), NFS_NAME_POINTER = the command line
;; Uses: A, X, Y, NFS_FS_STATION, NFS_FS_NETWORK, NFS_REQUEST
;; Errors: "Escape" while the password is typed, and those of <FS_COMMAND>
;; See: <FILE_SERVER_COMMAND>
I_AM_COMMAND:
    lda (NFS_CALL_XY),y
    cmp #' '
    beq I_AM_COMMAND_SKIP
    cmp #'9' + 1
    bcs I_AM_COMMAND_LINE           ; not a digit: no file server number
    jsr NFS_READ_DECIMAL
    bcc I_AM_COMMAND_STATION        ; no full stop: the number is the station
    sta NFS_FS_NETWORK
    iny
    jsr NFS_READ_DECIMAL
I_AM_COMMAND_STATION:
    beq I_AM_COMMAND_LINE           ; station 0: keep the current file server
    sta NFS_FS_STATION
I_AM_COMMAND_LINE:
    jsr COPY_NAME_TO_REQUEST                       ; copy the command line to NFS_REQUEST_DATA; X and Y = its length
I_AM_COMMAND_FIND_COLON:
    dey
    beq FILE_SERVER_COMMAND_SEND
    lda NFS_REQUEST_DATA,y
    cmp #':'
    bne I_AM_COMMAND_FIND_COLON
    jsr OSWRCH
I_AM_COMMAND_PASSWORD:
    jsr NFS_CHECK_ESCAPE
    jsr OSRDCH
    sta NFS_REQUEST_DATA,y          ; over the colon and what followed it
    iny
    inx
    cmp #$0D
    bne I_AM_COMMAND_PASSWORD
    jsr OSNEWL
    bne I_AM_COMMAND_FIND_COLON     ; always: OSNEWL returns a carriage return

;; Sends a * command to the file server as a command line, and acts on the command code of its reply.
;;
;; The command table in NetCommands.asm enters here for *I., and for any command it does not know. A reply whose
;; command code is zero has nothing more to do; codes 1-9 are dispatched to entries 25-33 of <NFS_DISPATCH_LOW>,
;; with Y = the reply's first byte of data.
;; In: NFS_NAME_POINTER = the command line
;; Uses: A, X, Y, NFS_REQUEST
;; Errors: those of <FS_COMMAND>
FILE_SERVER_COMMAND:
    jsr COPY_NAME_TO_REQUEST                       ; copy the command line to NFS_REQUEST_DATA; X = its length
    tay                             ; Y = 0, NFS_FS_COMMAND_LINE
FILE_SERVER_COMMAND_SEND:
    jsr FS_COMMAND
    ldx NFS_REPLY_COMMAND
    beq NFS_NO_OPERATION                  ; command code 0: done
    lda NFS_REPLY_DATA
    ldy #NFS_REPLY_ENTRIES - 1
    bne NFS_DISPATCH                ; always

;; The NFS's filing system control call, through FSCV: carries out FSCV 0-7, returning what each call's routine does.
;; In: A = the call, X, Y = its parameters
;; See: <NFS_DISPATCH>
NFS_FSC:
    jsr SAVE_COMMAND_REGISTERS
    cmp #NFS_FSC_COUNT
    bcs NFS_NO_OPERATION
    tax
    tya
    ldy #NFS_FSC_ENTRIES - 1
    bne NFS_DISPATCH                ; always

;; The language entry's routine: carries out an OS procedure call that another station sent.
;; In: X = the procedure, 0-4
;; See: <NFS_LANGUAGE_ENTRY>, <NFS_DISPATCH>
NFS_PROCEDURE_CALL:
    cpx #NFS_PROCEDURE_COUNT
NFS_PROCEDURE_CALL_CHECK:
    bcs NFS_NO_OPERATION
    ldy #NFS_PROCEDURE_ENTRIES - 1
;; Enters the routine of an entry in <NFS_DISPATCH_LOW>, through an RTS.
;;
;; The entry is the call's number plus one more than Y: each kind of call passes the entry for call 0, less one.
;; In: X = the call's number, Y = the entry for call 0 less one, A = what the routine takes in Y
;; Out: (to the routine) Y = A, X = the low byte of NFS_CALL_XY
;; Uses: A, X, Y
NFS_DISPATCH:
    inx
    dey
    bpl NFS_DISPATCH
    tay
    lda NFS_DISPATCH_HIGH-1,x
    pha
    lda NFS_DISPATCH_LOW-1,x
    pha
    ldx NFS_CALL_XY
;; Returns, doing nothing: the routine of the calls the NFS ignores.
NFS_NO_OPERATION:
    rts

; ---------------------------------------------------------------------------------------------------------------------
; Service calls
; ---------------------------------------------------------------------------------------------------------------------

;; The service call handler: offers each call to the DFS and the NFS, and carries out the NFS's.
;;
;; Bit 7 of the start-up options (the keyboard links) decides which of the two filing systems sees a call first: set,
;; the DFS, <DFS_SERVICE_ENTRY>, is called before the NFS; clear, after it. The DFS gets the call with A = 0 if the NFS
;; claimed it.
;;
;; At service 1, the first at a reset, the NFS checks the ADLC's status registers: when either has a bit set that it
;; should not, no Econet interface is fitted, and the NFS sets bit 7 of its byte in ROM_WORKSPACE_TABLE. From then
;; on it ignores every call but the Tube's, &FE and &FF:
;;
;; - &FE, Tube post initialisation: with a Tube, explodes the font and prints the second processor's start-up
;;   message, which arrives through register 1 and ends in a zero.
;; - &FF, Tube main initialisation: starts the Tube host code (<START_TUBE>).
;;
;; Services 0-&0C, and &12 for filing system 5, go to their routines in <NFS_DISPATCH_LOW> with NFS_SERVICE_Y and
;; NFS_SERVICE_RESULT set; a routine claims the call by clearing NFS_SERVICE_RESULT. The two are kept on the stack
;; meanwhile, since the routines issue service calls of their own.
;; In: A = the service, X = this ROM's number, Y = the service's parameter
;; Out: A = 0 if the call was claimed, X = this ROM's number, Y = the service's result
;; See: <NFS_DISPATCH_ENTRIES>
NFS_SERVICE:
    bit STARTUP_OPTIONS
    php
    bpl NFS_SERVICE_NET
    jsr DFS_SERVICE_ENTRY                       ; the DFS first
NFS_SERVICE_NET:
    pha
    cmp #ABSOLUTE_WORKSPACE_SERVICE
    bne NFS_SERVICE_CHECK_ENABLED
    lda ADLC_STATUS_1
    and #NFS_ADLC_SR1_ODD
    bne NFS_SERVICE_NO_ADLC
    lda ADLC_STATUS_2
    and #NFS_ADLC_SR2_ODD
    beq NFS_SERVICE_CHECK_ENABLED
NFS_SERVICE_NO_ADLC:
    rol ROM_WORKSPACE_TABLE,x       ; set bit 7: the NFS is disabled
    sec
    ror ROM_WORKSPACE_TABLE,x
NFS_SERVICE_CHECK_ENABLED:
    lda ROM_WORKSPACE_TABLE,x
    asl a                           ; carry = set if disabled
    pla
    bmi NFS_SERVICE_TUBE            ; the Tube's calls come whether or not
    bcs NFS_SERVICE_PASS
NFS_SERVICE_TUBE:
    cmp #TUBE_POST_INIT_SERVICE
    bcc NFS_SERVICE_NUMBERED
    bne START_TUBE                  ; &FF
    cpy #0
    beq NFS_SERVICE_NUMBERED        ; no Tube: leave &FE unclaimed
    ldx #6                          ; explode all the soft characters
    lda #NFS_OSBYTE_EXPLODE_FONT
    jsr OSBYTE
NFS_SERVICE_TUBE_MESSAGE:
    bit TUBE_R1_STATUS              ; wait for a character from the second processor
    bpl NFS_SERVICE_TUBE_MESSAGE
    lda TUBE_R1_DATA
    beq NFS_SERVICE_CLAIM           ; a zero ends its message
    jsr OSWRCH
    jmp NFS_SERVICE_TUBE_MESSAGE

;; Service &FF, Tube main initialisation: copies the Tube host code to RAM and points BRKV and EVNTV at it.
;;
;; Pages four to six are copied whole from the ROM, so the 50 bytes of NFS code after the Tube host code are copied
;; along with it, harmlessly. The code for zero page is copied to &0016-&0076, which takes in the first 32 bytes of
;; page four's code too. The service is then claimed.
;; Uses: A, X, Y, BRKV, EVNTV
;; See: <TUBE_BRK_HANDLER>, <TUBE_ENTRY_CODE>
START_TUBE:
    lda #<TUBE_SEND_EVENT
    sta EVNTV
    lda #>TUBE_SEND_EVENT
    sta EVNTV+1
    lda #<TUBE_BRK_HANDLER                     ; the Tube host code's error handler, at &0016
    sta BRKV
    lda #>TUBE_BRK_HANDLER
    sta BRKV+1
    lda #NFS_TUBE_INTERRUPTS
    sta TUBE_R1_STATUS              ; set the Tube ULA's control flags
    ldy #0
START_TUBE_COPY_PAGES:
    lda TUBE_PAGES_IMAGE,y
    sta TUBE_ENTRY_CODE,y
    lda TUBE_PAGES_IMAGE+$100,y
    sta TUBE_COMMANDS,y
    lda TUBE_PAGES_IMAGE+$200,y
    sta TUBE_COMMANDS+$100,y
    dey
    bne START_TUBE_COPY_PAGES
    jsr TUBE_MARK_FREE                       ; mark the Tube free
    ldx #NFS_TUBE_ZERO_PAGE_COPY
START_TUBE_COPY_ZERO_PAGE:
    lda TUBE_ZERO_PAGE_IMAGE,x
    sta TUBE_BRK_HANDLER,x
    dex
    bpl START_TUBE_COPY_ZERO_PAGE
NFS_SERVICE_CLAIM:
    lda #0                          ; claim the call through service 0's routine
NFS_SERVICE_NUMBERED:
    cmp #INITIALISE_FS_SERVICE
    bne NFS_SERVICE_CHECK
    cpy #NFS_FILING_SYSTEM
    bne NFS_SERVICE_CHECK
    lda #NFS_SERVICE_COUNT          ; service &12 for the NFS takes the entry after the last service's
    bne NFS_SERVICE_CALL            ; always
NFS_SERVICE_CHECK:
    cmp #NFS_SERVICE_COUNT
NFS_SERVICE_PASS:
    bcs NFS_SERVICE_EXIT            ; not one of the NFS's
NFS_SERVICE_CALL:
    tax
    lda NFS_SERVICE_RESULT
    pha
    lda NFS_SERVICE_Y
    pha
    stx NFS_SERVICE_RESULT
    sty NFS_SERVICE_Y
    tya
    ldy #NFS_SERVICE_ENTRIES - 1
    jsr NFS_DISPATCH
    ldx NFS_SERVICE_RESULT
    pla
    sta NFS_SERVICE_Y
    pla
    sta NFS_SERVICE_RESULT
    txa
    ldx ROMSEL_COPY
NFS_SERVICE_EXIT:
    plp
    bmi NFS_SERVICE_DONE            ; the DFS has had the call already
    jmp DFS_SERVICE_ENTRY                       ; the DFS last

;; Service 4, an unrecognised command: carries out *ROFF and *NET.
;; In: Y = the offset of the command at (TEXT_POINTER)
;; Out: NFS_SERVICE_RESULT = 0 if it was one of them, Y = as on entry
;; See: <ROFF_COMMAND>, <NFS_COMMAND>
NFS_SERVICE_UNRECOGNISED_COMMAND:
    ldx #NFS_ROFF_NAME - NFS_ROM_VERSION
    jsr NFS_MATCH_COMMAND_NAME
    bne NFS_SERVICE_TRY_NET
;; *ROFF, and OSBYTE &35: ends the control another station has over this one through *REMOTE.
;;
;; If the NFS is under *REMOTE control, this re-enables the keyboard, tells the controlling station
;; (<SEND_REMOTE_MESSAGE> with A = &0A) and stops the Econet intercepting OS calls and OSWRCH. The call is claimed
;; either way.
;; Uses: A, X, Y
;; See: <PROCEDURE_START_REMOTE>
ROFF_COMMAND:
    ldy #NFS_REMOTE_STATE
    lda (NFS_WORKSPACE_PAGE),y
    beq NFS_SET_INTERCEPTION_DONE
    lda #0
    tax
    sta (NFS_WORKSPACE_PAGE),y
    tay
    lda #NFS_OSBYTE_KEYBOARD_DISABLE ; X = 0: enable the keyboard
    jsr OSBYTE
    lda #$0A
    jsr SEND_REMOTE_MESSAGE
;; Sets or clears the Econet's interception of OS calls and OSWRCH (OSBYTE &CE and &D0), and claims the call.
;;
;; OSBYTE leaves A as it was and returns with carry set, so the ADC adds two: the loop writes OSBYTE &CE, then &D0,
;; leaving OSRDCH's interception (&CF) alone. NFS_BLOCKS_PAGE's low byte, normally 0, holds X meanwhile.
;; In: X = NFS_INTERCEPT to intercept, or 0 to stop
;; Out: NFS_SERVICE_RESULT = 0
;; Uses: A, X, Y
NFS_SET_INTERCEPTION:
    stx NFS_BLOCKS_PAGE
    lda #NFS_OSBYTE_OS_INTERCEPT
NFS_SET_INTERCEPTION_LOOP:
    ldx NFS_BLOCKS_PAGE
    ldy #<~NFS_INTERCEPT            ; keep the other bits
    jsr OSBYTE
    adc #1                          ; carry is set: the next call is &D0
    cmp #NFS_OSBYTE_WRCH_INTERCEPT
    beq NFS_SET_INTERCEPTION_LOOP
NFS_SET_INTERCEPTION_DONE:
    lda #0
    sta NFS_SERVICE_RESULT
    sta NFS_BLOCKS_PAGE
NFS_SERVICE_DONE:
    rts

NFS_SERVICE_TRY_NET:
    ldx #NFS_NET_NAME - NFS_ROM_VERSION
    jsr NFS_MATCH_COMMAND_NAME
    bne NFS_SERVICE_NOT_CLAIMED
;; *NET, and service &12 for filing system 5: selects the NFS as the filing system.
;;
;; It tells the current filing system that a new one is taking over, issues services &0F and &0A, restores
;; NFS_FS_STATION from the private workspace, and goes on to set the vectors (<NFS_SET_VECTORS>). Bit 7 of
;; NFS_SERVICE_Y is set first, so that there is no boot.
;; Uses: A, X, Y
NFS_COMMAND:
    jsr ANNOUNCE_NEW_FILING_SYSTEM
    sec
    ror NFS_SERVICE_Y               ; no boot
    jsr NFS_CLAIM_AND_BOOT
    ldy #NFS_SAVED_STATE_END
NFS_COMMAND_RESTORE:
    lda (NFS_WORKSPACE_PAGE),y
    sta NFS_FS_STATION - NFS_SAVED_STATE,y
    dey
    cpy #NFS_SAVED_STATE - 1
    bne NFS_COMMAND_RESTORE
    beq NFS_SET_VECTORS             ; always

;; Service 9, *HELP: prints the NFS's version, leaving the call for the other ROMs.
;; Out: Y = NFS_SERVICE_Y
;; Uses: A
NFS_SERVICE_HELP:
    jsr NFS_PRINT_INLINE
    .byte $0D, "NFS 3.60", $0D
    ; the LDY's opcode, with bit 7 set, ends the text
;; Leaves a service call unclaimed, with Y as the service gave it.
;; Out: Y = NFS_SERVICE_Y
NFS_SERVICE_NOT_CLAIMED:
    ldy NFS_SERVICE_Y
    rts

;; Tells the current filing system that a new one is about to take over: FSCV 6.
;; Uses: A, X, Y
ANNOUNCE_NEW_FILING_SYSTEM:
    lda #NFS_FSC_NEW_FS
    jmp (FSCV)

;; Service 3, auto-boot: starts the NFS at BREAK unless a key other than N is held down.
;;
;; The current filing system is told first that a new one is taking over. With N held, OSBYTE &78 records N as the
;; first key held and no key as the last one pressed. Starting prints "Econet Station n" and, when the network has
;; no clock, " No Clock", then sets the vectors and, if Y was zero, boots.
;; In: Y = 0 to boot
;; See: <NFS_SET_VECTORS>
NFS_SERVICE_AUTO_BOOT:
    jsr ANNOUNCE_NEW_FILING_SYSTEM
    lda #NFS_OSBYTE_SCAN_KEYBOARD
    jsr OSBYTE
    txa
    bmi NFS_START                   ; no key
    eor #NFS_KEY_N
    bne NFS_SERVICE_NOT_CLAIMED
    tay
    lda #NFS_OSBYTE_WRITE_KEYS_PRESSED
    jsr OSBYTE
NFS_START:
    jsr NFS_PRINT_INLINE
    .byte "Econet Station "
    ldy #NFS_STATION
    lda (NFS_WORKSPACE_PAGE),y
    jsr PRINT_DECIMAL                       ; print it in decimal
    lda #NFS_ADLC_NO_CLOCK
    bit ADLC_STATUS_2
    beq NFS_START_NEW_LINES
    jsr NFS_PRINT_INLINE
    .byte " No Clock"
    nop                             ; ends the text
NFS_START_NEW_LINES:
    jsr NFS_PRINT_INLINE
    .byte $0D, $0D
    ; the LDY's opcode, with bit 7 set, ends the text
;; Points the filing system vectors and NETV at the NFS, claims the call, and boots if NFS_SERVICE_Y is zero.
;;
;; FILEV-FSCV get their extended vector entries, with the NFS's routines in their extended vectors.
;; In: NFS_SERVICE_Y = 0 to boot
;; Out: NFS_SERVICE_RESULT = 0
;; Uses: A, X, Y, FILEV..FSCV+1, NETV, ROM_POINTER
NFS_SET_VECTORS:
    ldy #NFS_VECTOR_VALUES_END - NFS_VECTOR_VALUES - 1
NFS_SET_VECTORS_LOOP:
    lda NFS_VECTOR_VALUES,y
    sta FILEV,y
    dey
    bpl NFS_SET_VECTORS_LOOP
    jsr NFS_SET_NETV
    ldy #NFS_EXTENDED_OFFSET(FILEV)
    ldx #(FSCV - FILEV) / 2 + 1
    jsr NFS_SET_EXTENDED_VECTORS
    stx NFS_SERVICE_RESULT          ; X = 0: claim the call
;; Issues services &0F (vectors claimed) and &0A (claim the static workspace), then boots if NFS_SERVICE_Y is zero.
;;
;; The boot logs on as the user BOOT, through the command "I .BOOT", which is *I AM abbreviated.
;; In: NFS_SERVICE_Y = 0 to boot
;; Uses: A, X, Y
NFS_CLAIM_AND_BOOT:
    lda #NFS_OSBYTE_SERVICE
    ldx #VECTORS_CLAIMED_SERVICE
    jsr OSBYTE
    ldx #STATIC_WORKSPACE_SERVICE
    jsr OSBYTE
    ldx NFS_SERVICE_Y
    bne NFS_ABSOLUTE_WORKSPACE_DONE
NFS_BOOT:
    ldx #<NFS_BOOT_COMMAND
    ldy #>NFS_BOOT_COMMAND
    jmp NFS_UNRECOGNISED_COMMAND                       ; as FSCV 3

;; The command that boots the NFS: *I AM BOOT, abbreviated.
NFS_BOOT_COMMAND:
    .byte "I .BOOT", $0D

;; The values for FILEV-FSCV: their extended vector entries.
NFS_VECTOR_VALUES:
    .word NFS_EXTENDED_ENTRY(FILEV)
    .word NFS_EXTENDED_ENTRY(ARGSV)
    .word NFS_EXTENDED_ENTRY(BGETV)
    .word NFS_EXTENDED_ENTRY(BPUTV)
    .word NFS_EXTENDED_ENTRY(GBPBV)
    .word NFS_EXTENDED_ENTRY(FINDV)
    .word NFS_EXTENDED_ENTRY(FSCV)
NFS_VECTOR_VALUES_END:

;; The NFS's routines for the extended vectors of FILEV-FSCV, in the extended vectors' layout.
;;
;; <NFS_SET_EXTENDED_VECTORS> copies each address and writes the ROM's number over the third byte, so those bytes
;; ("J", "D", "W", "B", "A" and "R") are never used. The last entry's third byte is the first of the code that
;; follows.
NFS_VECTOR_HANDLERS:
    NFS_VECTOR_HANDLER NFS_OSFILE, 'J'
    NFS_VECTOR_HANDLER NFS_OSARGS, 'D'
    NFS_VECTOR_HANDLER NFS_OSBGET, 'W'
    NFS_VECTOR_HANDLER NFS_OSBPUT, 'B'
    NFS_VECTOR_HANDLER NFS_OSGBPB, 'A'
    NFS_VECTOR_HANDLER NFS_OSFIND, 'R'
    .word NFS_FSC

;; Service 1, absolute workspace claim: claims pages &0E and &0F.
;; In: Y = the top page claimed so far
;; Out: Y = &10 or more
NFS_SERVICE_ABSOLUTE_WORKSPACE:
    cpy #>NFS_REQUEST + 1
    bcs NFS_ABSOLUTE_WORKSPACE_DONE
    ldy #>NFS_REQUEST + 1
NFS_ABSOLUTE_WORKSPACE_DONE:
    rts

;; The NFS's routine for NETV's extended vector.
NFS_NETV_HANDLER:
    .word NETV_HANDLER

;; Service 2, private workspace claim: claims two pages and, after a power-on or hard reset, sets up the NFS's state.
;;
;; The two pages become NFS_WORKSPACE_PAGE and NFS_BLOCKS_PAGE. The *REMOTE state is cleared, and the transmitter
;; marked busy until the Econet starts. Unless the reset was a soft BREAK, the file server becomes station &FE on
;; network 0, the protection, boot option and *OPT 1 setting are cleared, receive block 0's station becomes &EB on
;; network 0, and every receive control block is marked free. Then the station's number is read, the Econet is
;; started (<ECONET_INITIALISE>), reception into the private page's blocks is enabled, and NETV is pointed at the NFS.
;; In: Y = the first page available
;; Out: Y = the page after the NFS's
;; Uses: A, X
NFS_SERVICE_PRIVATE_WORKSPACE:
    sty NFS_WORKSPACE_PAGE+1
    iny
    sty NFS_BLOCKS_PAGE+1
    lda #0
    ldy #NFS_REMOTE_STATE
    sta (NFS_WORKSPACE_PAGE),y
    ldy #$FF
    sta NFS_WORKSPACE_PAGE
    sta NFS_BLOCKS_PAGE
    sta NFS_BLOCK_NUMBER
    sta NFS_TRANSMIT_FREE
    tax
    lda #NFS_OSBYTE_LAST_BREAK
    jsr OSBYTE
    txa
    beq NFS_SERVICE_PRIVATE_WORKSPACE_STATION ; soft BREAK: keep the state
    ldy #NFS_SAVED_STATE
    lda #$FE                        ; the default file server, station 254
    sta NFS_FS_STATION
    sta (NFS_WORKSPACE_PAGE),y
    lda #0
    sta NFS_FS_NETWORK
    sta NFS_PROTECTION
    sta NFS_MESSAGES
    sta NFS_BOOT_OPTION
    iny
    sta (NFS_WORKSPACE_PAGE),y
    ldy #NFS_BLOCK_0_STATION + 1
    sta (NFS_BLOCKS_PAGE),y
    dey
    lda #$EB                        ; station 235
    sta (NFS_BLOCKS_PAGE),y
NFS_SERVICE_PRIVATE_WORKSPACE_FREE:
    lda NFS_BLOCK_NUMBER
    jsr FIND_RECEIVE_BLOCK                       ; Y = the block's offset; carry = set past the last
    bcs NFS_SERVICE_PRIVATE_WORKSPACE_STATION
    lda #NFS_FREE_BLOCK
    sta (NFS_BLOCKS_PAGE),y
    inc NFS_BLOCK_NUMBER
    bne NFS_SERVICE_PRIVATE_WORKSPACE_FREE ; always
NFS_SERVICE_PRIVATE_WORKSPACE_STATION:
    lda STATION_ID
    ldy #NFS_STATION
    sta (NFS_WORKSPACE_PAGE),y
    jsr ECONET_INITIALISE                       ; start the Econet
    lda #%01000000                  ; receive into the private page's blocks
    sta NFS_LISTENING
;; Points NETV at its extended vector entry, and the extended vector at the NFS's routine.
;;
;; Only NETV's low byte is written: the MOS's default for it is in page &FF already.
;; Out: Y = the page after the NFS's private workspace
;; Uses: A, X, ROM_POINTER
NFS_SET_NETV:
    lda #NFS_OSBYTE_EXTENDED_VECTORS
    ldx #0
    ldy #$FF
    jsr OSBYTE
    stx ROM_POINTER
    sty ROM_POINTER+1
    ldy #NFS_EXTENDED_OFFSET(NETV)
    sty NETV                        ; the low byte of NFS_EXTENDED_ENTRY(NETV)
    .assert NFS_EXTENDED_ENTRY {NETV} - NFS_EXTENDED_OFFSET {NETV} = EXTENDED_VECTOR_ENTRIES, "NETV: page &FF"
    ldx #1
;; Copies routines from <NFS_VECTOR_HANDLERS> or <NFS_NETV_HANDLER> to extended vectors, with this ROM's number.
;; In: X = the number of vectors, Y = the first one's offset, ROM_POINTER = the extended vectors' address
;; Out: X = 0, Y = the page after the NFS's private workspace
;; Uses: A
NFS_SET_EXTENDED_VECTORS:
    lda NFS_VECTOR_HANDLERS - NFS_EXTENDED_OFFSET(FILEV),y
    sta (ROM_POINTER),y
    iny
    lda NFS_VECTOR_HANDLERS - NFS_EXTENDED_OFFSET(FILEV),y
    sta (ROM_POINTER),y
    iny
    lda ROMSEL_COPY
    sta (ROM_POINTER),y
    iny
    dex
    bne NFS_SET_EXTENDED_VECTORS
    ldy NFS_BLOCKS_PAGE+1
    iny
    rts
    .assert NFS_EXTENDED_OFFSET {NETV} - NFS_EXTENDED_OFFSET {FILEV} = NFS_NETV_HANDLER - NFS_VECTOR_HANDLERS, "NETV."

;; FSCV 6, a new filing system is about to take over: keeps NFS_FS_STATION in the private workspace, and closes the
;; *SPOOL and *EXEC files.
;; Uses: A, X, Y
NFS_FSC_NEW_FILING_SYSTEM:
    ldy #NFS_SAVED_STATE_END
NFS_FSC_NEW_FILING_SYSTEM_LOOP:
    lda NFS_FS_STATION - NFS_SAVED_STATE,y
    sta (NFS_WORKSPACE_PAGE),y
    dey
    cpy #NFS_SAVED_STATE - 1
    bne NFS_FSC_NEW_FILING_SYSTEM_LOOP
    lda #NFS_OSBYTE_CLOSE_SPOOL_EXEC
    jmp OSBYTE

;; Matches the command at (TEXT_POINTER),NFS_SERVICE_Y with a name in the ROM's header, ignoring case.
;;
;; A full stop ends an abbreviation. The command matches only when nothing but spaces follows it.
;; In: X = the name's offset from <NFS_ROM_VERSION>, NFS_SERVICE_Y = the command's offset
;; Out: zero = set for a match, Y = the offset after it
;; Uses: A, X
NFS_MATCH_COMMAND_NAME:
    ldy NFS_SERVICE_Y
NFS_MATCH_COMMAND_NAME_LOOP:
    lda (TEXT_POINTER),y
    cmp #'.'
    beq NFS_SKIP_SPACES_NEXT
    and #%11011111                  ; capitals; a space becomes zero
    beq NFS_MATCH_COMMAND_NAME_END
    cmp NFS_ROM_VERSION,x
    bne NFS_MATCH_COMMAND_NAME_END
    iny
    inx
    bne NFS_MATCH_COMMAND_NAME_LOOP     ; always
NFS_MATCH_COMMAND_NAME_END:
    lda NFS_ROM_VERSION,x
    beq NFS_SKIP_SPACES                 ; the whole name matched
    rts
NFS_SKIP_SPACES_NEXT:
    iny
;; Skips spaces at (TEXT_POINTER),Y, and says whether the line ends there.
;; In: Y = the offset
;; Out: Y = the offset of the first character that is not a space, zero = set if it is a carriage return
;; Uses: A
NFS_SKIP_SPACES:
    lda (TEXT_POINTER),y
    cmp #' '
    beq NFS_SKIP_SPACES_NEXT
    eor #$0D
    rts

; ---------------------------------------------------------------------------------------------------------------------
; Talking to the file server
; ---------------------------------------------------------------------------------------------------------------------

;; Sets up NFS_FS_BLOCK to receive the file server's reply into NFS_REPLY_COMMAND, on port &90.
;; Out: Y = &FF
;; Uses: A
SET_UP_REPLY_BLOCK:
    lda #NFS_PORT_REPLY
;; Sets up NFS_FS_BLOCK to receive from the file server into NFS_REPLY_COMMAND on a port.
;; In: A = the port
;; Out: Y = &FF
SET_UP_RECEIVE_BLOCK:
    jsr SET_UP_FS_CONTROL_BLOCK
    sta NFS_FS_BLOCK_PORT
    lda #<NFS_REPLY_COMMAND
    sta NFS_FS_BLOCK_START
    dec NFS_FS_BLOCK                ; &7F: receive
    rts

;; Copies <FS_CONTROL_BLOCK_TEMPLATE> to NFS_FS_BLOCK, with the file server's station and network.
;; Out: Y = &FF
;; Keeps: A, X
SET_UP_FS_CONTROL_BLOCK:
    pha
    ldy #FS_CONTROL_BLOCK_TEMPLATE_END - FS_CONTROL_BLOCK_TEMPLATE - 1
SET_UP_FS_CONTROL_BLOCK_LOOP:
    lda FS_CONTROL_BLOCK_TEMPLATE,y
    sta a:NFS_FS_BLOCK,y
    cpy #2
    bpl SET_UP_FS_CONTROL_BLOCK_NEXT
    lda NFS_FS_STATION,y
    sta a:NFS_FS_BLOCK_STATION,y
SET_UP_FS_CONTROL_BLOCK_NEXT:
    dey
    bpl SET_UP_FS_CONTROL_BLOCK_LOOP
    pla
    rts

;; A control block that sends NFS_REQUEST to the file server's command port.
;;
;; The station and network are filled in from NFS_FS_STATION, and the end's low byte from the request's length.
;; The buffer addresses are 32 bits, &FFFF in the top half for the I/O processor.
;; See: <SET_UP_FS_CONTROL_BLOCK>
FS_CONTROL_BLOCK_TEMPLATE:
    .byte $80                       ; transmit
    .byte NFS_PORT_COMMAND
    .byte 0, 0                      ; station and network
    .word NFS_REQUEST               ; start

;; The rest of <FS_CONTROL_BLOCK_TEMPLATE>: the start's top half, then the end.
;;
;; Its first byte, &FF, is also what other parts BIT to set overflow.
FS_CONTROL_BLOCK_TEMPLATE_HIGH:
    .word $FFFF
    .word NFS_REQUEST + $FF         ; end
    .word $FFFF
FS_CONTROL_BLOCK_TEMPLATE_END:

;; Sends a request whose reply waits on the handle's sequence bit, and checks the reply.
;; In: A = the file server's handle, X = the length of the data, Y = the function, NFS_REQUEST_DATA = the data
;; Out: NFS_SEQUENCE_RESULT = the new sequence bits, X = 0
;; Uses: A, Y, NFS_FS_BLOCK
;; Errors: those of <FS_COMMAND>
;; See: <SEND_SEQUENCED_BLOCK>
FS_COMMAND_SEQUENCED:
    pha
    sec
    bcs FS_COMMAND_FUNCTION         ; always

;; Sends a request to the file server with NFS_REQUEST_URD as the caller set it, and checks the reply.
;; In: X = the length of the data, Y = the function, NFS_REQUEST_URD = the port for the data
;; Out: Y = 1, X = 0
;; Uses: A, NFS_FS_BLOCK
;; Errors: those of <FS_COMMAND>
FS_COMMAND_WITH_PORT:
    clv
    bvc FS_COMMAND_CLEAR_CARRY      ; always

;; *BYE: closes the *SPOOL and *EXEC files and logs off.
;; Errors: those of <FS_COMMAND>
BYE_COMMAND:
    lda #NFS_OSBYTE_CLOSE_SPOOL_EXEC
    jsr OSBYTE
    ldy #NFS_FS_BYE
;; Sends a request to the file server and waits for its reply, raising the error it holds if there is one.
;;
;; The request at NFS_REQUEST is the reply port, the function, the handles of the user root, current and library
;; directories, then X bytes of data. The reply comes to NFS_REPLY_COMMAND: its command code, its return code, then its
;; data. A return code other than zero is raised as an error with the reply's message (see <FS_ERROR>).
;; In: X = the length of the data, Y = the function, NFS_REQUEST_DATA = the data
;; Out: Y = 1, X = 0
;; Uses: A, NFS_FS_BLOCK, NFS_BLOCK_POINTER
;; Errors: the file server's, those of <TRANSMIT>, and "No reply" (&A5)
FS_COMMAND:
    clv
;; Sends a request to the file server as <FS_COMMAND> does, returning a "Not found" error if overflow is set.
;; In: X = the length of the data, Y = the function, overflow = set to return error &D6 (Not found) rather than raise
;; Out: carry = set if the file was not found, Y = 1
;; Uses: A, X, NFS_FS_BLOCK, NFS_BLOCK_POINTER
FS_COMMAND_IF_FOUND:
    lda NFS_URD
    sta NFS_REQUEST_URD
FS_COMMAND_CLEAR_CARRY:
    clc
FS_COMMAND_FUNCTION:
    sty NFS_REQUEST_FUNCTION
    ldy #1
FS_COMMAND_COPY_HANDLES:
    lda NFS_CSD,y
    sta NFS_REQUEST_CSD,y
    dey
    bpl FS_COMMAND_COPY_HANDLES
;; Sends the request at NFS_REQUEST, whose function and handles are set, and waits for the reply.
;; In: X = the length of the data, carry = set for a sequenced request (with its handle on the stack),
;;   overflow = as for <FS_COMMAND_IF_FOUND>
;; Inherit: <FS_COMMAND_IF_FOUND> Out
;; Uses: A, X, Y, NFS_FS_BLOCK, NFS_BLOCK_POINTER
FS_SEND_REQUEST:
    php
    lda #NFS_PORT_REPLY
    sta NFS_REQUEST
    jsr SET_UP_FS_CONTROL_BLOCK
    txa
    adc #NFS_REQUEST_DATA - NFS_REQUEST ; one more with carry set
    sta NFS_FS_BLOCK_END
    plp
    bcs FS_SEND_SEQUENCED
    php
    jsr TRANSMIT_FS_BLOCK
    plp
;; Waits for the file server's reply on port &90, and checks it as <FS_COMMAND> does.
;; In: overflow = as for <FS_COMMAND_IF_FOUND>, carry = clear
;; Inherit: <FS_COMMAND_IF_FOUND> Out
;; Uses: A, X, Y, NFS_FS_BLOCK
FS_AWAIT_REPLY:
    php
    jsr SET_UP_REPLY_BLOCK
    jsr AWAIT_RECEPTION
    plp
FS_CHECK_REPLY:
    iny
    lda (NFS_FS_BLOCK_START),y      ; the return code
    tax
    beq FS_CHECK_REPLY_DONE
    bvc FS_CHECK_REPLY_ERROR
    adc #$100 - NFS_ERROR_NOT_FOUND ; carry is clear: zero, with carry set, for "Not found"
FS_CHECK_REPLY_ERROR:
    bne FS_ERROR
FS_CHECK_REPLY_DONE:
    rts

FS_SEND_SEQUENCED:
    pla                             ; the handle
    ldx #<NFS_FS_BLOCK
    iny
    jsr SEND_SEQUENCED_BLOCK                       ; send it and wait for the reply, with the handle's sequence bit
    sta NFS_SEQUENCE_RESULT
    bcc FS_CHECK_REPLY

;; The NFS's OSBPUT, through BPUTV: writes a byte to an open file.
;; In: A = the byte, Y = the handle
;; Keeps: A, X, Y
;; Errors: the file server's, those of <TRANSMIT>, and "No reply" (&A5)
NFS_OSBPUT:
    clc
;; Reads or writes a byte of an open file, through the file server's function 8 or 9.
;;
;; The request and its reply are at NFS_BYTE_REQUEST, with the handle converted to the file server's, and the reply
;; waits on the handle's sequence bit. On an error, the reply is moved up to NFS_BYTE_ERROR, and the *SPOOL or
;; *EXEC file is closed if it is the file in question, before the error is raised.
;; In: A = the byte to write, Y = the handle, carry = set to read
;; Out: NFS_BYTE_REQUEST = the reply
;; Keeps: A, X, Y
;; Errors: the file server's, those of <TRANSMIT>, and "No reply" (&A5)
NFS_BYTE_TRANSFER:
    jsr DISALLOW_ESCAPE
    pha
    sta NFS_BYTE_FLAGS              ; the byte to write
    txa
    pha
    tya
    pha
    php
    sty NFS_BYTE_HANDLE
    jsr HANDLE_TO_MASK
    sty NFS_BYTE_DATA
    sty NFS_BYTE_MASK
    ldy #NFS_PORT_REPLY
    sty NFS_BYTE_REQUEST
    jsr SET_UP_FS_CONTROL_BLOCK
    lda #<NFS_BYTE_REQUEST
    sta NFS_FS_BLOCK_START
    lda #<NFS_BYTE_ERROR
    sta NFS_FS_BLOCK_END
    iny                             ; Y = 0
    ldx #NFS_FS_PUT_BYTE
    plp
    bcc NFS_BYTE_TRANSFER_FUNCTION
    dex                             ; NFS_FS_GET_BYTE
NFS_BYTE_TRANSFER_FUNCTION:
    stx NFS_BYTE_FUNCTION
    lda NFS_BYTE_MASK
    ldx #<NFS_FS_BLOCK
    jsr SEND_SEQUENCED_BLOCK                       ; send it and wait for the reply, with the handle's sequence bit
    ldx NFS_BYTE_FUNCTION           ; the return code
    beq NFS_BYTE_TRANSFER_DONE
    ldy #NFS_REQUEST + $FF - NFS_BYTE_ERROR ; to the end of the page
NFS_BYTE_TRANSFER_MOVE_ERROR:
    lda NFS_BYTE_REQUEST,y
    sta NFS_BYTE_ERROR,y
    dey
    bpl NFS_BYTE_TRANSFER_MOVE_ERROR
    tax                             ; the command code, zero
    lda #NFS_OSBYTE_EXEC_HANDLE     ; Y = &FF: read the *EXEC and *SPOOL handles
    jsr OSBYTE
    lda #<NFS_SPOOL_CLOSE_COMMAND
    cpy NFS_BYTE_HANDLE
    beq NFS_BYTE_TRANSFER_CLOSE
    lda #<NFS_EXEC_CLOSE_COMMAND
    cpx NFS_BYTE_HANDLE
    bne NFS_BYTE_TRANSFER_ERROR
NFS_BYTE_TRANSFER_CLOSE:
    tax
    ldy #>NFS_SPOOL_CLOSE_COMMAND
    .assert >NFS_SPOOL_CLOSE_COMMAND = >NFS_EXEC_CLOSE_COMMAND, "The two commands share a page."
    jsr OSCLI
NFS_BYTE_TRANSFER_ERROR:
    lda #<NFS_BYTE_ERROR
    sta NFS_FS_BLOCK_START
    ldx NFS_BYTE_FUNCTION
;; Raises the error a file server's reply holds.
;;
;; The reply's command code, zero, becomes the BRK; its return code the error number, raised to &A8 if lower (and
;; kept in NFS_LAST_ERROR); and its message, ending in a carriage return, the error message. The reply is copied
;; to the stack page, with a zero for the carriage return, and run there.
;; In: X = the return code, NFS_FS_BLOCK_START = the reply's address
;; See: <NFS_RAISE_ERROR_IN_STACK>
FS_ERROR:
    stx NFS_LAST_ERROR
    ldy #1
    cpx #NFS_ERROR_FIRST_FS
    bcs FS_ERROR_COPY
    lda #NFS_ERROR_FIRST_FS
    sta (NFS_FS_BLOCK_START),y
FS_ERROR_COPY:
    ldy #$FF
FS_ERROR_COPY_LOOP:
    iny
    lda (NFS_FS_BLOCK_START),y
    sta STACK,y
    eor #$0D
    bne FS_ERROR_COPY_LOOP
    sta STACK,y                     ; a zero ends the message
    beq NFS_RAISE_ERROR_IN_STACK        ; always
NFS_BYTE_TRANSFER_DONE:
    sta NFS_SEQUENCE_BITS
    pla
    tay
    pla
    tax
    pla
NFS_CHECK_ESCAPE_DONE:
    rts

;; Raises "Escape" if an ESCAPE condition is pending while NFS_ESCAPE_ENABLE allows it, acknowledging it first.
;; Uses: A
;; Errors: "Escape" (&11)
NFS_CHECK_ESCAPE:
    lda ESCAPE_FLAG
    and NFS_ESCAPE_ENABLE
    bpl NFS_CHECK_ESCAPE_DONE
    lda #NFS_OSBYTE_ACKNOWLEDGE_ESCAPE
    jsr OSBYTE
    jmp NFS_ERROR                   ; A is still &7E: index 6, "Escape"
    .assert (NFS_OSBYTE_ACKNOWLEDGE_ESCAPE & 7) = NFS_ERROR_INDEX_ESCAPE, "OSBYTE &7E's number gives Escape."

; ---------------------------------------------------------------------------------------------------------------------
; OS procedure calls
; ---------------------------------------------------------------------------------------------------------------------

;; OS procedure 1: brings this station under the control of the station that sent the call, as *REMOTE asks.
;;
;; If it is under control already, it only restores the protection. Otherwise it records the controller in
;; receive block 1, has the Econet intercept OS calls and OSWRCH, calls <BUILD_REMOTE_BLOCK>, disables the keyboard, and
;; stops the current program with error 0 (<PROCEDURE_ABANDON>).
;; Uses: A, X, Y
PROCEDURE_START_REMOTE:
    ldy #NFS_REMOTE_STATE
    lda (NFS_WORKSPACE_PAGE),y
    beq START_REMOTE
PROCEDURE_IGNORE:
    jmp RESTORE_PROTECTION                       ; restore the protection
START_REMOTE:
    ora #$09
    sta (NFS_WORKSPACE_PAGE),y
    ldx #NFS_INTERCEPT
    ldy #NFS_CALLER_STATION
    lda (NFS_WORKSPACE_PAGE),y
    pha
    iny
    lda (NFS_WORKSPACE_PAGE),y
    ldy #NFS_CONTROLLER + 1
    sta (NFS_BLOCKS_PAGE),y
    dey
    pla
    sta (NFS_BLOCKS_PAGE),y
    jsr NFS_SET_INTERCEPTION
    jsr BUILD_REMOTE_BLOCK
    ldx #1                          ; disable the keyboard
    ldy #0
    lda #NFS_OSBYTE_KEYBOARD_DISABLE
    jsr OSBYTE
;; OS procedure 3: restores the protection and raises error 0, with no message, to stop the current program.
PROCEDURE_ABANDON:
    jsr RESTORE_PROTECTION
    ldx #2
    lda #0
PROCEDURE_ABANDON_LOOP:
    sta STACK,x                     ; a BRK, error 0 and an empty message
    dex
    bpl PROCEDURE_ABANDON_LOOP
;; Raises the error that has been built in the stack page, by running its BRK.
NFS_RAISE_ERROR_IN_STACK:
    jmp STACK

;; OS procedure 4: a key from another station, which starts *REMOTE control if there is none, and is typed if it
;; comes from the controlling station.
;; Uses: A, X, Y
PROCEDURE_REMOTE_KEY:
    ldy #NFS_REMOTE_STATE
    lda (NFS_WORKSPACE_PAGE),y
    beq START_REMOTE
    ldy #NFS_CALLER_STATION
    lda (NFS_WORKSPACE_PAGE),y
    ldy #NFS_CONTROLLER
    cmp (NFS_BLOCKS_PAGE),y
    bne PROCEDURE_IGNORE
;; OS procedure 0: puts the character that came with the call into the keyboard buffer, as if it were typed.
;; Uses: A, X, Y
PROCEDURE_INSERT_KEY:
    ldy #NFS_CALLER_DATA
    lda (NFS_WORKSPACE_PAGE),y
    tay
    ldx #0                          ; the keyboard buffer
    jsr RESTORE_PROTECTION
    lda #NFS_OSBYTE_INSERT_INPUT
    jmp OSBYTE

; ---------------------------------------------------------------------------------------------------------------------
; The NFS's errors
; ---------------------------------------------------------------------------------------------------------------------

;; Raises "No reply" (&A5).
NFS_RAISE_NO_REPLY:
    lda #NFS_ERROR_INDEX_NO_REPLY
    bne NFS_ERROR_ANY               ; always

;; Raises the error for a control block that failed, from the low three bits of its status.
;; In: X = 0, NFS_BLOCK_POINTER = the control block
NFS_TRANSMIT_ERROR:
    lda (NFS_BLOCK_POINTER,x)
;; Raises one of the NFS's errors, by the low three bits of A.
;; In: A = the index, in bits 0-2
;; See: <NFS_ERROR_OFFSETS>
NFS_ERROR:
    and #7
;; Raises one of the NFS's errors, copying it from <NFS_ERRORS> to the stack page with a BRK before it.
;; In: A = the index, 0-8
NFS_ERROR_ANY:
    tax
    ldy NFS_ERROR_OFFSETS,x
    ldx #0
    stx STACK                       ; BRK
NFS_ERROR_COPY:
    lda NFS_ERRORS,y
    sta STACK+1,x
    beq NFS_RAISE_ERROR_IN_STACK
    iny
    inx
    bne NFS_ERROR_COPY              ; always

;; The command that closes the *SPOOL file.
NFS_SPOOL_CLOSE_COMMAND:
    .byte "SP.", $0D

;; The command that closes the *EXEC file.
NFS_EXEC_CLOSE_COMMAND:
    .byte "E.", $0D

;; Waits for a reception into the control block at NFS_BLOCK_POINTER, raising "No reply" if none comes in time.
;;
;; The block's control byte gets bit 7 set on reception. While a block in zero page is awaited, bit 7 of
;; NFS_LISTENING is set, so that the Econet receives into it. The wait counts down a three-byte count on the stack,
;; &2A times 65536 polls.
;; Out: Y = 0, zero = clear
;; Uses: A, X
;; Errors: "No reply" (&A5)
AWAIT_RECEPTION:
    lda #$2A                        ; the count's top byte
    pha
    lda NFS_LISTENING
    pha
    ldx NFS_BLOCK_POINTER+1
    bne AWAIT_RECEPTION_START
    ora #%10000000                  ; receive into the block at &00C0
    sta NFS_LISTENING
AWAIT_RECEPTION_START:
    lda #0
    pha
    pha
    tay
    tsx
AWAIT_RECEPTION_LOOP:
    lda (NFS_BLOCK_POINTER),y
    bmi AWAIT_RECEPTION_DONE
    dec STACK+1,x
    bne AWAIT_RECEPTION_LOOP
    dec STACK+2,x
    bne AWAIT_RECEPTION_LOOP
    dec STACK+4,x                   ; over NFS_LISTENING's copy
    bne AWAIT_RECEPTION_LOOP
AWAIT_RECEPTION_DONE:
    pla
    pla
    pla
    sta NFS_LISTENING
    pla
    beq NFS_RAISE_NO_REPLY
    rts

;; The NFS's OSBGET, through BGETV: reads a byte from an open file.
;;
;; The file's bit in NFS_EOF_FLAGS is set when the byte read is the last, and cleared otherwise.
;; In: Y = the handle
;; Out: A = the byte, or &FE past the end, carry = set past the end
;; Keeps: X, Y
;; Errors: the file server's, those of <TRANSMIT>, and "No reply" (&A5)
NFS_OSBGET:
    sec
    jsr NFS_BYTE_TRANSFER
    sec
    lda #$FE
    bit NFS_BYTE_FLAGS
    bvs NFS_OSBGET_DONE             ; past the end
    clc
    php
    lda NFS_BYTE_MASK
    plp
    bmi NFS_OSBGET_SET_EOF          ; the last byte
    jsr CLEAR_EOF_FLAGS
NFS_OSBGET_SET_EOF:
    jsr SET_EOF_FLAGS               ; after CLEAR_EOF_FLAGS, this changes nothing
    lda NFS_BYTE_DATA
NFS_OSBGET_DONE:
    rts

;; The errors the NFS raises itself, each its number, message and a zero.
;; See: <NFS_ERROR_OFFSETS>
NFS_ERRORS:
LINE_JAMMED_MESSAGE:
    .byte NFS_ERROR_LINE_JAMMED, "Line Jammed", 0
NFS_ERROR_MESSAGE:
    .byte NFS_ERROR_NET_ERROR, "Net Error", 0
NOT_LISTENING_MESSAGE:
    .byte NFS_ERROR_NOT_LISTENING, "Not listening", 0
NO_CLOCK_MESSAGE:
    .byte NFS_ERROR_NO_CLOCK, "No Clock", 0
ESCAPE_MESSAGE:
    .byte NFS_ERROR_ESCAPE, "Escape", 0
BAD_OPTION_MESSAGE:
    .byte NFS_ERROR_BAD_OPTION, "Bad Option", 0
NO_REPLY_MESSAGE:
    .byte NFS_ERROR_NO_REPLY, "No reply", 0

; ---------------------------------------------------------------------------------------------------------------------
; Helpers
; ---------------------------------------------------------------------------------------------------------------------

;; Converts an OSFILE control block's attributes to the file server's access byte.
;;
;; Attribute bits 0-5 (read, write, execute and locked for the owner, read and write for others) become access bits
;; 2, 3, 7, 4, 0 and 1.
;; In: NFS_CALL_XY = the control block
;; Out: A = the access byte
;; Uses: X, Y, NFS_BIT_SOURCE
ATTRIBUTES_TO_ACCESS:
    ldy #NFS_OSFILE_END
    lda (NFS_CALL_XY),y
    and #%00111111
    ldx #NFS_ACCESS_FROM_ATTRIBUTES - NFS_ACCESS_BITS - 1
    bne CONVERT_ACCESS              ; always
;; Converts the file server's access byte to OSFILE attributes.
;;
;; Access bits 0-4 become attribute bits 4 and 6 (others may read and execute), 5 (others may write), 0 and 2 (the
;; owner may read and execute), 1 (the owner may write), and 3 and 7 (locked).
;; In: A = the access byte
;; Out: A = the attributes
;; Uses: X, NFS_BIT_SOURCE
ACCESS_TO_ATTRIBUTES:
    and #%00011111
    ldx #$FF
CONVERT_ACCESS:
    sta NFS_BIT_SOURCE
    lda #0
CONVERT_ACCESS_LOOP:
    inx
    lsr NFS_BIT_SOURCE
    bcc CONVERT_ACCESS_NEXT         ; zero = set when no bits are left
    ora NFS_ACCESS_BITS,x
CONVERT_ACCESS_NEXT:
    bne CONVERT_ACCESS_LOOP
    rts

;; The bits <CONVERT_ACCESS> sets for each bit of an access byte, then for each bit of OSFILE's attributes.
NFS_ACCESS_BITS:
    .byte %01010000, %00100000, %00000101, %00000010, %10001000
NFS_ACCESS_FROM_ATTRIBUTES:
    .byte %00000100, %00001000, %10000000, %00010000, %00000001, %00000010

;; Transmits NFS_FS_BLOCK, the control block at &00C0, as <TRANSMIT> does.
;; Uses: A, X, Y, NFS_BLOCK_POINTER
;; Errors: those of <TRANSMIT>
TRANSMIT_FS_BLOCK:
    ldx #<NFS_FS_BLOCK
    stx NFS_BLOCK_POINTER
    ldx #>NFS_FS_BLOCK
    stx NFS_BLOCK_POINTER+1
;; Transmits the control block at NFS_BLOCK_POINTER, trying again after a pause when it fails.
;;
;; It waits for the transmitter to be free and claims it, has the Econet transmit the block (<ECONET_TRANSMIT>), and
;; waits for the block's status to lose bit 7. A status with bit 6 clear is success. "Line Jammed" is raised at once;
;; other failures are tried up to 255 more times, each after a pause that depends on the control byte, with ESCAPE
;; checked, before the error the status gives is raised.
;; Out: X = 0
;; Uses: A, Y, NMI_WORKSPACE..NMI_WORKSPACE+1
;; Errors: "Line Jammed" (&A0), "Net Error" (&A1), "Not listening" (&A2), "No Clock" (&A3), "Escape" (&11),
;;   "Bad Option" (&CB)
TRANSMIT:
    lda #$FF                        ; the tries left
    ldy #$60                        ; the pause
    pha
    tya
    pha
    ldx #0
    lda (NFS_BLOCK_POINTER,x)
TRANSMIT_TRY:
    sta (NFS_BLOCK_POINTER,x)       ; the control byte again, over the last status
    pha
TRANSMIT_WAIT_FREE:
    asl NFS_TRANSMIT_FREE
    bcc TRANSMIT_WAIT_FREE
    lda NFS_BLOCK_POINTER
    sta NMI_WORKSPACE
    lda NFS_BLOCK_POINTER+1
    sta NMI_WORKSPACE+1
    jsr ECONET_TRANSMIT                       ; start transmitting
TRANSMIT_WAIT_DONE:
    lda (NFS_BLOCK_POINTER,x)
    bmi TRANSMIT_WAIT_DONE
    asl a
    bpl TRANSMIT_DONE               ; bit 6 clear: sent
    asl a
    beq TRANSMIT_FAILED             ; "Line Jammed"
    jsr NFS_CHECK_ESCAPE
    pla
    tax                             ; X = the control byte
    pla
    tay
    pla
    beq TRANSMIT_FAILED             ; no tries left
    sbc #1                          ; carry is set
    pha
    tya
    pha
    txa
TRANSMIT_PAUSE:
    dex
    bne TRANSMIT_PAUSE
    dey
    bne TRANSMIT_PAUSE
    beq TRANSMIT_TRY                ; always
TRANSMIT_FAILED:
    tax
    jmp NFS_TRANSMIT_ERROR
TRANSMIT_DONE:
    pla
    pla
    pla
    jmp DISALLOW_ESCAPE

;; Keeps the registers of a command or filing system call that has a command line or file name, in TEXT_POINTER
;; too.
;; In: A, X, Y = the call's registers
;; Out: TEXT_POINTER, NFS_CALL_XY, NFS_NAME_POINTER = X and Y, NFS_CALL_A = A
;; Keeps: A, X, Y
SAVE_COMMAND_REGISTERS:
    stx TEXT_POINTER
    sty TEXT_POINTER+1
;; Keeps a filing system call's registers, and stops ESCAPE interrupting.
;; In: A, X, Y = the call's registers
;; Out: NFS_CALL_XY, NFS_NAME_POINTER = X and Y, NFS_CALL_A = A
;; Keeps: A, X, Y
SAVE_CALL_REGISTERS:
    sta NFS_CALL_A
    stx NFS_CALL_XY
    sty NFS_CALL_XY+1
    stx NFS_NAME_POINTER
    sty NFS_NAME_POINTER+1
;; Clears bit 7 of NFS_ESCAPE_ENABLE, so that ESCAPE does not interrupt waits on the network.
;; Keeps: A, X, Y, carry
DISALLOW_ESCAPE:
    php
    lsr NFS_ESCAPE_ENABLE
    plp
    rts

;; Prints the text that follows the JSR to it, through OSASCI, and goes on at the first byte with bit 7 set.
;;
;; That byte, the end of the text, is the next instruction's opcode.
;; Out: Y = 0, A = the byte that ended the text
;; Uses: NFS_INLINE_POINTER
;; Keeps: X
NFS_PRINT_INLINE:
    pla
    sta NFS_INLINE_POINTER
    pla
    sta NFS_INLINE_POINTER+1
    ldy #0
NFS_PRINT_INLINE_NEXT:
    inc NFS_INLINE_POINTER
    bne NFS_PRINT_INLINE_CHARACTER
    inc NFS_INLINE_POINTER+1
NFS_PRINT_INLINE_CHARACTER:
    lda (NFS_INLINE_POINTER),y
    bmi NFS_PRINT_INLINE_DONE
    jsr OSASCI
    jmp NFS_PRINT_INLINE_NEXT
NFS_PRINT_INLINE_DONE:
    jmp (NFS_INLINE_POINTER)

;; Reads a decimal number at (NFS_CALL_XY),Y, up to a full stop or a character below it.
;;
;; Any character above the full stop counts as a digit, by its low four bits.
;; In: Y = the offset of the first digit
;; Out: A = the number, modulo 256, Y = the offset of the character that ended it, carry = set if a full stop,
;;   zero = set if the number is 0
;; Uses: NFS_NUMBER, NFS_DIGIT
;; Keeps: X
NFS_READ_DECIMAL:
    lda #0
    sta NFS_NUMBER
NFS_READ_DECIMAL_LOOP:
    lda (NFS_CALL_XY),y
    cmp #'.'
    beq NFS_READ_DECIMAL_DONE
    bcc NFS_READ_DECIMAL_END
    and #$0F
    sta NFS_DIGIT
    asl NFS_NUMBER                  ; times two
    lda NFS_NUMBER
    asl a
    asl a                           ; times eight
    adc NFS_NUMBER                  ; times ten
    adc NFS_DIGIT
    sta NFS_NUMBER
    iny
    bne NFS_READ_DECIMAL_LOOP           ; always
NFS_READ_DECIMAL_END:
    clc
NFS_READ_DECIMAL_DONE:
    lda NFS_NUMBER
    rts

;; Converts a file handle in A to the file server's handle, as <HANDLE_TO_MASK> does.
;; In: A = the handle
;; Out: Y = the file server's handle
;; Keeps: A, X
HANDLE_IN_A_TO_MASK:
    tay
;; Converts a file handle, &20-&27, to the file server's handle, the byte with bit (handle - &20) set.
;; In: Y = the handle
;; Out: Y = the file server's handle, or &FF for a handle out of range
;; Keeps: A, X
HANDLE_TO_MASK:
    clc
;; Converts a file handle as <HANDLE_TO_MASK> does when carry is clear; with carry set, a handle of zero stays zero.
;; In: Y = the handle, carry = set to keep zero
;; Out: Y = the file server's handle
;; Keeps: A, X
HANDLE_TO_MASK_KEEP_ZERO:
    pha
    txa
    pha
    tya
    bcc HANDLE_TO_MASK_CONVERT
    beq HANDLE_TO_MASK_DONE
HANDLE_TO_MASK_CONVERT:
    sec
    sbc #$1F
    tax
    lda #1
HANDLE_TO_MASK_SHIFT:
    asl a
    dex
    bne HANDLE_TO_MASK_SHIFT
    ror a
    tay
    bne HANDLE_TO_MASK_DONE
    dey                             ; out of range: &FF
HANDLE_TO_MASK_DONE:
    pla
    tax
    pla
    rts

;; Converts the file server's handle, a byte with one bit set, to a file handle, &20-&27.
;; In: A = the file server's handle
;; Out: A, X = the file handle
MASK_TO_HANDLE:
    ldx #$1F
MASK_TO_HANDLE_LOOP:
    inx
    lsr a
    bne MASK_TO_HANDLE_LOOP
    txa
    rts

;; Compares NFS_FILE_START with NFS_FILE_END, all four bytes.
;;
;; It compares bytes 3, 2, 1 and 0, from the top, and stops at the first that differs.
;; Out: zero = set if they are equal
;; Uses: A, X
NFS_COMPARE_ADDRESSES:
    ldx #4
NFS_COMPARE_ADDRESSES_LOOP:
    lda NFS_FILE_START-1,x
    eor NFS_FILE_END-1,x
    bne NFS_COMPARE_ADDRESSES_DONE
    dex
    bne NFS_COMPARE_ADDRESSES_LOOP
NFS_COMPARE_ADDRESSES_DONE:
    rts

;; FSCV 7: gives the range of file handles the NFS uses, &20-&27.
;; Out: X = the lowest, Y = the highest
NFS_FSC_HANDLES:
    ldx #$20
    ldy #$27
    rts

;; Sets the bits of NFS_EOF_FLAGS that A has set.
;; In: A = the file server's handles
;; Out: A = NFS_EOF_FLAGS
SET_EOF_FLAGS:
    ora NFS_EOF_FLAGS
    bne STORE_EOF_FLAGS
;; Clears the bits of NFS_EOF_FLAGS that A has set.
;; In: A = the file server's handles
;; Out: A = NFS_EOF_FLAGS
CLEAR_EOF_FLAGS:
    eor #$FF
    and NFS_EOF_FLAGS
STORE_EOF_FLAGS:
    sta NFS_EOF_FLAGS
    rts

;; Reads the file name an OSFILE control block points to into NFS_FILE_NAME, through GSREAD.
;; In: NFS_CALL_XY = the control block
;; Out: NFS_NAME_POINTER = NFS_FILE_NAME, X = the name's length
;; Uses: A, Y, TEXT_POINTER
NFS_READ_FILE_NAME:
    ldy #1
NFS_READ_FILE_NAME_POINTER:
    lda (NFS_CALL_XY),y
    sta a:TEXT_POINTER,y
    dey
    bpl NFS_READ_FILE_NAME_POINTER
;; Reads the file name at TEXT_POINTER into NFS_FILE_NAME, as <NFS_READ_FILE_NAME> does.
;; In: TEXT_POINTER = the name
;; Inherit: <NFS_READ_FILE_NAME> Out
;; Uses: A, Y
NFS_READ_FILE_NAME_TEXT:
    ldy #0
;; Reads the file name at (TEXT_POINTER),Y into NFS_FILE_NAME, as <NFS_READ_FILE_NAME> does.
;; In: Y = the name's offset
;; Inherit: <NFS_READ_FILE_NAME> Out
;; Uses: A, Y
NFS_READ_FILE_NAME_AT:
    ldx #$FF
    clc
    jsr GSINIT
    beq NFS_READ_FILE_NAME_END
NFS_READ_FILE_NAME_LOOP:
    jsr GSREAD
    bcs NFS_READ_FILE_NAME_END
    inx
    sta NFS_FILE_NAME,x
    bcc NFS_READ_FILE_NAME_LOOP         ; always
NFS_READ_FILE_NAME_END:
    inx
    lda #$0D
    sta NFS_FILE_NAME,x
    lda #<NFS_FILE_NAME
    sta NFS_NAME_POINTER
    lda #>NFS_FILE_NAME
    sta NFS_NAME_POINTER+1
    rts

; ---------------------------------------------------------------------------------------------------------------------
; OSFILE
; ---------------------------------------------------------------------------------------------------------------------

;; The NFS's OSFILE, through FILEV: loads and saves files here, and passes the other calls to <NFS_OSFILE_INFO>.
;;
;; A negative call other than &FF does nothing.
;; In: A = the call, X/Y = the control block
;; Out: X/Y = as on entry, A = the call for a load or save; for the other calls the object's type (1 for a file),
;;   or 0 when it is not found
;; Errors: the file server's, those of <TRANSMIT>, "No reply" (&A5) and "Escape" (&11)
NFS_OSFILE:
    jsr SAVE_CALL_REGISTERS
    jsr NFS_READ_FILE_NAME
    lda NFS_CALL_A
    bpl NFS_OSFILE_OTHER
    cmp #$FF
    beq NFS_OSFILE_LOAD
    jmp NFS_CALL_RETURN                       ; return

NFS_OSFILE_LOAD:
    jsr COPY_NAME_TO_REQUEST                       ; copy the name to NFS_REQUEST_DATA; X = its length
    ldy #NFS_FS_LOAD
;; Loads a file: sends the request, receives the data on port &92, and fills in the control block.
;;
;; The data goes to the control block's load address, or the file's own if the execution address's low byte is not
;; zero. ESCAPE may interrupt. The file server's reply gives the load and execution addresses and the length, which
;; are copied to the control block, then the access and date.
;; In: X = the length of the request's data, Y = the function, NFS_CALL_XY = the control block
;; Uses: A, X, Y, NFS_FILE_START, NFS_FILE_END, NFS_FS_BLOCK
;; Errors: the file server's, those of <TRANSMIT>, "No reply" (&A5) and "Escape" (&11)
NFS_LOAD_FILE:
    lda #NFS_PORT_DATA              ; bit 7 set: ESCAPE may interrupt
    sta NFS_ESCAPE_ENABLE
    sta NFS_REQUEST_URD             ; the port for the data
    jsr FS_COMMAND_WITH_PORT
    ldy #NFS_OSFILE_EXEC
    lda (NFS_CALL_XY),y
    bne NFS_LOAD_FILE_OWN_ADDRESS
    jsr NFS_GET_LOAD_ADDRESS            ; the control block's address
    jsr COPY_FILE_INFO_TO_BLOCK                       ; then the file's information into the block
    bcc NFS_LOAD_FILE_RANGE             ; always
NFS_LOAD_FILE_OWN_ADDRESS:
    jsr COPY_FILE_INFO_TO_BLOCK                       ; the file's information into the block
    jsr NFS_GET_LOAD_ADDRESS            ; then its load address
NFS_LOAD_FILE_RANGE:
    ldy #4
NFS_LOAD_FILE_RANGE_LOOP:
    lda NFS_FILE_START,x
    sta NFS_FS_BLOCK_END,x          ; where the first block starts
    adc NFS_LOAD_LENGTH,x           ; the fourth byte adds the access byte,
    sta NFS_FILE_END,x
    inx
    dey
    bne NFS_LOAD_FILE_RANGE_LOOP
    sec
    sbc NFS_LOAD_ACCESS             ; which this takes off again
    sta NFS_FILE_END+3
    jsr RECEIVE_DATA
    ldx #2
NFS_LOAD_FILE_ACCESS:
    lda NFS_LOAD_ACCESS,x           ; the access and date, where a save's last reply has them
    sta NFS_REPLY_DATA,x
    dex
    bpl NFS_LOAD_FILE_ACCESS
    bmi OSFILE_FINISH               ; always

;; Receives data from NFS_FILE_START to NFS_FILE_END, block by block, on port &92.
;;
;; Each block is received after the one before, until a reception ends at NFS_FILE_END.
;; In: NFS_FS_BLOCK_END = NFS_FILE_START
;; Uses: A, X, Y, NFS_FS_BLOCK
;; Errors: "No reply" (&A5)
RECEIVE_DATA:
    jsr NFS_COMPARE_ADDRESSES
    beq RECEIVE_DATA_DONE           ; nothing to receive
    lda #NFS_PORT_DATA
    sta NFS_FS_BLOCK_PORT
RECEIVE_DATA_BLOCK:
    ldx #3
RECEIVE_DATA_SET_UP:
    lda NFS_FS_BLOCK_END,x
    sta NFS_FS_BLOCK_START,x
    lda NFS_FILE_END,x
    sta NFS_FS_BLOCK_END,x
    dex
    bpl RECEIVE_DATA_SET_UP
    lda #$7F                        ; receive
    sta NFS_FS_BLOCK
    jsr AWAIT_RECEPTION
    ldy #3
RECEIVE_DATA_CHECK:
    lda a:NFS_FS_BLOCK_END,y
    eor a:NFS_FILE_END,y
    bne RECEIVE_DATA_BLOCK
    dey
    bpl RECEIVE_DATA_CHECK
RECEIVE_DATA_DONE:
    rts

NFS_OSFILE_OTHER:
    beq NFS_OSFILE_SAVE
    jmp NFS_OSFILE_INFO

;; OSFILE 0: saves a file, sending the data to the port the file server's reply names.
;;
;; The control block's start address is replaced by the length, as the request takes it.
;; Uses: A, X, Y
NFS_OSFILE_SAVE:
    ldx #4
    ldy #NFS_OSFILE_END
NFS_OSFILE_SAVE_LENGTH:
    lda (NFS_CALL_XY),y
    sta a:NFS_FILE_END - NFS_OSFILE_END,y
    jsr SUBTRACT_4_FROM_Y                       ; Y less 4, to the start address
    sbc (NFS_CALL_XY),y
    sta NFS_SAVE_LENGTH - NFS_OSFILE_START,y
    pha
    lda (NFS_CALL_XY),y
    sta a:NFS_FILE_START - NFS_OSFILE_START,y
    pla
    sta (NFS_CALL_XY),y
    jsr ADD_5_TO_Y
    dex
    bne NFS_OSFILE_SAVE_LENGTH
    ldy #NFS_OSFILE_EXEC + 3
NFS_OSFILE_SAVE_ADDRESSES:
    lda (NFS_CALL_XY),y
    sta NFS_SAVE_LOAD - NFS_OSFILE_BLOCK_LOAD,y
    dey
    bne NFS_OSFILE_SAVE_ADDRESSES
    lda #NFS_PORT_ACKNOWLEDGE       ; bit 7 set: ESCAPE may interrupt
    sta NFS_ESCAPE_ENABLE
    sta NFS_REQUEST_URD
    sta NFS_SAVE_PORT
    ldx #NFS_SAVE_NAME - NFS_REQUEST_DATA
    jsr COPY_NAME_TO_REQUEST_AT_X                       ; the name after the addresses
    ldy #NFS_FS_SAVE
    jsr FS_COMMAND_WITH_PORT
    lda NFS_REPLY_DATA              ; the port for the data
    jsr SEND_DATA_BLOCKS                       ; send the data
;; Finishes a load or save: waits for the file server's last reply, shows the file's information if *OPT 1 asks,
;; and puts the attributes and date in the control block.
;;
;; The information is the name, padded to twelve characters, and the load and execution addresses and length in
;; hexadecimal. When the first reply's command code is not zero, the name printed is the reply's
;; (<PRINT_REPLY_LIST_AT>).
OSFILE_FINISH:
    lda NFS_REPLY_COMMAND
    pha
    jsr FS_AWAIT_REPLY
    pla
    ldy NFS_MESSAGES
    beq OSFILE_FINISH_ATTRIBUTES
    ldy #0
    tax
    beq OSFILE_FINISH_NAME
    jsr PRINT_REPLY_LIST_AT
    bmi OSFILE_FINISH_ADDRESSES     ; always
OSFILE_FINISH_NAME:
    lda (NFS_NAME_POINTER),y
    cmp #'!'
    bcc OSFILE_FINISH_PAD
    jsr OSASCI
    iny
    bne OSFILE_FINISH_NAME
OSFILE_FINISH_PAD:
    jsr PRINT_SPACE                       ; a space
    iny
    cpy #12
    bcc OSFILE_FINISH_PAD
OSFILE_FINISH_ADDRESSES:
    ldy #NFS_OSFILE_BLOCK_LOAD + 3
    jsr PRINT_BLOCK_HEX
    ldy #NFS_OSFILE_EXEC + 3
    jsr PRINT_BLOCK_HEX
    ldy #NFS_OSFILE_START + 2
    ldx #3
    jsr PRINT_BLOCK_HEX_X
    jsr OSNEWL
OSFILE_FINISH_ATTRIBUTES:
    stx NFS_REPLY_DATA+3            ; zero, the attributes' top byte
    ldy #NFS_OSFILE_END
    lda NFS_REPLY_DATA
    jsr ACCESS_TO_ATTRIBUTES
OSFILE_FINISH_ATTRIBUTES_LOOP:
    sta (NFS_CALL_XY),y
    iny
    lda NFS_REPLY_DATA - NFS_OSFILE_END,y
    cpy #NFS_OSFILE_END + 4
    bne OSFILE_FINISH_ATTRIBUTES_LOOP
    jmp NFS_CALL_RETURN                       ; return

;; Copies the load address of an OSFILE control block to NFS_FILE_START.
;; In: NFS_CALL_XY = the control block
;; Out: Y = 6
;; Uses: A
NFS_GET_LOAD_ADDRESS:
    ldy #NFS_OSFILE_BLOCK_LOAD + 3
NFS_GET_LOAD_ADDRESS_LOOP:
    lda (NFS_CALL_XY),y
    sta a:NFS_FILE_START - NFS_OSFILE_BLOCK_LOAD,y
    dey
    cpy #NFS_OSFILE_BLOCK_LOAD
    bcs NFS_GET_LOAD_ADDRESS_LOOP
;; Adds 5 to Y, the step from one address of an OSFILE control block to the next but one byte.
;; In: Y = the offset
;; Out: Y = the offset plus 5
ADD_5_TO_Y:
    iny
;; Adds 4 to Y, the step from one address of an OSFILE control block to the next.
;; In: Y = the offset
;; Out: Y = the offset plus 4
ADD_4_TO_Y:
    iny
    iny
    iny
    iny
    rts
