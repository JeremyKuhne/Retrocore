; retrocore: style=strict
;; COMMODORE BASIC: COMMODORE'S NAMES OF SHARED DEFINITIONS
;;
;; Commodore's names, and the names Microsoft's source gives only in its Commodore builds, for definitions of the
;; shared Microsoft modules. They resolve only in the PET and VIC-20 builds that include this file. Each entry is an
;; alias in <Commodore> that inherits its target's documentation and gives the names in its `Also:` section, citing the
;; documents by their keys in docs/Bibliography.md: Microsoft's source (M6502), Commodore's BASIC 4 listing of July
;; 23, 1979 (CBM4S79), and Martin Hoffmann-Vetter's reconstructions of each PET BASIC (HV1, HV1R, HV2, HV4, HV4R),
;; each for its own build and, under the lineage rule, for the same definition in the other PET builds, and
;; Commodore's listing of the VIC-20's BASIC (BV20), which the lineage rule reaches in the same way: on each entry
;; whose name it gives at the same address, in every build that has the entry. In CBM4S79,
;; SQR05 and SQR20 are in code18, TENC in code19, N0999, N9999 and NMIL in code22, and RMULC and RADDC in code25;
;; COPYC is in code6, STRD in code14, and CHRD, LEFTD, RIGHTD and MIDD in code16. The room check and the classic
;; collector's steps also have Microsoft's names here (M6502), since BASIC 4 gives those names to other steps, and so
;; does ANDOP on its AND, since AppleSoft gives it to its OR (Basic.md E4). Including this file emits no bytes and
;; does not change the origin.

;; The aliases for Commodore's names. Code uses the definitions' own names; these exist for the old names.
.scope Commodore

;; Inherit: <Float::SquareRootOfHalf>
;; Also: SQR05 (CBM4S79, HV1, HV1R, HV2, HV4, HV4R, BV20)
SquareRootOfHalf = Float::SquareRootOfHalf

;; Inherit: <Float::SquareRootOfTwo>
;; Also: SQR20 (CBM4S79, HV1, HV1R, HV2, HV4, HV4R, BV20)
SquareRootOfTwo = Float::SquareRootOfTwo

;; Inherit: <Float::Ten>
;; Also: TENC (CBM4S79, HV1, HV1R, HV2, HV4, HV4R, BV20)
Ten = Float::Ten

;; Inherit: <Float::LowerOutputLimit>
;; Also: N0999 (CBM4S79, HV1, HV1R, HV2, HV4, HV4R, BV20)
LowerOutputLimit = Float::LowerOutputLimit

;; Inherit: <Float::UpperOutputLimit>
;; Also: N9999 (CBM4S79, HV1, HV1R, HV2, HV4, HV4R, BV20)
UpperOutputLimit = Float::UpperOutputLimit

;; Inherit: <Float::Billion>
;; Also: NMIL (CBM4S79, HV1, HV1R, HV2, HV4, HV4R, BV20)
Billion = Float::Billion

;; Inherit: <Float::RandomMultiplier>
;; Also: RMULC (CBM4S79, HV1, HV1R, HV2, HV4, HV4R, BV20)
RandomMultiplier = Float::RandomMultiplier

;; Inherit: <Float::RandomAddend>
;; Also: RADDC (CBM4S79, HV1, HV1R, HV2, HV4, HV4R, BV20)
RandomAddend = Float::RandomAddend

;; Inherit: <Functions::Log::MultiplyByLogOfTwo>
;; Also: MULLN2 (M6502, CBM4S79, HV4, HV4R)
MultiplyByLogOfTwo = Functions::Log::MultiplyByLogOfTwo

;; Inherit: <Functions::Tan::ToDividePacked>
;; Also: GFDIV (M6502)
ToDividePacked = Functions::Tan::ToDividePacked

;; Inherit: <CharacterReaderTemplate::GetCurrent>
;; Also: CHDGOT (CBM4S79, HV1, HV1R, HV2, HV4, HV4R, BV20)
CharacterReaderGetCurrent = CharacterReaderTemplate::GetCurrent

;; Inherit: <CharacterReaderTemplate::Done>
;; Also: CHDRTS (CBM4S79, HV1, HV1R, HV2, HV4, HV4R, BV20)
CharacterReaderDone = CharacterReaderTemplate::Done

; BASIC 4's lister, which reads its keyword table through a pointer.
.ifdef Statements::List::ReadWordByte
;; Inherit: <Statements::List::ReadWordByte>
;; Also: RESCR2 (CBM4S79, HV4, HV4R)
ReadListWordByte = Statements::List::ReadWordByte
.endif

.ifdef Statements::List::ListFirstWord
;; Inherit: <Statements::List::ListFirstWord>
;; Also: PRIT3B (CBM4S79, HV4, HV4R)
ListFirstWord = Statements::List::ListFirstWord
.endif


; The string assignment's descriptor copy and the shared string functions. Each is guarded, so that a build of part
; of the modules, without them, leaves them out: the shared copy by the classic collector it goes with, BASIC 4's own
; copy (in Commodore.StringAssignment.asm) and the functions by their targets.
.ifdef Strings::CollectGarbage::NextPass
;; Inherit: <::StoreDescriptor>
;; Also: COPYC (CBM4S79, HV1, HV1R, HV2, HV4, HV4R, BV20)
StoreDescriptor = ::StoreDescriptor
.endif

.ifdef ::StoreLinkedDescriptor
;; Inherit: <::StoreLinkedDescriptor>
;; Also: COPYC (CBM4S79, HV1, HV1R, HV2, HV4, HV4R, BV20)
LinkedDescriptor = ::StoreLinkedDescriptor
.endif

.ifdef Functions::Str
;; Inherit: <Functions::Str>
;; Also: STRD (CBM4S79, HV1, HV1R, HV2, HV4, HV4R, BV20)
Str = Functions::Str
.endif

.ifdef Functions::Chr
;; Inherit: <Functions::Chr>
;; Also: CHRD (CBM4S79, HV1, HV1R, HV2, HV4, HV4R, BV20)
Chr = Functions::Chr
.endif

.ifdef Functions::Left
;; Inherit: <Functions::Left>
;; Also: LEFTD (CBM4S79, HV1, HV1R, HV2, HV4, HV4R, BV20)
Left = Functions::Left
.endif

.ifdef Functions::Right
;; Inherit: <Functions::Right>
;; Also: RIGHTD (CBM4S79, HV1, HV1R, HV2, HV4, HV4R, BV20)
Right = Functions::Right
.endif

.ifdef Functions::Mid
;; Inherit: <Functions::Mid>
;; Also: MIDD (CBM4S79, HV1, HV1R, HV2, HV4, HV4R, BV20)
Mid = Functions::Mid
.endif


; The PET's AND, which Microsoft's source names ANDOP; AppleSoft's overlay gives ANDOP to its OR.
.ifdef Operators::And
;; Inherit: <Operators::And>
;; Also: ANDOP (M6502, CBM4S79, HV1, HV1R, HV2, HV4, HV4R, BV20)
AndOperator = Operators::And
.endif


; BASIC 4's allocator's return, which Microsoft's GETRTS names in the output routine instead.
.ifdef Strings::ReserveSpace::Done
;; Inherit: <Strings::ReserveSpace::Done>
;; Also: GETRTS (CBM4S79, HV4, HV4R)
ReserveReturn = Strings::ReserveSpace::Done
.endif

; The unlinked allocator's room check in BASIC 1 and 2, and the linked allocator's step before its own, which BASIC 4's
; documents give Microsoft's name for the room check.
.ifdef Strings::ReserveSpace::CheckRoom
;; Inherit: <Strings::ReserveSpace::CheckRoom>
;; Also: TRYAG3 (M6502, HV1, HV1R, HV2, BV20)
UnlinkedCheckRoom = Strings::ReserveSpace::CheckRoom
.endif

.ifdef Strings::ReserveSpace::BelowLink
;; Inherit: <Strings::ReserveSpace::BelowLink>
;; Also: TRYAG3 (CBM4S79, HV4, HV4R)
ReserveBelowLink = Strings::ReserveSpace::BelowLink
.endif

; BASIC 4's room check in its linked allocator.
.ifdef Strings::ReserveSpace::CheckLinkedRoom
;; Inherit: <Strings::ReserveSpace::CheckLinkedRoom>
;; Also: TRYAG4 (CBM4S79, HV4, HV4R)
ReserveCheckRoom = Strings::ReserveSpace::CheckLinkedRoom
.endif

; The classic collector's steps in BASIC 1 and 2, whose Microsoft names BASIC 4 gives to its array back-link steps.
.ifdef Strings::CollectGarbage::NextArray
;; Inherit: <Strings::CollectGarbage::NextArray>
;; Also: ARYVA2 (M6502, HV1, HV1R, HV2, BV20)
CollectorNextArray = Strings::CollectGarbage::NextArray
.endif

.ifdef Strings::CollectGarbage::CheckArraysEnd
;; Inherit: <Strings::CollectGarbage::CheckArraysEnd>
;; Also: ARYVA3 (M6502, HV1, HV1R, HV2, BV20)
CollectorCheckArraysEnd = Strings::CollectGarbage::CheckArraysEnd
.endif

.ifdef Strings::CollectGarbage::ReadArray
;; Inherit: <Strings::CollectGarbage::ReadArray>
;; Also: ARYVGO (M6502, HV1, HV1R, HV2, BV20)
CollectorReadArray = Strings::CollectGarbage::ReadArray
.endif

.ifdef Strings::CollectGarbage::ElementsReady
;; Inherit: <Strings::CollectGarbage::ElementsReady>
;; Also: ARYGET (M6502, HV1, HV1R, HV2, BV20)
CollectorElementsReady = Strings::CollectGarbage::ElementsReady
.endif

.ifdef Strings::CollectGarbage::CheckElement
;; Inherit: <Strings::CollectGarbage::CheckElement>
;; Also: GOGO (M6502, HV1, HV1R, HV2, BV20)
CollectorCheckElement = Strings::CollectGarbage::CheckElement
.endif

.ifdef Strings::CollectGarbage::Advance
;; Inherit: <Strings::CollectGarbage::Advance>
;; Also: DVARTS (M6502, HV1, HV1R, HV2, BV20)
CollectorAdvance = Strings::CollectGarbage::Advance
.endif


; BASIC 4's names for its own paths in the shared variable lookup and string release.
.ifdef FindVariable::SecondMismatch
;; Inherit: <FindVariable::SecondMismatch>
;; Also: NXTPTR (CBM4S79, HV4, HV4R)
SecondNameMismatch = FindVariable::SecondMismatch
.endif

.ifdef Variables::CheckReservedName::CheckDiskStatus
;; Inherit: <Variables::CheckReservedName::CheckDiskStatus>
;; Also: QDSVAR (CBM4S79, HV4, HV4R)
CheckDiskStatusName = Variables::CheckReservedName::CheckDiskStatus
.endif

.ifdef Variables::Create::NextArray
;; Inherit: <Variables::Create::NextArray>
;; Also: ARYVA2 (CBM4S79, HV4, HV4R)
CreateNextArray = Variables::Create::NextArray
.endif

.ifdef Variables::Create::CheckArraysEnd
;; Inherit: <Variables::Create::CheckArraysEnd>
;; Also: ARYVA3 (CBM4S79, HV4, HV4R)
CreateCheckArraysEnd = Variables::Create::CheckArraysEnd
.endif

.ifdef Variables::Create::ReadArray
;; Inherit: <Variables::Create::ReadArray>
;; Also: ARYVGO (CBM4S79, HV4, HV4R)
CreateReadArray = Variables::Create::ReadArray
.endif

.ifdef Variables::Create::ScanElements
;; Inherit: <Variables::Create::ScanElements>
;; Also: ARYGET (CBM4S79, HV4, HV4R)
CreateScanElements = Variables::Create::ScanElements
.endif

.ifdef Variables::Create::CheckElement
;; Inherit: <Variables::Create::CheckElement>
;; Also: GOGO (CBM4S79, HV4, HV4R)
CreateCheckElement = Variables::Create::CheckElement
.endif

.ifdef Variables::Create::MoveLink
;; Inherit: <Variables::Create::MoveLink>
;; Also: GOGO1 (CBM4S79, HV4, HV4R)
CreateMoveLink = Variables::Create::MoveLink
.endif

.ifdef Variables::Create::Advance
;; Inherit: <Variables::Create::Advance>
;; Also: DVARTS (CBM4S79, HV4, HV4R)
CreateAdvance = Variables::Create::Advance
.endif

.ifdef Variables::Create::WriteEntry
;; Inherit: <Variables::Create::WriteEntry>
;; Also: ARYDON (CBM4S79, HV4, HV4R)
CreateWriteEntry = Variables::Create::WriteEntry
.endif

.ifdef Strings::ReleaseDescriptor::CheckBottom
;; Inherit: <Strings::ReleaseDescriptor::CheckBottom>
;; Also: RES00 (CBM4S79, HV4, HV4R)
ReleaseCheckBottom = Strings::ReleaseDescriptor::CheckBottom
.endif

.ifdef Strings::ReleaseDescriptor::SkipLink
;; Inherit: <Strings::ReleaseDescriptor::SkipLink>
;; Also: FRE01 (CBM4S79, HV4, HV4R)
ReleaseSkipLink = Strings::ReleaseDescriptor::SkipLink
.endif

.ifdef Strings::ReleaseDescriptor::ReadDescriptor
;; Inherit: <Strings::ReleaseDescriptor::ReadDescriptor>
;; Also: FRE02 (CBM4S79, HV4, HV4R)
ReleaseReadDescriptor = Strings::ReleaseDescriptor::ReadDescriptor
.endif

; The VIC-20's BASIC (BV20): the shared entries only its build has.
.ifdef ClearVariables::AfterClose
;; Inherit: <ClearVariables::AfterClose>
;; Also: CLEART (BV20)
ClearVariablesAfterClose = ClearVariables::AfterClose
.endif
.ifdef Statements::List::CheckTokenDefault
;; Inherit: <Statements::List::CheckTokenDefault>
;; Also: NQPLOP (BV20)
CheckTokenDefault = Statements::List::CheckTokenDefault
.endif
.ifdef EvaluateOperand::Default
;; Inherit: <EvaluateOperand::Default>
;; Also: NEVAL (BV20)
EvaluateOperandDefault = EvaluateOperand::Default
.endif
.ifdef ::FacToSignedWord
;; Inherit: <::FacToSignedWord>
;; Also: FLPINT (BV20)
FloatToInteger = ::FacToSignedWord
.endif


.endscope
