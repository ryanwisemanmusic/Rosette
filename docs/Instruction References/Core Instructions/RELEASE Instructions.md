TILERELEASE — Release Tile

Opcode/Instruction	                    Op/En	64/32 bit Mode Support	CPUID Feature Flag	Description
VEX.128.NP.0F38.W0 49 C0 TILERELEASE	A	    V/N.E.	                AMX-TILE	        Initialize TILECFG and TILEDATA.

Instruction Operand Encoding:

Op/En	Tuple	Operand 1	Operand 2	Operand 3	Operand 4
A	    N/A	    N/A	        N/A	        N/A	        N/A

Description:

This instruction returns TILECFG and TILEDATA to the INIT state.

Any attempt to execute the TILERELEASE instruction inside an Intel TSX transaction will result in a transaction abort.

Operation:

zero_all_tile_data()
tilecfg := 0// equivalent to 64B of zeros
TILES_CONFIGURED := 0

Intel C/C++ Compiler Intrinsic Equivalent:

TILERELEASE void _tile_release(void);

Flags Affected:

None.

Exceptions:

AMX-E6; see Section 2.10, “Intel® AMX Instruction Exception Classes,” for details.