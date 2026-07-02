
ILEZERO — Zero Tile

Opcode/Instruction	                                Op/En	64/32 bit Mode Support	CPUID Feature Flag	    Description
VEX.128.F2.0F38.W0 49 11:rrr:000 TILEZERO tmm1	    A	    V/N.E.	                AMX-TILE	            Zero the destination tile.

Instruction Operand Encoding:

Op/En	Tuple	Operand 1	    Operand 2	Operand 3	Operand 4
A	    N/A	    ModRM:reg (w)	N/A	        N/A	        N/A

Description:

This instruction zeroes the destination tile.

Any attempt to execute the TILEZERO instruction inside an Intel TSX transaction will result in a transaction abort.

Operation:

TILEZERO tdest
nbytes := palette_table[palette_id].bytes_per_row
for i in 0 ... palette_table[palette_id].max_rows-1:
    for j in 0 ... nbytes-1:
        tdest.row[i].byte[j] := 0
zero_tilecfg_start()

Intel C/C++ Compiler Intrinsic Equivalent:

TILEZERO void _tile_zero(__tile dst);

Flags Affected:

None.

Exceptions:

AMX-E5; see Section 2.10, “Intel® AMX Instruction Exception Classes,” for details.



VZEROALL — Zero XMM, YMM, and ZMM Registers

Opcode/Instruction	Op /En	64/32 bit Mode Support	CPUID Feature Flag	Description
VEX.256.0F.WIG 77 VZEROALL	ZO	V/V	AVX	Zero some of the XMM, YMM, and ZMM registers.

Instruction Operand Encoding:

Op/En	Operand 1	Operand 2	Operand 3	Operand 4
ZO	    N/A	    N/A	            N/A	        N/A

Description:

In 64-bit mode, the instruction zeroes XMM0-XMM15, YMM0-YMM15, and ZMM0-ZMM15. Outside 64-bit mode, it zeroes only XMM0-XMM7, YMM0-YMM7, and ZMM0-ZMM7. VZEROALL does not modify ZMM16-ZMM31.

Note: VEX.vvvv is reserved and must be 1111b, otherwise instructions will #UD. In Compatibility and legacy 32-bit mode only the lower 8 registers are modified.

Operation:

simd_reg_file[][] is a two dimensional array representing the SIMD register file containing all the overlapping xmm, ymm, and zmm
registers present in that implementation. The major dimension is the register number: 0 for xmm0, ymm0, and zmm0; 1 for xmm1,
ymm1, and zmm1; etc. The minor dimension size is the width of the implemented SIMD state measured in bits. On a machine
supporting Intel AVX-512, the width is 512.

VZEROALL (VEX.256 encoded version):

IF (64-bit mode)
    limit :=15
ELSE
    limit := 7
FOR i in 0 .. limit:
    simd_reg_file[i][MAXVL-1:0] := 0
    
Intel C/C++ Compiler Intrinsic Equivalent:

VZEROALL: _mm256_zeroall()

SIMD Floating-Point Exceptions:

None.

Other Exceptions:

See Table 2-25, “Type 8 Class Exception Conditions.”



VZEROUPPER — Zero Upper Bits of YMM and ZMM Registers

Opcode/Instruction	            Op /En	64/32 bit Mode Support	CPUID Feature Flag	Description
VEX.128.0F.WIG 77 VZEROUPPER	ZO	    V/V	                    AVX	                Zero bits in positions 128 and higher of some YMM and ZMM registers.

Instruction Operand Encoding:

Op/En	Operand 1	Operand 2	Operand 3	Operand 4
ZO	    N/A	        N/A	        N/A	        N/A

Description:

In 64-bit mode, the instruction zeroes the bits in positions 128 and higher in YMM0-YMM15 and ZMM0-ZMM15. Outside 64-bit mode, it zeroes those bits only in YMM0-YMM7 and ZMM0-ZMM7. VZEROUPPER does not modify the lower 128 bits of these registers and it does not modify ZMM16-ZMM31.

This instruction is recommended when transitioning between AVX and legacy SSE code; it will eliminate performance penalties caused by false dependencies.

Note: VEX.vvvv is reserved and must be 1111b otherwise instructions will #UD. In Compatibility and legacy 32-bit mode only the lower 8 registers are modified.

Operation:

simd_reg_file[][] is a two dimensional array representing the SIMD register file containing all the overlapping xmm, ymm, and zmm
registers present in that implementation. The major dimension is the register number: 0 for xmm0, ymm0, and zmm0; 1 for xmm1,
ymm1, and zmm1; etc. The minor dimension size is the width of the implemented SIMD state measured in bits.

VZEROUPPER:

IF (64-bit mode)
    limit :=15
ELSE
    limit := 7
FOR i in 0 .. limit:
    simd_reg_file[i][MAXVL-1:128] := 0

Intel C/C++ Compiler Intrinsic Equivalent:

VZEROUPPER: _mm256_zeroupper()

SIMD Floating-Point Exceptions:

None.

Other Exceptions:

See Table 2-25, “Type 8 Class Exception Conditions.”


