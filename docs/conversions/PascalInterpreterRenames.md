# Apple Pascal 1.1's interpreter: renames

The definitions the conversion renamed, for [PascalInterpreter.md](PascalInterpreter.md). Each renamed definition
that a document names keeps that name in its `Also:`; the names before this conversion were the private
conversion's own, which no document gives, so they are not kept (PI8). Locals moved with their routines
(`OpEQU::Bytes` is `Pcodes::Equal::Bytes`).

| Before | Now | What |
| --- | --- | --- |
| `CspEXIT` | `StandardProcedures::ExitProcedure` | standard procedure |
| `CspFLC` | `StandardProcedures::FillCharacters` | standard procedure |
| `CspGSEG` | `StandardProcedures::GetSegment` | standard procedure |
| `CspHLT` | `StandardProcedures::Halt` | standard procedure |
| `CspIDS` | `StandardProcedures::IdentifierSearch` | standard procedure |
| `CspMEMA` | `StandardProcedures::MemoryAvailable` | standard procedure |
| `CspMRK` | `StandardProcedures::MarkHeap` | standard procedure |
| `CspMVL_MVR` | `StandardProcedures::MoveLeftOrRight` | standard procedure |
| `CspNEW` | `StandardProcedures::New` | standard procedure |
| `CspRLS` | `StandardProcedures::ReleaseHeap` | standard procedure |
| `CspRSEG` | `StandardProcedures::ReleaseSegment` | standard procedure |
| `CspSCN` | `StandardProcedures::Scan` | standard procedure |
| `CspTIM` | `StandardProcedures::Time` | standard procedure |
| `CspTRS` | `StandardProcedures::TreeSearch` | standard procedure |
| `OpABI` | `Pcodes::AbsoluteInteger` | p-code handler |
| `OpADI` | `Pcodes::AddIntegers` | p-code handler |
| `OpADJ` | `Pcodes::AdjustSet` | p-code handler |
| `OpBPT` | `Pcodes::Breakpoint` | p-code handler |
| `OpCBP` | `Pcodes::CallBaseProcedure` | p-code handler |
| `OpCGP` | `Pcodes::CallGlobalProcedure` | p-code handler |
| `OpCHK` | `Pcodes::CheckRange` | p-code handler |
| `OpCIP` | `Pcodes::CallIntermediateProcedure` | p-code handler |
| `OpCLP` | `Pcodes::CallLocalProcedure` | p-code handler |
| `OpCSP` | `Pcodes::CallStandardProcedure` | p-code handler |
| `OpCXP` | `Pcodes::CallExternalProcedure` | p-code handler |
| `OpDIF` | `Pcodes::SetDifference` | p-code handler |
| `OpDVI` | `Pcodes::DivideIntegers` | p-code handler |
| `OpEQU` | `Pcodes::Equal` | p-code handler |
| `OpEQUI` | `Pcodes::EqualIntegers` | p-code handler |
| `OpGEQ` | `Pcodes::GreaterOrEqual` | p-code handler |
| `OpGEQI` | `Pcodes::GreaterOrEqualIntegers` | p-code handler |
| `OpGRT` | `Pcodes::Greater` | p-code handler |
| `OpGRTI` | `Pcodes::GreaterIntegers` | p-code handler |
| `OpINC` | `Pcodes::IncrementField` | p-code handler |
| `OpIND` | `Pcodes::LoadIndirect` | p-code handler |
| `OpINN` | `Pcodes::InSet` | p-code handler |
| `OpINT` | `Pcodes::SetIntersection` | p-code handler |
| `OpIXA` | `Pcodes::IndexArray` | p-code handler |
| `OpIXP` | `Pcodes::IndexPackedArray` | p-code handler |
| `OpIXS` | `Pcodes::IndexString` | p-code handler |
| `OpLAE` | `Pcodes::LoadExtendedAddress` | p-code handler |
| `OpLAND` | `Pcodes::LogicalAnd` | p-code handler |
| `OpLAO` | `Pcodes::LoadGlobalAddress` | p-code handler |
| `OpLDA` | `Pcodes::LoadIntermediateAddress` | p-code handler |
| `OpLDB` | `Pcodes::LoadByte` | p-code handler |
| `OpLDC` | `Pcodes::LoadMultipleConstant` | p-code handler |
| `OpLDCI` | `Pcodes::LoadConstantWord` | p-code handler |
| `OpLDCN` | `Pcodes::LoadNil` | p-code handler |
| `OpLDE` | `Pcodes::LoadExtended` | p-code handler |
| `OpLDL` | `Pcodes::LoadLocal` | p-code handler |
| `OpLDM` | `Pcodes::LoadMultiple` | p-code handler |
| `OpLDO` | `Pcodes::LoadGlobal` | p-code handler |
| `OpLDP` | `Pcodes::LoadPackedField` | p-code handler |
| `OpLEQ` | `Pcodes::LessOrEqual` | p-code handler |
| `OpLEQI` | `Pcodes::LessOrEqualIntegers` | p-code handler |
| `OpLES` | `Pcodes::Less` | p-code handler |
| `OpLESI` | `Pcodes::LessIntegers` | p-code handler |
| `OpLLA` | `Pcodes::LoadLocalAddress` | p-code handler |
| `OpLNOT` | `Pcodes::LogicalNot` | p-code handler |
| `OpLOD` | `Pcodes::LoadIntermediate` | p-code handler |
| `OpLOR` | `Pcodes::LogicalOr` | p-code handler |
| `OpLPA` | `Pcodes::LoadPackedArrayAddress` | p-code handler |
| `OpLSA` | `Pcodes::LoadStringAddress` | p-code handler |
| `OpMODI` | `Pcodes::ModuloIntegers` | p-code handler |
| `OpMOV` | `Pcodes::MoveWords` | p-code handler |
| `OpMPI` | `Pcodes::MultiplyIntegers` | p-code handler |
| `OpNEQ` | `Pcodes::NotEqual` | p-code handler |
| `OpNEQI` | `Pcodes::NotEqualIntegers` | p-code handler |
| `OpNGI` | `Pcodes::NegateInteger` | p-code handler |
| `OpRBP` | `Pcodes::ReturnFromBaseProcedure` | p-code handler |
| `OpRNP` | `Pcodes::ReturnFromProcedure` | p-code handler |
| `OpSAS` | `Pcodes::AssignString` | p-code handler |
| `OpSBI` | `Pcodes::SubtractIntegers` | p-code handler |
| `OpSGS` | `Pcodes::SingletonSet` | p-code handler |
| `OpSIND` | `Pcodes::ShortLoadIndirect` | p-code handler |
| `OpSLDL` | `Pcodes::ShortLoadLocal` | p-code handler |
| `OpSLDO` | `Pcodes::ShortLoadGlobal` | p-code handler |
| `OpSQI` | `Pcodes::SquareInteger` | p-code handler |
| `OpSRO` | `Pcodes::StoreGlobal` | p-code handler |
| `OpSRS` | `Pcodes::SubrangeSet` | p-code handler |
| `OpSTB` | `Pcodes::StoreByte` | p-code handler |
| `OpSTE` | `Pcodes::StoreExtended` | p-code handler |
| `OpSTL` | `Pcodes::StoreLocal` | p-code handler |
| `OpSTM` | `Pcodes::StoreMultiple` | p-code handler |
| `OpSTO` | `Pcodes::StoreIndirect` | p-code handler |
| `OpSTP` | `Pcodes::StorePackedField` | p-code handler |
| `OpSTR` | `Pcodes::StoreIntermediate` | p-code handler |
| `OpUNI` | `Pcodes::SetUnion` | p-code handler |
| `OpXIT` | `Pcodes::ExitSystem` | p-code handler |
| `OpXJP` | `Pcodes::CaseJump` | p-code handler |
| `RealMath::CspPOT` | `StandardProcedures::PowerOfTen` | standard procedure |
| `RealMath::CspRND` | `StandardProcedures::Round` | standard procedure |
| `RealMath::CspTNC` | `StandardProcedures::Truncate` | standard procedure |
| `RealMath::OpABR` | `Pcodes::AbsoluteReal` | p-code handler |
| `RealMath::OpADR` | `Pcodes::AddReals` | p-code handler |
| `RealMath::OpDVR` | `Pcodes::DivideReals` | p-code handler |
| `RealMath::OpFLO` | `Pcodes::FloatNextToTop` | p-code handler |
| `RealMath::OpFLT` | `Pcodes::FloatTop` | p-code handler |
| `RealMath::OpMPR` | `Pcodes::MultiplyReals` | p-code handler |
| `RealMath::OpNGR` | `Pcodes::NegateReal` | p-code handler |
| `RealMath::OpSBR` | `Pcodes::SubtractReals` | p-code handler |
| `RealMath::OpSQR` | `Pcodes::SquareReal` | p-code handler |
| `UnitIo::CspIOC` | `StandardProcedures::IoCheck` | standard procedure |
| `UnitIo::CspIOR` | `StandardProcedures::IoResult` | standard procedure |
| `UnitIo::CspUBUSY` | `StandardProcedures::UnitBusy` | standard procedure |
| `UnitIo::CspUCLEAR` | `StandardProcedures::UnitClear` | standard procedure |
| `UnitIo::CspUREAD` | `StandardProcedures::UnitRead` | standard procedure |
| `UnitIo::CspUSTAT` | `StandardProcedures::UnitStatus` | standard procedure |
| `UnitIo::CspUWAIT` | `StandardProcedures::UnitWait` | standard procedure |
| `UnitIo::CspUWRITE` | `StandardProcedures::UnitWrite` | standard procedure |
| `BASE` | `GlobalFrame` | register |
| `MP` | `LocalFrame` | register |
| `JTAB` | `JumpTable` | register |
| `SEG` | `ProcedureDictionary` | register |
| `IPC` | `InstructionPointer` | register |
| `NP` | `HeapTop` | register |
| `KP` | `ProgramStackTop` | register |
| `Syscom` | `Syscom::Start` | SYSCOM word |
| `SysIoResult` | `Syscom::IoResult` | SYSCOM word |
| `SysErrorNumber` | `Syscom::ErrorNumber` | SYSCOM word |
| `SysBootUnit` | `Syscom::BootUnit` | SYSCOM word |
| `SysDirectory` | `Syscom::Directory` | SYSCOM word |
| `SysErrorStack` | `Syscom::ErrorFrame` | SYSCOM word |
| `SysBase` | `Syscom::SavedGlobalFrame` | SYSCOM word |
| `SysMp` | `Syscom::SavedLocalFrame` | SYSCOM word |
| `SysJtab` | `Syscom::SavedJumpTable` | SYSCOM word |
| `SysSeg` | `Syscom::SavedProcedureDictionary` | SYSCOM word |
| `SysMemoryTop` | `Syscom::StackTop` | SYSCOM word |
| `SysIpc` | `Syscom::ErrorInstruction` | SYSCOM word |
| `SysEofCharacter` | `Syscom::EofCharacter` | SYSCOM word |
| `SegmentTable` | `Syscom::SegmentTable` | SYSCOM word |
| `SyscomExtra` | `Syscom::Rest` | SYSCOM word |
| `SYSCOM_FLUSH_KEY` | `SyscomRecord::FLUSH_KEY` | layout offset |
| `SYSCOM_BREAK_KEY` | `SyscomRecord::BREAK_KEY` | layout offset |
| `SYSCOM_STOP_KEY` | `SyscomRecord::STOP_KEY` | layout offset |
| `MSCW_SIZE` | `.sizeof(MarkStack)` | layout offset |
| `MSCW_STATIC_LINK` | `MarkStack::STATIC_LINK` | layout offset |
| `MSCW_DYNAMIC_LINK` | `MarkStack::DYNAMIC_LINK` | layout offset |
| `MSCW_JTAB` | `MarkStack::JUMP_TABLE` | layout offset |
| `MSCW_SEG` | `MarkStack::PROCEDURE_DICTIONARY` | layout offset |
| `MSCW_IPC` | `MarkStack::INSTRUCTION_POINTER` | layout offset |
| `MSCW_STACK` | `MarkStack::STACK_POINTER` | layout offset |
| `SEGMENT_UNIT` | `SegmentEntry::UNIT` | layout offset |
| `SEGMENT_BLOCK` | `SegmentEntry::BLOCK` | layout offset |
| `SEGMENT_SIZE` | `SegmentEntry::SIZE` | layout offset |
| `SEGMENT_TABLE_ENTRY_SIZE` | `.sizeof(SegmentEntry)` | layout offset |
| `SEGMENT_TABLE_BLOCK` | `SegmentEntry::BLOCK` | layout offset |
| `DIRECTORY_ENTRY_SIZE` | `.sizeof(DirectoryEntry)` | layout offset |
| `DIRECTORY_FIRST_BLOCK` | `DirectoryEntry::FIRST_BLOCK` | layout offset |
| `DIRECTORY_NAME` | `DirectoryEntry::NAME` | layout offset |
| `RealMath::MultiplyReals` | `RealMath::MultiplyOperands` | helper (MPR takes its name) |
| `ReleaseSegment` | `ReleaseSegmentUse` | helper (RSEG takes its name) |
