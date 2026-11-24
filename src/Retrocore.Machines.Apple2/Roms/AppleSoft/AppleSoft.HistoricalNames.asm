; retrocore: style=strict
;; APPLESOFT: APPLE'S NAMES OF SHARED DEFINITIONS
;;
;; Apple's names for definitions of the shared Microsoft modules, which resolve only in the AppleSoft builds that
;; include this file. Each entry is an alias in <AppleSoft> that inherits its target's documentation and gives
;; Apple's name in its `Also:` section, citing the documents by their keys in docs/Bibliography.md: the Apple II
;; Technical Information Library's AppleSoft articles (ASTIL; PRNTFAC is in article 79, "Applesoft: Internals--Device
;; I/O Routines", a2til228.txt, and COMBYTE in article 76, "Applesoft: Internals--Floating Point Math Package (3 of
;; 3)", a2til231.txt) and the 1982 AppleSoft disassembly (AS82), or UNKN for the names only the SDK's MACRO-10
;; overlay of AppleSoft gives, which its callers use. Including this file emits no bytes and does not change the
;; origin.

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

.endscope
