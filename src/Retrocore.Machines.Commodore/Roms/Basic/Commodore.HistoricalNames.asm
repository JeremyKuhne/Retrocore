; retrocore: style=strict
;; COMMODORE BASIC: COMMODORE'S NAMES OF SHARED DEFINITIONS
;;
;; Commodore's names, and the names Microsoft's source gives only in its Commodore builds, for definitions of the
;; shared Microsoft modules. They resolve only in the PET builds that include this file. Each entry is an alias in
;; <Commodore> that inherits its target's documentation and gives the names in its `Also:` section, citing the
;; documents by their keys in docs/Bibliography.md: Microsoft's source (M6502), Commodore's BASIC 4 listing of July
;; 23, 1979 (CBM4S79), and Martin Hoffmann-Vetter's reconstructions of each PET BASIC (HV1, HV1R, HV2, HV4, HV4R),
;; each for its own build. Including this file emits no bytes and does not change the origin.

;; The aliases for Commodore's names. Code uses the definitions' own names; these exist for the old names.
.scope Commodore

;; Inherit: <Float::SquareRootOfHalf>
;; Also: SQR05 (CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
SquareRootOfHalf = Float::SquareRootOfHalf

;; Inherit: <Float::SquareRootOfTwo>
;; Also: SQR20 (CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
SquareRootOfTwo = Float::SquareRootOfTwo

;; Inherit: <Float::Ten>
;; Also: TENC (CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
Ten = Float::Ten

;; Inherit: <Float::LowerOutputLimit>
;; Also: N0999 (CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
LowerOutputLimit = Float::LowerOutputLimit

;; Inherit: <Float::UpperOutputLimit>
;; Also: N9999 (CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
UpperOutputLimit = Float::UpperOutputLimit

;; Inherit: <Float::Billion>
;; Also: NMIL (CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
Billion = Float::Billion

;; Inherit: <Float::RandomMultiplier>
;; Also: RMULC (CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
RandomMultiplier = Float::RandomMultiplier

;; Inherit: <Float::RandomAddend>
;; Also: RADDC (CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
RandomAddend = Float::RandomAddend

;; Inherit: <Functions::Log::MultiplyByLogOfTwo>
;; Also: MULLN2 (M6502, CBM4S79, HV4, HV4R)
MultiplyByLogOfTwo = Functions::Log::MultiplyByLogOfTwo

;; Inherit: <Functions::Tan::ToDividePacked>
;; Also: GFDIV (M6502)
ToDividePacked = Functions::Tan::ToDividePacked

;; Inherit: <CharacterReaderTemplate::GetCurrent>
;; Also: CHDGOT (CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
CharacterReaderGetCurrent = CharacterReaderTemplate::GetCurrent

;; Inherit: <CharacterReaderTemplate::Done>
;; Also: CHDRTS (CBM4S79, HV1, HV1R, HV2, HV4, HV4R)
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

.endscope
