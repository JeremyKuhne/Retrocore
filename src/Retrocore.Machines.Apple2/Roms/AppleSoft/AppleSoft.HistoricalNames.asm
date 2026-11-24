; retrocore: style=strict
;; APPLESOFT: APPLE'S NAMES OF SHARED DEFINITIONS
;;
;; Apple's names for definitions of the shared Microsoft modules, which resolve only in the AppleSoft builds that
;; include this file. Each entry is an alias in <AppleSoft> that inherits its target's documentation and gives
;; Apple's name in its `Also:` section, citing the documents by their keys in docs/Bibliography.md: the Apple II
;; Technical Information Library's AppleSoft articles (ASTIL; PRNTFAC is in article 79, "Applesoft: Internals--Device
;; I/O Routines", a2til228.txt, and COMBYTE in article 76, "Applesoft: Internals--Floating Point Math Package (3 of
;; 3)", a2til231.txt) and the May 1982 Applesoft source listing (AS82), or UNKN for the names only the SDK's MACRO-10
;; overlay of AppleSoft gives, which its callers use. The room check and the classic collector's steps also have
;; Microsoft's names here (M6502), since BASIC 4 gives those names to other definitions (Basic.md E4). Including this
;; file emits no bytes and does not change the origin.

;; The aliases for Apple's names. Code uses the definitions' own names; these exist for the old names.
.scope AppleSoft

;; Inherit: <Float::PrintFac>
;; Also: PRNTFAC (ASTIL)
PrintFac = Float::PrintFac

;; Inherit: <Float::FormatFacAtOffset::SignDone>
;; Also: FOUT13 (UNKN)
SignDone = Float::FormatFacAtOffset::SignDone

;; Inherit: <Float::OverflowError>
;; Also: OVERFLOW (AS82)
OverflowError = Float::OverflowError

;; Inherit: <Float::DivideArg>
;; Also: FIDVT (ASTIL)
DivideArg = Float::DivideArg

;; Inherit: <Float::ReadNumber::Digit>
;; Also: INSRTDIG (AS82)
ReadNumberDigit = Float::ReadNumber::Digit

;; Inherit: <Float::LogPolynomial>
;; Also: LOGSER (AS82)
LogPolynomial = Float::LogPolynomial

;; Inherit: <Float::Billion>
;; Also: BILLION (AS82)
Billion = Float::Billion

;; Inherit: <RequireType::Mismatch>
;; Also: MISMTCH (AS82)
Mismatch = RequireType::Mismatch

;; Inherit: <Statements::New>
;; Also: NEW (ASTIL, AS82)
New = Statements::New

;; Inherit: <::ReadCommaAndByte>
;; Also: COMBYTE (ASTIL, AS82)
ReadCommaAndByte = ::ReadCommaAndByte

;; Inherit: <Statements::List::ReadSecondBound>
;; Also: GOLST1 (UNKN)
SecondListBound = Statements::List::ReadSecondBound

;; Inherit: <Statements::List::NextTableByte>
;; Also: GRODY1 (UNKN)
NextListTableByte = Statements::List::NextTableByte

;; Inherit: <Statements::List::ReadTableByte>
;; Also: GRODY2 (UNKN)
ReadListTableByte = Statements::List::ReadTableByte

;; Inherit: <Statements::List::ListWordCharacter>
;; Also: PRIT31 (UNKN)
ListKeywordCharacter = Statements::List::ListWordCharacter

;; Inherit: <Statements::List::ListLastCharacter>
;; Also: PRIT32 (UNKN)
ListLastKeywordCharacter = Statements::List::ListLastCharacter

;; Inherit: <Statements::PopFinish>
;; Also: REMER1 (UNKN)
PopFinish = Statements::PopFinish

;; Inherit: <Variables::FindArray::Search>
;; Also: INDLO1 (UNKN)
FindArraySearch = Variables::FindArray::Search

;; Inherit: <Variables::ArrayFound::CheckDimensions>
;; Also: GOTAR1 (UNKN)
ArrayFoundCheckDimensions = Variables::ArrayFound::CheckDimensions

;; Inherit: <Variables::ArrayMissing>
;; Also: GOTAR2 (UNKN)
ArrayMissing = Variables::ArrayMissing

;; Inherit: <Operators::Not::LoadFalse>
;; Also: NOTOP1 (UNKN)
NotLoadFalse = Operators::Not::LoadFalse

;; Inherit: <Operators::Or>
;; Also: ANDOP (UNKN)
OrOperator = Operators::Or

;; Inherit: <Operators::And>
;; Also: OROP1 (UNKN)
AndOperator = Operators::And

;; Inherit: <Operators::And::LoadFalse>
;; Also: OROP11 (UNKN)
AndLoadFalse = Operators::And::LoadFalse

;; Inherit: <Operators::And::LoadTrue>
;; Also: OROP12 (UNKN)
AndLoadTrue = Operators::And::LoadTrue

;; Inherit: <AssignVariableList::CheckEmptyLine>
;; Also: NOWGE2 (UNKN)
CheckEmptyInputLine = AssignVariableList::CheckEmptyLine

;; Inherit: <AssignVariableList::RestoreCharacter>
;; Also: NOWGE3 (UNKN)
RestoreInputCharacter = AssignVariableList::RestoreCharacter

;; Inherit: <AssignVariableList::EmptyNumber>
;; Also: TRMOK1 (UNKN)
EmptyInputNumber = AssignVariableList::EmptyNumber

;; Inherit: <FindVariable::AfterVectors>
;; Also: PTRGT4 (UNKN)
AfterVectors = FindVariable::AfterVectors

;; Inherit: <FindVariable::ToChooseArrayLookup>
;; Also: STRNA1 (UNKN)
ToChooseArrayLookup = FindVariable::ToChooseArrayLookup

;; Inherit: <FindVariable::NoParenthesis>
;; Also: STRNA2 (UNKN)
NoParenthesis = FindVariable::NoParenthesis

;; Inherit: <FindVariable::SearchScalars>
;; Also: STRNA3 (UNKN)
SearchScalars = FindVariable::SearchScalars

;; Inherit: <ZeroVariable>
;; Also: SIMZER (UNKN)
SimpleZero = ::ZeroVariable

;; Inherit: <Variables::ElementsStart::FromCount>
;; Also: FMAPT1 (UNKN)
ElementsStartFromCount = Variables::ElementsStart::FromCount

;; Inherit: <Variables::ChooseArrayLookup>
;; Also: QINTG1 (UNKN)
ChooseArrayLookup = Variables::ChooseArrayLookup

; The statements whose dispatch entries the shared modules define.

;; Inherit: <Statements::On>
;; Also: ON (UNKN)
On = Statements::On

;; `WAIT`'s handler, under AppleSoft's own label for it.
;; Inherit: <Statements::Wait>
;; Also: WAIT (UNKN)
Wait = Statements::Wait


; The unlinked allocator's room check and the classic collector's steps, whose Microsoft names BASIC 4 gives to other
; steps instead.

;; Inherit: <Strings::ReserveSpace::CheckRoom>
;; Also: TRYAG3 (M6502)
UnlinkedCheckRoom = Strings::ReserveSpace::CheckRoom

;; Inherit: <Strings::CollectGarbage::NextArray>
;; Also: ARYVA2 (M6502)
CollectorNextArray = Strings::CollectGarbage::NextArray

;; Inherit: <Strings::CollectGarbage::CheckArraysEnd>
;; Also: ARYVA3 (M6502)
CollectorCheckArraysEnd = Strings::CollectGarbage::CheckArraysEnd

;; Inherit: <Strings::CollectGarbage::ReadArray>
;; Also: ARYVGO (M6502)
CollectorReadArray = Strings::CollectGarbage::ReadArray

;; Inherit: <Strings::CollectGarbage::ElementsReady>
;; Also: ARYGET (M6502)
CollectorElementsReady = Strings::CollectGarbage::ElementsReady

;; Inherit: <Strings::CollectGarbage::CheckElement>
;; Also: GOGO (M6502)
CollectorCheckElement = Strings::CollectGarbage::CheckElement

;; Inherit: <Strings::CollectGarbage::Advance>
;; Also: DVARTS (M6502)
CollectorAdvance = Strings::CollectGarbage::Advance

.endscope
