; retrocore: style=strict
;; The dispatch tables: the routine for each opcode from <FIRST_TABLE_OPCODE> up, and for each standard procedure.

;; The routine that runs each opcode from <FIRST_TABLE_OPCODE> ($80) up, in opcode order. Fetch reaches it
;; through <Dispatch>.
;; Also: PCTBL (WK11)
OpcodeTable:
    Opcode $80, Pcodes::AbsoluteInteger
    Opcode $81, Pcodes::AbsoluteReal
    Opcode $82, Pcodes::AddIntegers
    Opcode $83, Pcodes::AddReals
    Opcode $84, Pcodes::LogicalAnd
    Opcode $85, Pcodes::SetDifference
    Opcode $86, Pcodes::DivideIntegers
    Opcode $87, Pcodes::DivideReals
    Opcode $88, Pcodes::CheckRange
    Opcode $89, Pcodes::FloatNextToTop
    Opcode $8A, Pcodes::FloatTop
    Opcode $8B, Pcodes::InSet
    Opcode $8C, Pcodes::SetIntersection
    Opcode $8D, Pcodes::LogicalOr
    Opcode $8E, Pcodes::ModuloIntegers
    Opcode $8F, Pcodes::MultiplyIntegers
    Opcode $90, Pcodes::MultiplyReals
    Opcode $91, Pcodes::NegateInteger
    Opcode $92, Pcodes::NegateReal
    Opcode $93, Pcodes::LogicalNot
    Opcode $94, Pcodes::SubrangeSet
    Opcode $95, Pcodes::SubtractIntegers
    Opcode $96, Pcodes::SubtractReals
    Opcode $97, Pcodes::SingletonSet
    Opcode $98, Pcodes::SquareInteger
    Opcode $99, Pcodes::SquareReal
    Opcode $9A, Pcodes::StoreIndirect
    Opcode $9B, Pcodes::IndexString
    Opcode $9C, Pcodes::SetUnion
    Opcode $9D, Pcodes::LoadExtended
    Opcode $9E, Pcodes::CallStandardProcedure
    Opcode $9F, Pcodes::LoadNil
    Opcode $A0, Pcodes::AdjustSet
    Opcode $A1, Jump::IfFalse
    Opcode $A2, Pcodes::IncrementField
    Opcode $A3, Pcodes::LoadIndirect
    Opcode $A4, Pcodes::IndexArray
    Opcode $A5, Pcodes::LoadGlobalAddress
    Opcode $A6, Pcodes::LoadStringAddress
    Opcode $A7, Pcodes::LoadExtendedAddress
    Opcode $A8, Pcodes::MoveWords
    Opcode $A9, Pcodes::LoadGlobal
    Opcode $AA, Pcodes::AssignString
    Opcode $AB, Pcodes::StoreGlobal
    Opcode $AC, Pcodes::CaseJump
    Opcode $AD, Pcodes::ReturnFromProcedure
    Opcode $AE, Pcodes::CallIntermediateProcedure
    Opcode $AF, Pcodes::Equal
    Opcode $B0, Pcodes::GreaterOrEqual
    Opcode $B1, Pcodes::Greater
    Opcode $B2, Pcodes::LoadIntermediateAddress
    Opcode $B3, Pcodes::LoadMultipleConstant
    Opcode $B4, Pcodes::LessOrEqual
    Opcode $B5, Pcodes::Less
    Opcode $B6, Pcodes::LoadIntermediate
    Opcode $B7, Pcodes::NotEqual
    Opcode $B8, Pcodes::StoreIntermediate
    Opcode $B9, Jump::Always
    Opcode $BA, Pcodes::LoadPackedField
    Opcode $BB, Pcodes::StorePackedField
    Opcode $BC, Pcodes::LoadMultiple
    Opcode $BD, Pcodes::StoreMultiple
    Opcode $BE, Pcodes::LoadByte
    Opcode $BF, Pcodes::StoreByte
    Opcode $C0, Pcodes::IndexPackedArray
    Opcode $C1, Pcodes::ReturnFromBaseProcedure
    Opcode $C2, Pcodes::CallBaseProcedure
    Opcode $C3, Pcodes::EqualIntegers
    Opcode $C4, Pcodes::GreaterOrEqualIntegers
    Opcode $C5, Pcodes::GreaterIntegers
    Opcode $C6, Pcodes::LoadLocalAddress
    Opcode $C7, Pcodes::LoadConstantWord
    Opcode $C8, Pcodes::LessOrEqualIntegers
    Opcode $C9, Pcodes::LessIntegers
    Opcode $CA, Pcodes::LoadLocal
    Opcode $CB, Pcodes::NotEqualIntegers
    Opcode $CC, Pcodes::StoreLocal
    Opcode $CD, Pcodes::CallExternalProcedure
    Opcode $CE, Pcodes::CallLocalProcedure
    Opcode $CF, Pcodes::CallGlobalProcedure
    Opcode $D0, Pcodes::LoadPackedArrayAddress
    Opcode $D1, Pcodes::StoreExtended
    ; NOP, $D2 and $D7: Fetch::Skip1 steps over it.
    Opcode $D2, Fetch::Skip1
    ; EFJ and NFJ: SYSTEM.APPLE 1.1 has no routine for them.
    Opcode $D3, ExecutionError::Unimplemented
    Opcode $D4, ExecutionError::Unimplemented
    Opcode $D5, Pcodes::Breakpoint
    Opcode $D6, Pcodes::ExitSystem
    Opcode $D7, Fetch::Skip1
    ; SLDL 1-16: one routine, which works out the local from the opcode.
    Opcodes $D8, $E7, Pcodes::ShortLoadLocal
    ; SLDO 1-16: one routine, which works out the global from the opcode.
    Opcodes $E8, $F7, Pcodes::ShortLoadGlobal
    Opcode $F8, Pcodes::ShortLoadIndirect::Zero
    ; SIND 1-7 (SIND 0 has its own entry point in the same routine).
    Opcodes $F9, $FF, Pcodes::ShortLoadIndirect

;; The routine that runs each standard procedure, by the number <CSP at Pcodes::CallStandardProcedure> gives it.
;; <Pcodes::CallStandardProcedure> reaches it through <CspDispatch>.
;; Also: CSPTBL (WK11)
CspTable:
    StandardProcedure CSP::IOC, StandardProcedures::IoCheck
    StandardProcedure CSP::NEW, StandardProcedures::New
    ; MVL and MVR: one routine, which tells them apart by the number.
    StandardProcedure CSP::MVL, StandardProcedures::MoveLeftOrRight
    StandardProcedure CSP::MVR, StandardProcedures::MoveLeftOrRight
    StandardProcedure CSP::EXIT, StandardProcedures::ExitProcedure
    StandardProcedure CSP::UREAD, StandardProcedures::UnitRead
    StandardProcedure CSP::UWRITE, StandardProcedures::UnitWrite
    StandardProcedure CSP::IDS, StandardProcedures::IdentifierSearch
    StandardProcedure CSP::TRS, StandardProcedures::TreeSearch
    StandardProcedure CSP::TIM, StandardProcedures::Time
    StandardProcedure CSP::FLC, StandardProcedures::FillCharacters
    StandardProcedure CSP::SCN, StandardProcedures::Scan
    StandardProcedure CSP::USTAT, StandardProcedures::UnitStatus
    NoStandardProcedures 13, 20
    StandardProcedure CSP::GSEG, StandardProcedures::GetSegment
    StandardProcedure CSP::RSEG, StandardProcedures::ReleaseSegment
    StandardProcedure CSP::TNC, StandardProcedures::Truncate
    StandardProcedure CSP::RND, StandardProcedures::Round
    ; SIN, COS, LOG, ATAN, LN, EXP and SQT: SYSTEM.APPLE 1.1 leaves these to TRANSCEND, in SYSTEM.LIBRARY.
    StandardProcedure CSP::SIN, ExecutionError::Unimplemented
    StandardProcedure CSP::COS, ExecutionError::Unimplemented
    StandardProcedure CSP::LOG, ExecutionError::Unimplemented
    StandardProcedure CSP::ATAN, ExecutionError::Unimplemented
    StandardProcedure CSP::LN, ExecutionError::Unimplemented
    StandardProcedure CSP::EXP, ExecutionError::Unimplemented
    StandardProcedure CSP::SQT, ExecutionError::Unimplemented
    StandardProcedure CSP::MRK, StandardProcedures::MarkHeap
    StandardProcedure CSP::RLS, StandardProcedures::ReleaseHeap
    StandardProcedure CSP::IOR, StandardProcedures::IoResult
    StandardProcedure CSP::UBUSY, StandardProcedures::UnitBusy
    StandardProcedure CSP::POT, StandardProcedures::PowerOfTen
    StandardProcedure CSP::UWAIT, StandardProcedures::UnitWait
    StandardProcedure CSP::UCLEAR, StandardProcedures::UnitClear
    StandardProcedure CSP::HLT, StandardProcedures::Halt
    StandardProcedure CSP::MEMA, StandardProcedures::MemoryAvailable
