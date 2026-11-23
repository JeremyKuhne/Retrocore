# Bibliography

The documents that the SDK's sources take historical names from. A `;; Also:` entry cites them by key, as
`;; Also: COUT (A2RM78)`: hover shows the document, and the lint reports a key that is not in this table. See
[DocComments.md](DocComments.md) (section 2.4).

The language server reads this table from the SDK's copy of this file. A `Bibliography.md` at the root of a
workspace adds documents of its own, or replaces a key, with the same columns.

| Key | Title | Year | Publisher | Link |
| --- | --- | --- | --- | --- |
| A1OM | Apple-1 Operation Manual | 1976 | Apple Computer | |
| A2RM78 | Apple II Reference Manual | 1978 | Apple Computer | <https://archive.org/details/Apple_II_Redbook> |
| A2RM79 | Apple II Reference Manual | 1979 | Apple Computer | |
| PA1 | Programmer's Aid #1 | 1978 | Apple Computer | <https://archive.org/details/programmers-aid-1> |
| DOS33 | DOS 3.3 source listing | July 1983 | Apple Computer | |
| IBSM | Annotated listing of Integer BASIC, by Paul R. Santa-Maria | | | |
| M6502 | BASIC M6502 8K version 1.1 source (MACRO-10), published under the MIT license | 1978 | Microsoft | <https://github.com/microsoft/BASIC-M6502> |
| ASTIL | Apple II Technical Information Library: "Applesoft: Internals" articles | | Apple Computer | <https://mirrors.apple2.org.za/Apple%20II%20Documentation%20Project/Companies/Apple/Documentation/Apple%20Technical%20Information%20Library/> |
| AS82 | Applesoft source listing, May 26, 1982 (Roger Wagner Publishing's reference copy) | 1982 | Apple Computer | <https://archive.org/details/roger_wagner_applesoft_source> |
| CBM4S79 | PET BASIC version 4 source, listing of July 23, 1979 (OCRed and reconstructed by Martin Hoffmann-Vetter) | 1979 | Commodore | <https://github.com/mist64/cbmsrc/tree/01bd60f162ef92212ef0cb67546ae8f42be34168/BASIC_PET_V4_1979-07-23> |
| K4S79 | PET 2001 operating system version 4.0 (July 25, 1979), listing of October 23, 1979 (OCRed and reconstructed by Martin Hoffmann-Vetter) | 1979 | Commodore | <https://github.com/mist64/cbmsrc/tree/01bd60f162ef92212ef0cb67546ae8f42be34168/KERNAL_PET_4.0_1979-10-23> |
| HV1 | PET BASIC 1 (901439-01 ...), reconstructed source | | Martin Hoffmann-Vetter | <https://github.com/mist64/cbmsrc/tree/01bd60f162ef92212ef0cb67546ae8f42be34168/BASIC_PET_V1_REC> |
| HV1R | PET BASIC 1 revised (901439-09 ...), reconstructed source | | Martin Hoffmann-Vetter | <https://github.com/mist64/cbmsrc/tree/01bd60f162ef92212ef0cb67546ae8f42be34168/BASIC_PET_V1R_REC> |
| HV2 | PET BASIC 2 (901465-01, -02, 901447-24), reconstructed source | | Martin Hoffmann-Vetter | <https://github.com/mist64/cbmsrc/tree/01bd60f162ef92212ef0cb67546ae8f42be34168/BASIC_PET_V2_REC> |
| HV4 | PET BASIC 4 (901465-19, -20, -21), reconstructed source | | Martin Hoffmann-Vetter | <https://github.com/mist64/cbmsrc/tree/01bd60f162ef92212ef0cb67546ae8f42be34168/BASIC_PET_V4_REC> |
| HV4R | PET BASIC 4 revised (901465-23, -20, -21), reconstructed source | | Martin Hoffmann-Vetter | <https://github.com/mist64/cbmsrc/tree/01bd60f162ef92212ef0cb67546ae8f42be34168/BASIC_PET_V4R_REC> |
| HVK4 | PET operating system 4.0 (901465-21, 901447-29, 901465-22), reconstructed source | | Martin Hoffmann-Vetter | <https://github.com/mist64/cbmsrc/tree/01bd60f162ef92212ef0cb67546ae8f42be34168/KERNAL_PET_4.0_REC> |

## How the BASIC documents were checked

The Microsoft 6502 BASIC keys were checked against the SDK's builds before any name is cited from them; none of their
text is in the repository. The full method, with the counts, is step 2 of the BASIC conversion's log,
`docs/conversions/Basic.md`, on the `claude/basic-rename-table` branch until it is merged. A name is cited from a
document only where the check found that the document gives that name for that thing:

- **M6502:** the repository's `m6502.asm`. Each MACRO-10 overlay build was assembled on it, and a name is cited for a
  build where `m6502.asm` defines it and the overlay build gives it the same value as the native build. Where the
  overlay's definition is in a vendor's `.mac`, a matching value shows only that the overlay kept Microsoft's label on
  the vendor's code, so each such case was checked for the `.mac` replacing the very line that defines the name;
  M6502 is not cited on the nine rows where it does not.
- **ASTIL:** names and addresses read from the "Applesoft: Internals" index, page-zero map and routine articles, and
  cited where the address equals the AppleSoft builds' value. A name found only in prose is not cited.
- **AS82:** only the archive's damaged OCR text could be read. A name is cited only where the listing's symbol tables
  give the same value as the AppleSoft builds. Apple's authorship and the date rest on the archive's description.
- **CBM4S79:** a pre-release whose addresses differ from the ROMs, so page-zero names were checked by value and code
  labels by the instructions and data at the label. It gives names for BASIC 4 only.
- **K4S79:** assembled for RAM ($8000 lower), and cited where the address plus $8000, or the page-zero value, equals
  the BASIC 4 build's.
- **HV1, HV1R, HV2, HV4, HV4R:** assembled by a script that reads their text and reproduces each ROM's bytes but
  for the checksum bytes. A name is cited for its own build where its address or value equals the native build's.
  cbmsrc's notes say the reconstructions of BASIC 1 carry Commodore's later names back to BASIC 1's code, so HV1's
  and HV1R's names are the reconstructor's, not Microsoft's or Commodore's of 1977.
- **HVK4:** as the HV keys, at the BASIC 4 ROMs' addresses.
