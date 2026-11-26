; retrocore: style=strict
;; The dispatch tables: the routine for each opcode from <FIRST_TABLE_OPCODE> up, and for each standard procedure.

;; The routine that runs each opcode from <FIRST_TABLE_OPCODE> ($80) up, in opcode order. Fetch reaches it
;; through <Dispatch>.
;; Also: PCTBL (WK11)
OpcodeTable:
    Opcode $80, OpABI
    Opcode $81, RealMath::OpABR
    Opcode $82, OpADI
    Opcode $83, RealMath::OpADR
    Opcode $84, OpLAND
    Opcode $85, OpDIF
    Opcode $86, OpDVI
    Opcode $87, RealMath::OpDVR
    Opcode $88, OpCHK
    Opcode $89, RealMath::OpFLO
    Opcode $8A, RealMath::OpFLT
    Opcode $8B, OpINN
    Opcode $8C, OpINT
    Opcode $8D, OpLOR
    Opcode $8E, OpMODI
    Opcode $8F, OpMPI
    Opcode $90, RealMath::OpMPR
    Opcode $91, OpNGI
    Opcode $92, RealMath::OpNGR
    Opcode $93, OpLNOT
    Opcode $94, OpSRS
    Opcode $95, OpSBI
    Opcode $96, RealMath::OpSBR
    Opcode $97, OpSGS
    Opcode $98, OpSQI
    Opcode $99, RealMath::OpSQR
    Opcode $9A, OpSTO
    Opcode $9B, OpIXS
    Opcode $9C, OpUNI
    Opcode $9D, OpLDE
    Opcode $9E, OpCSP
    Opcode $9F, OpLDCN
    Opcode $A0, OpADJ
    Opcode $A1, Jump::IfFalse
    Opcode $A2, OpINC
    Opcode $A3, OpIND
    Opcode $A4, OpIXA
    Opcode $A5, OpLAO
    Opcode $A6, OpLSA
    Opcode $A7, OpLAE
    Opcode $A8, OpMOV
    Opcode $A9, OpLDO
    Opcode $AA, OpSAS
    Opcode $AB, OpSRO
    Opcode $AC, OpXJP
    Opcode $AD, OpRNP
    Opcode $AE, OpCIP
    Opcode $AF, OpEQU
    Opcode $B0, OpGEQ
    Opcode $B1, OpGRT
    Opcode $B2, OpLDA
    Opcode $B3, OpLDC
    Opcode $B4, OpLEQ
    Opcode $B5, OpLES
    Opcode $B6, OpLOD
    Opcode $B7, OpNEQ
    Opcode $B8, OpSTR
    Opcode $B9, Jump::Always
    Opcode $BA, OpLDP
    Opcode $BB, OpSTP
    Opcode $BC, OpLDM
    Opcode $BD, OpSTM
    Opcode $BE, OpLDB
    Opcode $BF, OpSTB
    Opcode $C0, OpIXP
    Opcode $C1, OpRBP
    Opcode $C2, OpCBP
    Opcode $C3, OpEQUI
    Opcode $C4, OpGEQI
    Opcode $C5, OpGRTI
    Opcode $C6, OpLLA
    Opcode $C7, OpLDCI
    Opcode $C8, OpLEQI
    Opcode $C9, OpLESI
    Opcode $CA, OpLDL
    Opcode $CB, OpNEQI
    Opcode $CC, OpSTL
    Opcode $CD, OpCXP
    Opcode $CE, OpCLP
    Opcode $CF, OpCGP
    Opcode $D0, OpLPA
    Opcode $D1, OpSTE
    ; NOP, $D2 and $D7: Fetch::Skip1 steps over it.
    Opcode $D2, Fetch::Skip1
    ; EFJ and NFJ: SYSTEM.APPLE 1.1 has no routine for them.
    Opcode $D3, ExecutionError::Unimplemented
    Opcode $D4, ExecutionError::Unimplemented
    Opcode $D5, OpBPT
    Opcode $D6, OpXIT
    Opcode $D7, Fetch::Skip1
    ; SLDL 1-16: one routine, which works out the local from the opcode.
    Opcodes $D8, $E7, OpSLDL
    ; SLDO 1-16: one routine, which works out the global from the opcode.
    Opcodes $E8, $F7, OpSLDO
    Opcode $F8, OpSIND::Zero
    ; SIND 1-7 (SIND 0 has its own entry point in the same routine).
    Opcodes $F9, $FF, OpSIND

;; The routine that runs each standard procedure, by the number <CSP at OpCSP> gives it. <OpCSP> reaches it through
;; <CspDispatch>.
;; Also: CSPTBL (WK11)
CspTable:
    StandardProcedure CSP::IOC, UnitIo::CspIOC
    StandardProcedure CSP::NEW, CspNEW
    ; MVL and MVR: one routine, which tells them apart by the number.
    StandardProcedure CSP::MVL, CspMVL_MVR
    StandardProcedure CSP::MVR, CspMVL_MVR
    StandardProcedure CSP::EXIT, CspEXIT
    StandardProcedure CSP::UREAD, UnitIo::CspUREAD
    StandardProcedure CSP::UWRITE, UnitIo::CspUWRITE
    StandardProcedure CSP::IDS, CspIDS
    StandardProcedure CSP::TRS, CspTRS
    StandardProcedure CSP::TIM, CspTIM
    StandardProcedure CSP::FLC, CspFLC
    StandardProcedure CSP::SCN, CspSCN
    StandardProcedure CSP::USTAT, UnitIo::CspUSTAT
    NoStandardProcedures 13, 20
    StandardProcedure CSP::GSEG, CspGSEG
    StandardProcedure CSP::RSEG, CspRSEG
    StandardProcedure CSP::TNC, RealMath::CspTNC
    StandardProcedure CSP::RND, RealMath::CspRND
    ; SIN, COS, LOG, ATAN, LN, EXP and SQT: SYSTEM.APPLE 1.1 leaves these to TRANSCEND, in SYSTEM.LIBRARY.
    StandardProcedure CSP::SIN, ExecutionError::Unimplemented
    StandardProcedure CSP::COS, ExecutionError::Unimplemented
    StandardProcedure CSP::LOG, ExecutionError::Unimplemented
    StandardProcedure CSP::ATAN, ExecutionError::Unimplemented
    StandardProcedure CSP::LN, ExecutionError::Unimplemented
    StandardProcedure CSP::EXP, ExecutionError::Unimplemented
    StandardProcedure CSP::SQT, ExecutionError::Unimplemented
    StandardProcedure CSP::MRK, CspMRK
    StandardProcedure CSP::RLS, CspRLS
    StandardProcedure CSP::IOR, UnitIo::CspIOR
    StandardProcedure CSP::UBUSY, UnitIo::CspUBUSY
    StandardProcedure CSP::POT, RealMath::CspPOT
    StandardProcedure CSP::UWAIT, UnitIo::CspUWAIT
    StandardProcedure CSP::UCLEAR, UnitIo::CspUCLEAR
    StandardProcedure CSP::HLT, CspHLT
    StandardProcedure CSP::MEMA, CspMEMA
