; retrocore: style=strict ignore=unlinked-name:READ|CREATE|RENAME -- SOS's calls, not BASIC's statements
; SOSSTUF: BASIC's SOS calls. The parameter lists for the console, the console's events, and the one parameter list
; every file call shares, with SosCalls::Call and SosCalls::SetUp to make a call from it.
;
; A SOS call is a BRK followed by the call's number and the address of its parameter list; the list starts with its
; count of parameters. The lists are written as BASIC runs, so this part of BASIC must not be write-protected.

; ---------------------------------------------------------------------------------------------------------------------
; The parameter lists' layouts
; ---------------------------------------------------------------------------------------------------------------------

;; BASIC's SOS calls: the layouts of their parameter lists, the one list the file calls share, and the routines that
;; make a file call from it.
.scope SosCalls

; The parameter counts of the calls BASIC makes.

;; CREATE's parameter count.
CREATE_COUNT = 3

;; DESTROY's parameter count.
DESTROY_COUNT = 1

;; RENAME's parameter count.
RENAME_COUNT = 2

;; GET_FILE_INFO's and SET_FILE_INFO's parameter count.
FILE_INFO_COUNT = 3

;; OPEN's parameter count.
OPEN_COUNT = 4

;; NEWLINE's parameter count.
NEWLINE_COUNT = 3

;; READ's parameter count.
READ_COUNT = 4

;; WRITE's parameter count.
WRITE_COUNT = 3

;; CLOSE's parameter count.
CLOSE_COUNT = 1

;; FLUSH's parameter count.
FLUSH_COUNT = 1

;; SET_MARK's and SET_EOF's parameter count.
SET_MARK_COUNT = 3

;; GET_MARK's parameter count.
GET_MARK_COUNT = 2

;; RELEASE_SEG's parameter count.
RELEASE_SEG_COUNT = 1

;; FIND_SEG's parameter count.
FIND_SEG_COUNT = 6

;; The joystick call's parameter count.
JOYSTICK_COUNT = 2

;; D_CONTROL's and D_STATUS's parameter count.
DEVICE_COUNT = 3

;; GET_DEV_NUM's parameter count.
DEVICE_NUMBER_COUNT = 2

;; SET_PREFIX's parameter count.
SET_PREFIX_COUNT = 1

;; GET_PREFIX's parameter count.
GET_PREFIX_COUNT = 2

;; The joystick call's number, which BASIC's table of file calls gives as a number.
SOS_JOYSTICK = $64

;; OPEN's parameters.
.struct OpenList
    COUNT .byte                             ;; <SosCalls::OPEN_COUNT>
    PATHNAME .word                          ;; the pathname's address, its length first
    REFERENCE .byte                         ;; the reference number OPEN returns
    OPTIONS .word                           ;; the option list's address
    OPTIONS_LENGTH .byte                    ;; the option list's length
.endstruct

;; WRITE's parameters.
.struct WriteList
    COUNT .byte                             ;; <SosCalls::WRITE_COUNT>
    REFERENCE .byte                         ;; the file's reference number
    BUFFER .word                            ;; the bytes' address
    LENGTH .word                            ;; the count of bytes to write
.endstruct

;; READ's parameters; WRITE takes the first four too.
.struct ReadList
    COUNT .byte                             ;; <SosCalls::READ_COUNT>
    REFERENCE .byte                         ;; the file's reference number
    BUFFER .word                            ;; where the bytes go
    REQUEST .word                           ;; the count of bytes to read
    TRANSFERRED .word                       ;; the count READ really read
.endstruct

;; NEWLINE's parameters.
.struct NewlineList
    COUNT .byte                             ;; <SosCalls::NEWLINE_COUNT>
    REFERENCE .byte                         ;; the file's reference number
    ENABLED .byte                           ;; bit 7 set: reads end at the character after it
    CHARACTER .byte                         ;; the character that ends a read
.endstruct

;; FLUSH's parameters.
.struct FlushList
    COUNT .byte                             ;; <SosCalls::FLUSH_COUNT>
    REFERENCE .byte                         ;; the file's reference number, or 0 for every file
.endstruct

;; D_CONTROL's and D_STATUS's parameters.
.struct DeviceList
    COUNT .byte                             ;; <SosCalls::DEVICE_COUNT>
    DEVICE .byte                            ;; the device's number
    CODE .byte                              ;; the control or status code
    LIST .word                              ;; the address of the control or status list
.endstruct

;; GET_DEV_NUM's parameters.
.struct DeviceNumberList
    COUNT .byte                             ;; <SosCalls::DEVICE_NUMBER_COUNT>
    PATHNAME .word                          ;; the device name's address, its length first
    DEVICE .byte                            ;; the device's number, which the call returns
.endstruct

;; The control list that arms one of the console's events, the any-key event.
.struct EventList
    PRIORITY .byte                          ;; the event's priority; 0 turns the event off
    ID .byte                                ;; the event's ID
    HANDLER .word                           ;; the handler's address
    BANK .byte                              ;; the handler's bank
.endstruct

;; The control list that arms the console's attention event, with its key.
.struct AttentionList
    PRIORITY .byte                          ;; the event's priority; 0 turns the event off
    ID .byte                                ;; the event's ID
    HANDLER .word                           ;; the handler's address
    BANK .byte                              ;; the handler's bank
    KEY .byte                               ;; the attention key
.endstruct

;; GET_FILE_INFO's and SET_FILE_INFO's parameters.
.struct FileInfoList
    COUNT .byte                             ;; <SosCalls::FILE_INFO_COUNT>
    PATHNAME .word                          ;; the pathname's address, its length first
    INFORMATION .word                       ;; the information list's address
    LENGTH .byte                            ;; the information list's length
.endstruct

;; CREATE's parameters.
.struct CreateList
    COUNT .byte                             ;; <SosCalls::CREATE_COUNT>
    PATHNAME .word                          ;; the pathname's address, its length first
    OPTIONS .word                           ;; the option list's address
    OPTIONS_LENGTH .byte                    ;; the option list's length
.endstruct

;; RENAME's parameters.
.struct RenameList
    COUNT .byte                             ;; <SosCalls::RENAME_COUNT>
    PATHNAME .word                          ;; the old pathname's address
    NEW_PATHNAME .word                      ;; the new pathname's address
.endstruct

;; SET_MARK's and SET_EOF's parameters.
.struct MarkList
    COUNT .byte                             ;; <SosCalls::SET_MARK_COUNT>
    REFERENCE .byte                         ;; the file's reference number
    BASE .byte                              ;; what the displacement counts from: the start, the mark or the end
    DISPLACEMENT .dword                     ;; the displacement
.endstruct

;; GET_MARK's parameters.
.struct MarkResultList
    COUNT .byte                             ;; <SosCalls::GET_MARK_COUNT>
    REFERENCE .byte                         ;; the file's reference number
    MARK .dword                             ;; the mark the call returns
.endstruct

;; FIND_SEG's parameters.
.struct FindSegmentList
    COUNT .byte                             ;; <SosCalls::FIND_SEG_COUNT>
    SEARCH_MODE .byte                       ;; the search mode
    SEGMENT_ID .byte                        ;; the segment's ID
    PAGE_COUNT .word                        ;; the count of pages wanted
    BASE .word                              ;; the segment's base bank and page, which the call returns
    LIMIT .word                             ;; the segment's limit bank and page, which the call returns
    SEGMENT .byte                           ;; the segment's number, which the call returns
.endstruct

;; RELEASE_SEG's parameters.
.struct ReleaseSegmentList
    COUNT .byte                             ;; <SosCalls::RELEASE_SEG_COUNT>
    SEGMENT .byte                           ;; the segment's number
.endstruct

;; The joystick call's parameters.
.struct JoystickList
    COUNT .byte                             ;; <SosCalls::JOYSTICK_COUNT>
    MODE .byte                              ;; the mode, which picks the port; the results follow it
.endstruct

;; SET_PREFIX's parameters, and GET_PREFIX's with the length.
.struct PrefixList
    COUNT .byte                             ;; <SosCalls::SET_PREFIX_COUNT> or <SosCalls::GET_PREFIX_COUNT>
    PATHNAME .word                          ;; the prefix's address, its length first
    LENGTH .byte                            ;; GET_PREFIX's buffer length
.endstruct

;; CREATE's option list.
.struct FileOptions
    FILE_TYPE .byte                         ;; the file type
    AUX_TYPE .word                          ;; the auxiliary type
    STORAGE_TYPE .byte                      ;; the storage type
    EOF .dword                              ;; the end of file
.endstruct

;; GET_FILE_INFO's and SET_FILE_INFO's information list, as far as BASIC keeps it.
.struct FileInformation
    ACCESS .byte                            ;; the access bits
    FILE_TYPE .byte                         ;; the file type
    AUX_TYPE .word                          ;; the auxiliary type
    STORAGE_TYPE .byte                      ;; the storage type
    EOF .dword                              ;; the end of file
    BLOCKS .word                            ;; the count of blocks the file takes
    DATE .word                              ;; the first two bytes of the date
.endstruct

.endscope

; ---------------------------------------------------------------------------------------------------------------------
; The console
; ---------------------------------------------------------------------------------------------------------------------

; The console's parameter lists.
.scope Console continued

;; The console event's ID BASIC gives both events.
EVENT_ID = 1

;; The priority BASIC gives the events it arms.
EVENT_PRIORITY = 1

;; The attention key, CONTROL-C.
CONTROL_C = 3

;; D_CONTROL's code that resets the console.
CONTROL_RESET = 0

;; D_CONTROL's code that empties the type-ahead buffer.
CONTROL_FLUSH_TYPE_AHEAD = 5

;; D_CONTROL's code that arms the attention event.
CONTROL_ATTENTION = 6

;; D_CONTROL's code that arms the any-key event.
CONTROL_ANY_KEY = 8

;; D_CONTROL's code that sets the echo flags.
CONTROL_ECHO = 11

;; D_STATUS's code that reads the cursor's position.
STATUS_CURSOR = 16

;; NEWLINE's flag that turns new-line mode on.
NEWLINE_ON = $FF

;; The echo flag that echoes keys to the screen.
ECHO_ON = $80

;; The bit of <KEYSTROK> the any-key event sets.
KEY_SEEN = $80

;; The bit of <KEYSTROK> the attention event sets, for CONTROL-C.
CONTROL_C_SEEN = $40

;; OPEN's parameter list for .CONSOLE: the name <Console::Name>, the reference number back in <Console::Reference>,
;; and no option list.
;; See: <Console::Initialize>
;; Also: OPNCNST (BB13)
OpenParameters:
    .byte SosCalls::OPEN_COUNT
    .word Name

;; The console's reference number, from OPEN; <Console::Initialize> copies it into the console's other lists.
;; Also: CONSRFN (BB13)
Reference:
    .byte 0
    .word 0                                 ; the option list: none
    .byte 0                                 ; the option list's length

;; The console's name, `.CONSOLE`, with its length first.
;; Also: CONSFN (BB13)
Name:
    .byte .strlen(".CONSOLE")
    .byte ".CONSOLE"

;; WRITE's parameter list for text to the console, first the sign-on: the console's reference number, the text at
;; <Console::SignOn> and its length.
;;
;; Text output writes strings through it too, putting a file's reference number in for the call.
;; See: <Console::Initialize>
;; Also: SINIT (BB13)
WriteParameters:
    .byte SosCalls::WRITE_COUNT
    .byte 0                                 ; the reference number

;; The text's address, in <Console::WriteParameters>.
;; Also: SPRNTPL (BB13)
WriteAddress:
    .word SignOn

;; The text's length, in <Console::WriteParameters>.
;; Also: OUTSTRL (BB13)
WriteLength:
    .word SIGN_ON_LENGTH

;; NEWLINE's parameter list: the console's reads end at a carriage return.
;; Also: ISNLTB (BB13)
NewlineParameters:
    .byte SosCalls::NEWLINE_COUNT
    .byte 0                                 ; the reference number
    .byte NEWLINE_ON, RETURN

;; READ's parameter list for one key, into <KEYSAVE>: the console's or, while `EXEC` runs, the `EXEC` file's reference
;; number goes in <Console::KeyReference>.
;;
;; Its request, one byte, is also <Console::FlushAllParameters>.
;; See: <Console::ReadKey>
;; Also: RDCTC (BB13)
KeyParameters:
    .byte SosCalls::READ_COUNT

;; The reference number <Console::KeyParameters> reads from.
;; Also: GETREF (BB13)
KeyReference:
    .byte 0
    .word KEYSAVE

;; FLUSH's parameter list: one parameter, reference number 0, which flushes every open file. Its two bytes are also
;; the request of <Console::KeyParameters>, one byte. Nothing sets it, so <ReadyForCommand>'s FLUSH is always of
;; every file.
;; Also: RFLUSH (BB13)
FlushAllParameters:
    .byte SosCalls::FLUSH_COUNT, 0

;; READ's count of bytes read, in <Console::KeyParameters>, which BASIC ignores.
;; Also: RNDGOT (BB13)
KeyTransferred:
    .word 0

;; WRITE's parameter list for one character, <Console::Character>, to the console.
;;
;; Its count is set when it is used; READ's count of bytes read follows, for a READ through it.
;; Also: SCHRTB (BB13)
CharacterParameters:
    .byte 0                                 ; the parameter count, set when it is used
    .byte 0                                 ; the reference number
    .word Character
    .word 1                                 ; one byte
    .word 0                                 ; the bytes read, for a READ through it

;; The character <Console::CharacterParameters> writes.
;; Also: OUTCHAR (BB13)
Character:
    .byte 0

;; READ's parameter list for a line from the console into <BUF>, up to <INALLWD> characters.
;; Also: SLINTB (BB13)
LineParameters:
    .byte SosCalls::READ_COUNT
    .byte 0                                 ; the reference number
    .word BUF
    .word INALLWD

;; The count of characters <Console::LineParameters>'s READ returned.
;; Also: SNOCHRS (BB13)
LineLength:
    .word 0

;; D_CONTROL's parameter list for <Console::CONTROL_RESET>, which resets the console. The list it points to is its
;; own last word, as the reset reads none.
;; Also: DINIT (BB13)
ResetParameters:
    .byte SosCalls::DEVICE_COUNT

;; The console's device number, in <Console::ResetParameters>; <Console::Initialize> copies it from
;; <Console::Device>.
;; Also: INDN (BB13)
ResetDevice:
    .byte 0
    .byte CONTROL_RESET
    .word *

;; GET_DEV_NUM's parameter list for .CONSOLE, which returns its device number in <Console::Device>.
;; Also: DGCN (BB13)
DeviceNumberParameters:
    .byte SosCalls::DEVICE_NUMBER_COUNT
    .word Name

;; The console's device number, from GET_DEV_NUM.
;; Also: OTDN (BB13)
Device:
    .byte 0

;; D_CONTROL's parameter list for <Console::CONTROL_ANY_KEY>, the any-key event, from <Console::AnyKeyEvent>.
;; Also: DKBD (BB13)
AnyKeyParameters:
    .byte SosCalls::DEVICE_COUNT

;; The console's device number, in <Console::AnyKeyParameters>.
;; Also: INDN3 (BB13)
AnyKeyDevice:
    .byte 0
    .byte CONTROL_ANY_KEY
    .word AnyKeyEvent

;; The any-key event: its priority (0 turns it off), its ID, the handler <Console::AnyKeyHandler> and its bank,
;; <Console::AnyKeyBank>.
;; Also: KBDKEY (BB13)
AnyKeyEvent:
    .byte EVENT_PRIORITY
    .byte EVENT_ID
    .word AnyKeyHandler

;; The bank of <Console::AnyKeyHandler>, set to BASIC's own bank at start.
;; Also: KBDBNK (BB13)
AnyKeyBank:
    .byte 0

;; D_CONTROL's parameter list for <Console::CONTROL_ATTENTION>, the attention event, from
;; <Console::AttentionEvent>.
;; Also: DCNTR (BB13)
AttentionParameters:
    .byte SosCalls::DEVICE_COUNT

;; The console's device number, in <Console::AttentionParameters>.
;; Also: INDN2 (BB13)
AttentionDevice:
    .byte 0
    .byte CONTROL_ATTENTION
    .word AttentionEvent

;; The attention event: its priority (0 turns it off), its ID, the handler <Console::AttentionHandler>, its bank
;; <Console::AttentionBank>, and the attention key, CONTROL-C.
;; See: <Console::AttentionOff>, <Console::AttentionOn>
;; Also: DCCPRI (BB13)
AttentionEvent:
    .byte EVENT_PRIORITY
    .byte EVENT_ID
    .word AttentionHandler

;; The bank of <Console::AttentionHandler>, set to BASIC's own bank at start.
;; Also: DCNTBNK (BB13)
AttentionBank:
    .byte 0
    .byte CONTROL_C                         ; the attention key

;; D_CONTROL's parameter list for <Console::CONTROL_FLUSH_TYPE_AHEAD>, which empties the type-ahead buffer.
;; Also: DFLUSH (BB13)
FlushTypeAheadParameters:
    .byte SosCalls::DEVICE_COUNT

;; The console's device number, in <Console::FlushTypeAheadParameters>.
;; Also: INDN6 (BB13)
FlushTypeAheadDevice:
    .byte 0
    .byte CONTROL_FLUSH_TYPE_AHEAD
    .word $3000                             ; a list the control never reads

;; D_CONTROL's parameter list for <Console::CONTROL_ECHO>, which sets the echo flags from <Console::EchoFlags>.
;; Also: DECHO (BB13)
EchoParameters:
    .byte SosCalls::DEVICE_COUNT

;; The console's device number, in <Console::EchoParameters>.
;; Also: INDN4 (BB13)
EchoDevice:
    .byte 0
    .byte CONTROL_ECHO
    .word EchoFlags

;; The echo flags for <Console::EchoParameters>: <Console::ECHO_ON> echoes keys to the screen, 0 does not.
;; Also: ECHOFLG (BB13)
EchoFlags:
    .byte 0

;; D_STATUS's parameter list for <Console::STATUS_CURSOR>, the cursor's position, into <Console::CursorColumn> and
;; <Console::CursorLine>.
;; Also: REDCUR (BB13)
CursorParameters:
    .byte SosCalls::DEVICE_COUNT

;; The console's device number, in <Console::CursorParameters>.
;; Also: INDN5 (BB13)
CursorDevice:
    .byte 0
    .byte STATUS_CURSOR
    .word CursorColumn

;; The cursor's column, from <Console::CursorParameters>.
;; Also: CURX (BB13)
CursorColumn:
    .byte 0

;; The cursor's line, from <Console::CursorParameters>.
;; Also: CURY (BB13)
CursorLine:
    .byte 0

.assert Reference = OpenParameters + SosCalls::OpenList::REFERENCE, "Reference is OPEN's reference number."
.assert WriteAddress = WriteParameters + SosCalls::WriteList::BUFFER, "WriteAddress is WRITE's buffer."
.assert WriteLength = WriteParameters + SosCalls::WriteList::LENGTH, "WriteLength is WRITE's length."
.assert KeyReference = KeyParameters + SosCalls::ReadList::REFERENCE, "KeyReference is READ's reference number."
.assert FlushAllParameters = KeyParameters + SosCalls::ReadList::REQUEST, "FLUSH shares the key READ's request."
.assert KeyTransferred = KeyParameters + SosCalls::ReadList::TRANSFERRED, "KeyTransferred is READ's count read."
.assert Character = CharacterParameters + .sizeof(SosCalls::ReadList), "Character follows CharacterParameters."
.assert LineLength = LineParameters + SosCalls::ReadList::TRANSFERRED, "LineLength is READ's count read."
.assert ResetDevice = ResetParameters + SosCalls::DeviceList::DEVICE, "ResetDevice is D_CONTROL's device."
.assert Device = DeviceNumberParameters + SosCalls::DeviceNumberList::DEVICE, "Device is GET_DEV_NUM's device."
.assert AnyKeyDevice = AnyKeyParameters + SosCalls::DeviceList::DEVICE, "AnyKeyDevice is D_CONTROL's device."
.assert AnyKeyBank = AnyKeyEvent + SosCalls::EventList::BANK, "AnyKeyBank is the event's bank."
.assert AttentionDevice = AttentionParameters + SosCalls::DeviceList::DEVICE, "AttentionDevice is D_CONTROL's device."
.assert AttentionBank = AttentionEvent + SosCalls::AttentionList::BANK, "AttentionBank is the event's bank."
.assert FlushTypeAheadDevice = FlushTypeAheadParameters + SosCalls::DeviceList::DEVICE, "The list's device."
.assert EchoDevice = EchoParameters + SosCalls::DeviceList::DEVICE, "EchoDevice is D_CONTROL's device."
.assert CursorDevice = CursorParameters + SosCalls::DeviceList::DEVICE, "CursorDevice is D_STATUS's device."

; ---------------------------------------------------------------------------------------------------------------------
; Keys and CONTROL-C
; ---------------------------------------------------------------------------------------------------------------------

;; Turns the attention event off, so CONTROL-C reads as a key, then arms it with <Console::AttentionOn>'s call.
;; See: <Console::AttentionOn>, <Console::AttentionEvent>
;; Also: CTCOFF (BB13)
.proc AttentionOff
    lda #0
    sta AttentionEvent+SosCalls::AttentionList::PRIORITY
    ; Falls into Console::AttentionOn.
.endproc

;; Arms the attention event from <Console::AttentionEvent>, then gives it <Console::EVENT_PRIORITY> again for next
;; time.
;; Also: CTCON (BB13)
.proc AttentionOn
    brk
    .byte SDCNT
    .word AttentionParameters
    lda #EVENT_PRIORITY
    sta AttentionEvent+SosCalls::AttentionList::PRIORITY
    rts
.endproc

;; The any-key event's handler: sets <Console::KEY_SEEN> in <KEYSTROK> and reads the key.
;;
;; The statement fetcher sees the bit before the next statement.
;; See: <Console::AttentionHandler>, <Console::ReadKey>
;; Also: KBDEVNT (BB13)
.proc AnyKeyHandler
    lda #KEY_SEEN
    .byte $2C                               ; BIT abs, which skips AttentionHandler's LDA
    ; Falls into Console::AttentionHandler.
.endproc

;; The attention event's handler: sets <Console::CONTROL_C_SEEN> in <KEYSTROK> for CONTROL-C and reads the key from
;; the console.
;; See: <Console::AnyKeyHandler>, <Console::ReadKey>
;; Also: CTCEVNT (BB13)
.proc AttentionHandler
    lda #CONTROL_C_SEEN
    ora KEYSTROK
    sta KEYSTROK
    lda Reference
    sta KeyReference
    ; Falls into Console::ReadKey.
.endproc

;; Reads one key into <KEYSAVE> with echo and CONTROL-C off, from <Console::KeyReference>'s file.
;;
;; When the read fails while `EXEC` is reading, the `EXEC` file is closed and the key is read from the console instead;
;; when it fails in `GET#`, the error goes to the end-of-file handling in <DSKEOF>.
;; Out: zero = set for a key read
;; Also: DOAGET (BB13)
.proc ReadKey
    jsr EchoOff
    jsr AttentionOff
    brk
    .byte SRED
    .word KeyParameters
    pha                                     ; the error code
    jsr EchoOn
    pla
    beq SosCalls::Call::Done
    ldx KeyReference                        ; EXEC's file, or GET#'s?
    cpx INFLNO
    beq ExecFailed
    jmp DSKEOF                              ; GET#'s: ON EOF# may take it

;; Closes the `EXEC` file, and reads the key from the console.
ExecFailed:
    jsr EXCCLS
    ldx LineParameters+SosCalls::ReadList::REFERENCE
    stx KeyReference
    bne ReadKey                             ; always
.endproc

;; Turns the console's echo on, then arms the attention event again.
;; See: <Console::EchoOff>
;; Also: ECHOON (BB13)
.proc EchoOn
    lda #ECHO_ON
    .byte $2C                               ; BIT abs, which skips EchoOff's LDA
    ; Falls into Console::EchoOff.
.endproc

;; Turns the console's echo off, then arms the attention event again.
;; See: <Console::EchoOn>
;; Also: ECHOFF (BB13)
.proc EchoOff
    lda #0
    sta EchoFlags
    brk
    .byte SDCNT
    .word EchoParameters
    jmp AttentionOn
.endproc

.endscope

; ---------------------------------------------------------------------------------------------------------------------
; File calls
; ---------------------------------------------------------------------------------------------------------------------

; The file calls' shared parameter list, and making a call from it.
.scope SosCalls continued

;; Makes the SOS call <SosCalls::SetUp> chose, with the parameters in <SosCalls::Parameters>.
;; Out: A = the error code, zero = set for none
;; Entry: Done = returns, for routines that branch to return
;; See: <SosCalls::SetUp>, <SosCalls::MakeFileCall>
;; Also: GOSOS (BB13)
.proc Call
    brk

;; The call number the BRK makes, which <SosCalls::SetUp> sets.
;; Also: SCN (BB13)
Number:
    .byte 0
    .word Parameters

;; Returns.
;; Also: SOSRTS (BB13)
Done:
    rts
.endproc

;; The parameter list every file call shares: the count, which <SosCalls::SetUp> sets, then the parameters.
;;
;; Each call's parameters have their own names; those at the same offset share its byte. The calls' layouts are
;; <SosCalls::CreateList>, <SosCalls::OpenList>, <SosCalls::ReadList> and the others in this scope.
;; See: <SosCalls::SetUp>, <SosCalls::ParameterCounts>
;; Also: SOSTBL (BB13)
Parameters:
    .byte 0

;; The first parameter: a pathname's address, or a reference number.
;; Also: PTHPTR (BB13)
Pathname:
    .word 0

;; The file's reference number, for `READ`, `WRITE` and the mark calls.
;; Also: RWRFNM (BB13)
Reference = Parameters + ReadList::REFERENCE

;; NEWLINE's on-or-off flag.
;; Also: NWLNB (BB13)
NewlineEnabled = Parameters + NewlineList::ENABLED

;; READ's and WRITE's buffer address.
;; Also: SBFPTR (BB13)
Buffer = Parameters + ReadList::BUFFER

;; SET_MARK's base: from the start, the mark or the end.
;; Also: BASE (BB13)
MarkBase = Parameters + MarkList::BASE

;; The mark or end of file a call returns.
;; Also: OUTMRK (BB13)
Mark = Parameters + MarkResultList::MARK

;; FIND_SEG's search mode.
;; Also: ISRCHMD (BB13)
SearchMode = Parameters + FindSegmentList::SEARCH_MODE

;; FIND_SEG's segment ID.
;; Also: ISEGID (BB13)
SegmentId = Parameters + FindSegmentList::SEGMENT_ID

;; RELEASE_SEG's segment number.
;; Also: SEGNUM (BB13)
ReleasedSegment = Parameters + ReleaseSegmentList::SEGMENT

;; The joystick call's mode.
;; Also: JMODE (BB13)
JoystickMode = Parameters + JoystickList::MODE

;; The second parameter: CREATE's option list's address, or another call's.
;; Also: CRTLST (BB13)
CreateOptions:
    .word 0

;; RENAME's new pathname.
;; Also: NWPTHNM (BB13)
NewPathname = Parameters + RenameList::NEW_PATHNAME

;; The file information list's address.
;; Also: FLSTPTR (BB13)
InformationAddress = Parameters + FileInfoList::INFORMATION

;; The reference number OPEN returns.
;; Also: REFOUT (BB13)
OpenedReference = Parameters + OpenList::REFERENCE

;; OPEN's option list's address.
;; Also: OPNLST (BB13)
OpenOptions = Parameters + OpenList::OPTIONS

;; NEWLINE's character.
;; Also: NLCHR (BB13)
NewlineCharacter = Parameters + NewlineList::CHARACTER

;; The count `READ` or `WRITE` moves.
;; Also: INBYTES (BB13)
Request = Parameters + ReadList::REQUEST

;; SET_MARK's displacement.
;; Also: DSPLMNT (BB13)
Displacement = Parameters + MarkList::DISPLACEMENT

;; FIND_SEG's page count.
;; Also: IOPGCN (BB13)
PageCount = Parameters + FindSegmentList::PAGE_COUNT

;; The third parameter: CREATE's option list's length.
;; Also: INLNGTH (BB13)
CreateOptionsLength:
    .byte 0

;; OPEN's option list's length.
;; Also: OPNLNGTH (BB13)
OpenOptionsLength:
    .byte 0

;; The count `READ` really moved.
;; Also: OUTBYTES (BB13)
Transferred = Parameters + ReadList::TRANSFERRED

;; FIND_SEG's base bank and page.
;; Also: BSBNKP (BB13)
SegmentBase = Parameters + FindSegmentList::BASE
    .word 0                                 ; FIND_SEG's limit bank and page

;; FIND_SEG's segment number.
;; Also: OSEGNM (BB13)
SegmentNumber:
    .byte 0

.assert Pathname = Parameters + OpenList::PATHNAME, "Pathname is the calls' first parameter."
.assert CreateOptions = Parameters + CreateList::OPTIONS, "CreateOptions is CREATE's option list."
.assert CreateOptionsLength = Parameters + CreateList::OPTIONS_LENGTH, "CREATE's option list's length."
.assert OpenOptionsLength = Parameters + OpenList::OPTIONS_LENGTH, "OpenOptionsLength is OPEN's option list's length."
.assert SegmentNumber = Parameters + FindSegmentList::SEGMENT, "SegmentNumber is FIND_SEG's segment number."

;; The storage type of a seedling file, a file of one block.
STORAGE_SEEDLING = 1

;; CREATE's option list: the file type, the auxiliary type and the storage type, a <SosCalls::FileOptions>.
;; Also: CRTTBL (BB13)
NewFileOptions:

;; The file type CREATE gives the file.
;; Also: INFLID (BB13)
NewFileType:
    .byte 0

;; The auxiliary type CREATE gives the file; BASIC puts a data file's record length here.
;; Also: INAUXID (BB13)
NewFileAuxType:
    .word 0

;; The storage type CREATE gives the file: a seedling.
;; Also: INSTRTYP (BB13)
NewFileStorageType:
    .byte STORAGE_SEEDLING

;; CREATE's end of file, which BASIC never sets.
;;
;; Its initial contents are whatever was in memory when Apple built SOS.INTERP.
;; Also: INEOF (BB13)
NewFileEnd:
.if VERSION = 123
    .res 4, $A0
.else
    .res 4
.endif

.assert NewFileType = NewFileOptions + FileOptions::FILE_TYPE, "NewFileType is CREATE's file type."
.assert NewFileAuxType = NewFileOptions + FileOptions::AUX_TYPE, "NewFileAuxType is CREATE's auxiliary type."
.assert NewFileStorageType = NewFileOptions + FileOptions::STORAGE_TYPE, "NewFileStorageType is CREATE's storage type."
.assert NewFileEnd = NewFileOptions + FileOptions::EOF, "NewFileEnd is CREATE's end of file."

;; GET_FILE_INFO's and SET_FILE_INFO's information list, a <SosCalls::FileInformation>: the access bits first.
;; Also: FATRB (BB13)
FileAccess:
    .byte 0

;; The file's type.
;; Also: FID (BB13)
FileType:
    .byte 0

;; The file's auxiliary type.
;; Also: FAUX (BB13)
FileAuxType:
    .word 0

;; The file's storage type.
;; Also: FSTYP (BB13)
FileStorageType:
    .byte 0

;; The file's end, four bytes.
;; Also: FEOF (BB13)
FileEnd:
    .word 0
    .word 0

;; The file's count of blocks.
;; Also: FBLKS (BB13)
FileBlocks:
    .word 0
    .word 0                                 ; the date

.assert FileType = FileAccess + FileInformation::FILE_TYPE, "FileType is the information's file type."
.assert FileAuxType = FileAccess + FileInformation::AUX_TYPE, "FileAuxType is the information's auxiliary type."
.assert FileStorageType = FileAccess + FileInformation::STORAGE_TYPE, "The storage type."
.assert FileEnd = FileAccess + FileInformation::EOF, "FileEnd is the information's end of file."
.assert FileBlocks = FileAccess + FileInformation::BLOCKS, "FileBlocks is the information's count of blocks."

;; OPEN's option list: the access requested, 1 to read, from `LOAD`, or 2 to read and write, from `SAVE`.
;; Also: INREQ (BB13)
OpenAccess:
    .byte 0

;; The bytes of the information list <SosCalls::HelloInformation> asks for.
HELLO_INFORMATION_LENGTH = 3

;; GET_FILE_INFO's parameter list for `HELLO`, which tells <ColdStart> whether there is a program to run.
;; Also: HELF (BB13)
HelloInformation:
    .byte FILE_INFO_COUNT
    .word HelloPathname
    .word FileAccess
    .byte HELLO_INFORMATION_LENGTH

;; `HELLO`'s pathname, its length first.
HelloPathname:
    .byte .strlen("HELLO")

;; `HELLO`, the program BASIC runs at start, with a zero after.
;; Also: HELCN (BB13)
HelloName:
    .byte "HELLO"
    .byte 0

;; Gets a file's information into <SosCalls::FileAccess>, after <GETFISET> sets the call up.
;; See: <GETFISET>, <SosCalls::MakeFileCall>
;; Also: GETFI (BB13)
.proc GetFileInfo
    jsr GETFISET
    ; Falls into SosCalls::MakeFileCall.
.endproc

;; Makes a file call from <SosCalls::Parameters>, ending the statement with the error, if any.
;; In: Y = the call's index in <SosCalls::CallNumbers>, such as <SosCalls::CALL_OPEN>
;; See: <SosCalls::SetUp>, <SosCalls::Call>
;; Also: SETGO (BB13)
.proc MakeFileCall
    jsr SetUp
    jsr Call
    beq SetUp::Done
    jmp SERROR
.endproc

;; Sets <SosCalls::Call> up for a file call: its number, and its parameter count in <SosCalls::Parameters>.
;; In: Y = the call's index in <SosCalls::CallNumbers>, such as <SosCalls::CALL_OPEN>
;; Keeps: X, Y
;; Entry: Done = returns, for <SosCalls::MakeFileCall> when the call worked
;; Also: SETUP (BB13)
.proc SetUp
    lda a:CallNumbers,Y
    sta Call::Number
    lda #<(Parameters)
    sta Call::Number+1
    lda #>(Parameters)
    sta Call::Number+2
    lda a:ParameterCounts,Y
    sta Parameters

;; Returns.
;; Also: NOWRTS (BB13)
Done:
    rts
.endproc

; The file calls' indexes in CallNumbers and ParameterCounts.

;; CREATE's index.
;; Also: CRT (BB13)
CALL_CREATE = 0

;; DESTROY's index.
;; Also: DST (BB13)
CALL_DESTROY = CALL_CREATE+1

;; RENAME's index.
;; Also: RNM (BB13)
CALL_RENAME = CALL_DESTROY+1

;; SET_FILE_INFO's index.
;; Also: SFI (BB13)
CALL_SET_FILE_INFO = CALL_RENAME+1

;; GET_FILE_INFO's index.
;; Also: GFI (BB13)
CALL_GET_FILE_INFO = CALL_SET_FILE_INFO+1

;; OPEN's index.
;; Also: OPN (BB13)
CALL_OPEN = CALL_GET_FILE_INFO+1

;; NEWLINE's index.
;; Also: NWL (BB13)
CALL_NEWLINE = CALL_OPEN+1

;; READ's index.
;; Also: RED (BB13)
CALL_READ = CALL_NEWLINE+1

;; WRITE's index.
;; Also: WRT (BB13)
CALL_WRITE = CALL_READ+1

;; CLOSE's index.
;; Also: CLS (BB13)
CALL_CLOSE = CALL_WRITE+1

;; SET_MARK's index.
;; Also: STM (BB13)
CALL_SET_MARK = CALL_CLOSE+1

;; GET_MARK's index.
;; Also: GTM (BB13)
CALL_GET_MARK = CALL_SET_MARK+1

;; RELEASE_SEG's index.
;; Also: RLS (BB13)
CALL_RELEASE_SEG = CALL_GET_MARK+1

;; FIND_SEG's index.
;; Also: FND (BB13)
CALL_FIND_SEG = CALL_RELEASE_SEG+1

;; SET_EOF's index.
;; Also: STE (BB13)
CALL_SET_EOF = CALL_FIND_SEG+1

;; The joystick call's index.
;; Also: PDL (BB13)
CALL_JOYSTICK = CALL_SET_EOF+1

;; One entry of <SosCalls::CallNumbers>: a file call's SOS call number, at its index.
;; Parameters:
;;   index = the call's index, such as <SosCalls::CALL_OPEN>
;;   number = the SOS call number
.macro SosCallNumber index, number
    .assert * - CallNumbers = index, "A call number is at its call's index."
    .byte number
.endmacro

;; One entry of <SosCalls::ParameterCounts>: a file call's parameter count, at its index.
;; Parameters:
;;   index = the call's index, such as <SosCalls::CALL_OPEN>
;;   count = the call's parameter count
.macro SosParameterCount index, count
    .assert * - ParameterCounts = index, "A parameter count is at its call's index."
    .byte count
.endmacro

;; The SOS call number of each file call, by its index.
;; See: <SosCalls::ParameterCounts>, <SosCalls::SetUp>
;; Also: SCNUMT (BB13)
CallNumbers:
    SosCallNumber CALL_CREATE, SCRT
    SosCallNumber CALL_DESTROY, SDST
    SosCallNumber CALL_RENAME, SRNM
    SosCallNumber CALL_SET_FILE_INFO, SSFI
    SosCallNumber CALL_GET_FILE_INFO, SGFI
    SosCallNumber CALL_OPEN, SOPN
    SosCallNumber CALL_NEWLINE, SNWL
    SosCallNumber CALL_READ, SRED
    SosCallNumber CALL_WRITE, SWRT
    SosCallNumber CALL_CLOSE, SCLS
    SosCallNumber CALL_SET_MARK, SSTM
    SosCallNumber CALL_GET_MARK, SGTM
    SosCallNumber CALL_RELEASE_SEG, MRLS
    SosCallNumber CALL_FIND_SEG, MFND
    SosCallNumber CALL_SET_EOF, SSTE
    SosCallNumber CALL_JOYSTICK, SOS_JOYSTICK

;; The parameter count of each file call, in <SosCalls::CallNumbers>'s order.
;; Also: PCNTT (BB13)
ParameterCounts:
    SosParameterCount CALL_CREATE, CREATE_COUNT
    SosParameterCount CALL_DESTROY, DESTROY_COUNT
    SosParameterCount CALL_RENAME, RENAME_COUNT
    SosParameterCount CALL_SET_FILE_INFO, FILE_INFO_COUNT
    SosParameterCount CALL_GET_FILE_INFO, FILE_INFO_COUNT
    SosParameterCount CALL_OPEN, OPEN_COUNT
    SosParameterCount CALL_NEWLINE, NEWLINE_COUNT
    SosParameterCount CALL_READ, READ_COUNT
    SosParameterCount CALL_WRITE, WRITE_COUNT
    SosParameterCount CALL_CLOSE, CLOSE_COUNT
    SosParameterCount CALL_SET_MARK, SET_MARK_COUNT
    SosParameterCount CALL_GET_MARK, GET_MARK_COUNT
    SosParameterCount CALL_RELEASE_SEG, RELEASE_SEG_COUNT
    SosParameterCount CALL_FIND_SEG, FIND_SEG_COUNT
    SosParameterCount CALL_SET_EOF, SET_MARK_COUNT
    SosParameterCount CALL_JOYSTICK, JOYSTICK_COUNT

.endscope
.if VERSION >= 130

; ---------------------------------------------------------------------------------------------------------------------
; 1.3's program prefix
;
; With a program selector, a program runs with its own volume's prefix while BASIC's own files keep SOS's prefix.
; BASIC keeps both, in SOSPATH and PROGPATH, and sets the one each command needs.
; ---------------------------------------------------------------------------------------------------------------------

;; 1.3's two prefixes, SOS's own in <SOSPATH> and the program's in <PROGPATH>, and setting SOS's prefix to either.
.scope Prefix

;; GET_PREFIX's buffer length.
PATHNAME_LIMIT = 80

;; Strips the file name from <PROGPATH>, leaving the prefix up to its last slash.
;; Keeps: X
;; Entry: Done = returns, for the prefix routines' branches
;; Also: SPROGPFX (BB13)
.proc StripFileName
    ldy PROGPATH
    beq Done
    iny

;; Steps back to the last slash.
;; Also: PRGLP (BB13)
FindSlash:
    dey
    lda PROGPATH,Y
    cmp #'/'
    bne FindSlash
    sty PROGPATH

;; Returns.
;; Also: PRGRTS (BB13)
Done:
    rts
.endproc

;; Sets SOS's prefix back to BASIC's, from <SOSPATH>.
;; See: <Prefix::UseProgram>
;; Also: SETSOS (BB13)
.proc UseSos
    lda #<(SOSPATH)
    sta a:Pathname
    lda #>(SOSPATH)
    sta a:Pathname+1
    jmp Set
.endproc

;; Sets SOS's prefix to the program's, from <PROGPATH>; after `RUN` or `CHAIN`, it takes the new program's first.
;; See: <Prefix::UseSos>, <Prefix::TakeFromName>
;; Also: SETPROG (BB13)
.proc UseProgram
    lda CMDFLG
    beq SetProgramPrefix                    ; no RUN or CHAIN: PROGPATH stands
    jsr TakeFromName

;; Points the call at <PROGPATH>.
SetProgramPrefix:
    lda #<(PROGPATH)
    sta a:Pathname
    lda #>(PROGPATH)
    sta a:Pathname+1
    ; Falls into Prefix::Set.
.endproc

;; Sets SOS's prefix to the pathname <Prefix::Pathname> points to, ending the statement with an error if it fails.
;; Entry: Failed = ends the statement with the SOS error in A
;; Also: SETPFX (BB13)
.proc Set
    brk
    .byte SETPREF
    .word Parameters
    beq StripFileName::Done

;; Ends the statement with the prefix call's error.
;; Also: MPERR (BB13)
Failed:
    jmp SERROR
.endproc

;; Copies SOS's prefix into <SOSPATH>, through <CATBUF>.
;; Also: FILSOS (BB13)
.proc SaveSos
    brk
    .byte GETPREF
    .word PREFTAB
    bne Set::Failed
    ldy CATBUF+1                            ; the prefix's length

;; Copies the prefix, with its length, last byte first.
CopyPrefix:
    lda CATBUF+1,Y
    sta SOSPATH,Y
    dey
    bpl CopyPrefix
    rts
.endproc

;; Takes the program's prefix from the name in <NAMBUF> when it is a full pathname (starting with `.` or `/`), then
;; marks `RUN`'s or `CHAIN`'s prefix as taken.
;; Also: FILPROG (BB13)
.proc TakeFromName
    lda NAMBUF+1
    cmp #'.'                                ; a device name
    beq CopyPathname
    cmp #'/'                                ; a volume name
    bne Taken

;; Copies the full pathname in <NAMBUF> into <PROGPATH> and strips its file name.
;; Also: FILPROG2 (BB13)
CopyPathname:
    ldy NAMBUF

;; Copies a byte of the pathname, last first.
CopyByte:
    lda NAMBUF,Y
    sta PROGPATH,Y
    dey
    bpl CopyByte
    jsr StripFileName

;; Clears <CMDFLG>: the prefix is taken.
;; Also: FILPROG1 (BB13)
Taken:
    lda #0
    sta CMDFLG
    rts
.endproc

;; Copies SOS's prefix from <SOSPATH> to <PROGPATH>, for a program run without the selector.
;; Keeps: X
;; Also: COPYSOS (BB13)
.proc CopySosToProgram
    ldy SOSPATH

;; Copies a byte, last first.
CopyByte:
    lda SOSPATH,Y
    sta PROGPATH,Y
    dey
    bpl CopyByte
    rts
.endproc

;; Makes <PROGPATH> name the volume rather than the device: sets it as SOS's prefix and reads the prefix back, which
;; SOS gives by volume name.
;; Also: CNVTPFX1 (BB13)
.proc ToVolumeName
    lda #<(PROGPATH)
    sta a:Pathname
    lda #>(PROGPATH)
    sta a:Pathname+1
    brk
    .byte SETPREF
    .word Parameters
    lda #SosCalls::GET_PREFIX_COUNT
    sta a:Parameters
    brk
    .byte GETPREF
    .word Parameters
    dec a:Parameters                        ; and SET_PREFIX's count again
    rts
.endproc

;; SET_PREFIX's and GET_PREFIX's parameter list, a <SosCalls::PrefixList>: the count, 1 for SET_PREFIX, 2 for
;; GET_PREFIX.
Parameters:
    .byte SosCalls::SET_PREFIX_COUNT

;; The pathname's address, for <Prefix::Set> and <Prefix::ToVolumeName>, then GET_PREFIX's buffer length.
;; Also: SHFTPFX (BB13)
Pathname:
    .word 0
    .byte PATHNAME_LIMIT

.assert Pathname = Parameters + SosCalls::PrefixList::PATHNAME, "Pathname is the prefix's address."

.endscope
.endif
