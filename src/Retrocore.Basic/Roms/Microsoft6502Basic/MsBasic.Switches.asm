; MICROSOFT 6502 BASIC: SHARED BUILD SWITCHES
;
; The platform selects REALIO before including this file. These defaults describe the AppleSoft and PET builds.
; TIME controls the time-output path and table in MsBasic.FloatOutput.asm, but not clock support as a whole;
; the PET floating-point composition selects its time-output path independently. EXTIO and DISKO record legacy
; configuration values only: native platform modules and macro arguments, not these values, select I/O code.
; Shipped roots assert their supported settings; custom compositions may still supply these values independently.

.ifndef REALIO
REALIO = 4                          ;; Microsoft I/O target: 3 for Commodore, 4 for Apple
.endif
.ifndef INTPRC
INTPRC = 1                          ;; 1 includes integer-variable and integer-array support
.endif
.ifndef ADDPRC
ADDPRC = 1                          ;; 1 includes the extra floating-point mantissa byte
.endif
.ifndef LNGERR
LNGERR = 1                          ;; 1 uses full error messages
.endif
.ifndef TIME
.if REALIO = 3
TIME = 1                            ;; time-output selection in MsBasic.FloatOutput.asm, not a full clock switch
.else
TIME = 0                            ;; time-output selection in MsBasic.FloatOutput.asm, not a full clock switch
.endif
.endif
.ifndef EXTIO
.if REALIO = 3
EXTIO = 1                           ;; legacy external-I/O setting; informational in native modules
.else
EXTIO = 0                           ;; legacy external-I/O setting; informational in native modules
.endif
.endif
.ifndef DISKO
.if REALIO = 3
DISKO = 1                           ;; legacy disk-I/O setting; informational in native modules
.else
DISKO = 0                           ;; legacy disk-I/O setting; informational in native modules
.endif
.endif

.assert REALIO = 3 || REALIO = 4, "The native sources support REALIO 3 and 4."
.assert INTPRC = 1, "INTPRC must be 1; the native sources require integer arrays."
.assert ADDPRC = 1, "ADDPRC must be 1; the native sources require five-byte floats."
.assert LNGERR = 1, "LNGERR must be 1; the native sources require long errors."
.assert TIME = 0 || TIME = 1, "TIME is 0 or 1."
.assert EXTIO = 0 || EXTIO = 1, "EXTIO is 0 or 1."
.assert DISKO = 0 || DISKO = 1, "DISKO is 0 or 1."
