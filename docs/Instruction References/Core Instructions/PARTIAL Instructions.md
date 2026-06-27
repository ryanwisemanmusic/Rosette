FPATAN — Partial Arctangent

Opcode1

Instruction	    64-Bit Mode	    Compat/Leg Mode	    Description
D9 F3			                Valid	            Replace ST(1) with arctan(ST(1)/ST(0)) and pop the register stack.

1. See IA-32 Architecture Compatibility section below.

Description:

Computes the arctangent of the source operand in register ST(1) divided by the source operand in register ST(0), stores the result in ST(1), and pops the FPU register stack. The result in register ST(0) has the same sign as the source operand ST(1) and a magnitude less than +π.

The FPATAN instruction returns the angle between the X axis and the line from the origin to the point (X,Y), where Y (the ordinate) is ST(1) and X (the abscissa) is ST(0). The angle depends on the sign of X and Y independently, not just on the sign of the ratio Y/X. This is because a point (−X,Y) is in the second quadrant, resulting in an angle between π/2 and π, while a point (X,−Y) is in the fourth quadrant, resulting in an angle between 0 and −π/2. A point (−X,−Y) is in the third quadrant, giving an angle between −π/2 and −π.

The following table shows the results obtained when computing the arctangent of various classes of numbers, assuming that underflow does not occur.

This instruction’s operation is the same in non-64-bit modes and 64-bit mode.

IA-32 Architecture Compatibility:

The source operands for this instruction are restricted for the 80287 math coprocessor to the following range:

0 ≤ |ST(1)| < |ST(0)| < +∞

Operation:

ST(1) := arctan(ST(1) / ST(0));
PopRegisterStack;

FPU Flags Affected:

C1	Set to 0 if stack underflow occurred.
Set if result was rounded up; cleared otherwise.
C0, C2, C3	Undefined.

Floating-Point Exceptions:

#IS:
	Stack underflow occurred.
#IA:
	Source operand is an SNaN value or unsupported format.
#D:
	Source operand is a denormal value.
#U:
	Result is too small for destination format.
#P:
	Value cannot be represented exactly in destination format.

Protected Mode Exceptions:

#NM:
	CR0.EM[bit 2] or CR0.TS[bit 3] = 1.
#MF:
	If there is a pending x87 FPU exception.
#UD:
	If the LOCK prefix is used.

Real-Address Mode Exceptions:

Same exceptions as in protected mode.

Virtual-8086 Mode Exceptions:

Same exceptions as in protected mode.

Compatibility Mode Exceptions:

Same exceptions as in protected mode.

64-Bit Mode Exceptions:

Same exceptions as in protected mode.



FPREM — Partial Remainder

Opcode	Instruction	    64-Bit Mode	    Compat/Leg Mode	    Description
D9 F8	FPREM	        Valid	        Valid	            Replace ST(0) with the remainder obtained from dividing ST(0) by ST(1).

Description:

Computes the remainder obtained from dividing the value in the ST(0) register (the dividend) by the value in the ST(1) register (the divisor or modulus), and stores the result in ST(0). The remainder represents the following value:

Remainder := ST(0) − (Q ∗ ST(1))

Here, Q is an integer value that is obtained by truncating the floating-point number quotient of [ST(0) / ST(1)] toward zero. The sign of the remainder is the same as the sign of the dividend. The magnitude of the remainder is less than that of the modulus, unless a partial remainder was computed (as described below).

This instruction produces an exact result; the inexact-result exception does not occur and the rounding control has no effect. The following table shows the results obtained when computing the remainder of various classes of numbers, assuming that underflow does not occur.

When the result is 0, its sign is the same as that of the dividend. When the modulus is ∞, the result is equal to the value in ST(0).

The FPREM instruction does not compute the remainder specified in IEEE Std 754. The IEEE specified remainder can be computed with the FPREM1 instruction. The FPREM instruction is provided for compatibility with the Intel 8087 and Intel287 math coprocessors.

The FPREM instruction gets its name “partial remainder” because of the way it computes the remainder. This instruction arrives at a remainder through iterative subtraction. It can, however, reduce the exponent of ST(0) by no more than 63 in one execution of the instruction. If the instruction succeeds in producing a remainder that is less than the modulus, the operation is complete and the C2 flag in the FPU status word is cleared. Otherwise, C2 is set, and the result in ST(0) is called the partial remainder. The exponent of the partial remainder will be less than the exponent of the original dividend by at least 32. Software can re-execute the instruction (using the partial remainder in ST(0) as the dividend) until C2 is cleared. (Note that while executing such a remainder-computation loop, a higher-priority interrupting routine that needs the FPU can force a context switch in-between the instructions in the loop.)

An important use of the FPREM instruction is to reduce the arguments of periodic functions. When reduction is complete, the instruction stores the three least-significant bits of the quotient in the C3, C1, and C0 flags of the FPU

status word. This information is important in argument reduction for the tangent function (using a modulus of π/4), because it locates the original angle in the correct one of eight sectors of the unit circle.

This instruction’s operation is the same in non-64-bit modes and 64-bit mode.

Operation:

D := exponent(ST(0)) – exponent(ST(1));
IF D < 64
    THEN
        Q := Integer(TruncateTowardZero(ST(0) / ST(1)));
        ST(0) := ST(0) – (ST(1) ∗ Q);
        C2 := 0;
        C0, C3, C1 := LeastSignificantBits(Q); (* Q2, Q1, Q0 *)
    ELSE
        C2 := 1;
        N := An implementation-dependent number between 32 and 63;
        QQ := Integer(TruncateTowardZero((ST(0) / ST(1)) / 2(D − N)));
        ST(0) := ST(0) – (ST(1) ∗ QQ ∗ 2(D − N));
FI;

FPU Flags Affected:

C0:
	Set to bit 2 (Q2) of the quotient.
C1:
	Set to 0 if stack underflow occurred; otherwise, set to least significant bit of quotient (Q0).
C2:
	Set to 0 if reduction complete; set to 1 if incomplete.
C3:
	Set to bit 1 (Q1) of the quotient.

Floating-Point Exceptions:

#IS:
	Stack underflow occurred.
#IA:
	Source operand is an SNaN value, modulus is 0, dividend is ∞, or unsupported format.
#D:
	Source operand is a denormal value.
#U:
	Result is too small for destination format.

Protected Mode Exceptions:

#NM:
	CR0.EM[bit 2] or CR0.TS[bit 3] = 1.
#MF:
	If there is a pending x87 FPU exception.
#UD:
	If the LOCK prefix is used.

Real-Address Mode Exceptions:

Same exceptions as in protected mode.

Virtual-8086 Mode Exceptions:

Same exceptions as in protected mode.

Compatibility Mode Exceptions:

Same exceptions as in protected mode.

64-Bit Mode Exceptions:

Same exceptions as in protected mode.



FPREM1 — Partial Remainder

Opcode	Instruction	    64-Bit Mode	    Compat/Leg Mode	    Description
D9 F5	FPREM1	        Valid	        Valid	            Replace ST(0) with the IEEE remainder obtained from dividing ST(0) by ST(1).

Description:

Computes the IEEE remainder obtained from dividing the value in the ST(0) register (the dividend) by the value in the ST(1) register (the divisor or modulus), and stores the result in ST(0). The remainder represents the following value:

Remainder := ST(0) − (Q ∗ ST(1))

Here, Q is an integer value that is obtained by rounding the floating-point number quotient of [ST(0) / ST(1)] toward the nearest integer value. The magnitude of the remainder is less than or equal to half the magnitude of the modulus, unless a partial remainder was computed (as described below).

This instruction produces an exact result; the precision (inexact) exception does not occur and the rounding control has no effect. The following table shows the results obtained when computing the remainder of various classes of numbers, assuming that underflow does not occur.

When the result is 0, its sign is the same as that of the dividend. When the modulus is ∞, the result is equal to the value in ST(0).

The FPREM1 instruction computes the remainder specified in IEEE Standard 754. This instruction operates differently from the FPREM instruction in the way that it rounds the quotient of ST(0) divided by ST(1) to an integer (see the “Operation” section below).

Like the FPREM instruction, FPREM1 computes the remainder through iterative subtraction, but can reduce the exponent of ST(0) by no more than 63 in one execution of the instruction. If the instruction succeeds in producing a remainder that is less than one half the modulus, the operation is complete and the C2 flag in the FPU status word is cleared. Otherwise, C2 is set, and the result in ST(0) is called the partial remainder. The exponent of the partial remainder will be less than the exponent of the original dividend by at least 32. Software can re-execute the instruction (using the partial remainder in ST(0) as the dividend) until C2 is cleared. (Note that while executing such a remainder-computation loop, a higher-priority interrupting routine that needs the FPU can force a context switch in-between the instructions in the loop.)

An important use of the FPREM1 instruction is to reduce the arguments of periodic functions. When reduction is complete, the instruction stores the three least-significant bits of the quotient in the C3, C1, and C0 flags of the FPU status word. This information is important in argument reduction for the tangent function (using a modulus of π/4), because it locates the original angle in the correct one of eight sectors of the unit circle.

This instruction’s operation is the same in non-64-bit modes and 64-bit mode.

Operation:

D := exponent(ST(0)) – exponent(ST(1));
IF D < 64
    THEN
        Q := Integer(RoundTowardNearestInteger(ST(0) / ST(1)));
        ST(0) := ST(0) – (ST(1) ∗ Q);
        C2 := 0;
        C0, C3, C1 := LeastSignificantBits(Q); (* Q2, Q1, Q0 *)
    ELSE
        C2 := 1;
        N := An implementation-dependent number between 32 and 63;
        QQ := Integer(TruncateTowardZero((ST(0) / ST(1)) / 2(D − N)));
        ST(0) := ST(0) – (ST(1) ∗ QQ ∗ 2(D − N));
FI;

FPU Flags Affected:

C0:
	Set to bit 2 (Q2) of the quotient.
C1:
	Set to 0 if stack underflow occurred; otherwise, set to least significant bit of quotient (Q0).
C2:
	Set to 0 if reduction complete; set to 1 if incomplete.
C3:
	Set to bit 1 (Q1) of the quotient.

Floating-Point Exceptions:

#IS:
	Stack underflow occurred.
#IA:
	Source operand is an SNaN value, modulus (divisor) is 0, dividend is ∞, or unsupported format.
#D:
	Source operand is a denormal value.
#U:
	Result is too small for destination format.

Protected Mode Exceptions:

#NM:
	CR0.EM[bit 2] or CR0.TS[bit 3] = 1.
#MF:
	If there is a pending x87 FPU exception.
#UD:
	If the LOCK prefix is used.

Real-Address Mode Exceptions:

Same exceptions as in protected mode.

Virtual-8086 Mode Exceptions:

Same exceptions as in protected mode.

Compatibility Mode Exceptions:

Same exceptions as in protected mode.

64-Bit Mode Exceptions:

Same exceptions as in protected mode.



FPTAN — Partial Tangent

Opcode	Instruction	    64-Bit Mode	    Compat/Leg Mode	    Description
D9 F2	FPTAN	        Valid	        Valid	            Replace ST(0) with its approximate tangent and push 1 onto the FPU stack.

Description:

Computes the approximate tangent of the source operand in register ST(0), stores the result in ST(0), and pushes a 1.0 onto the FPU register stack. The source operand must be given in radians and must be less than ±263. The following table shows the unmasked results obtained when computing the partial tangent of various classes of numbers, assuming that underflow does not occur.

ST(0) SRC	ST(0) DEST
−∞	        *
−F	        − F to + F
−0	        -0
+0	        +0
+F	        − F to + F
+∞	        *
NaN	        NaN

Table 3-33. FPTAN Results

F Means finite floating-point value.
* Indicates floating-point invalid-arithmetic-operand (#IA) exception.
If the source operand is outside the acceptable range, the C2 flag in the FPU status word is set, and the value in register ST(0) remains unchanged. The instruction does not raise an exception when the source operand is out of range. It is up to the program to check the C2 flag for out-of-range conditions. Source values outside the range − 263 to +263 can be reduced to the range of the instruction by subtracting an appropriate integer multiple of 2π. However, even within the range -263 to +263, inaccurate results can occur because the finite approximation of π used internally for argument reduction is not sufficient in all cases. Therefore, for accurate results it is safe to apply FPTAN only to arguments reduced accurately in software, to a value smaller in absolute value than 3π/8. See the sections titled “Approximation of Pi” and “Transcendental Instruction Accuracy” in Chapter 8 of the Intel® 64 and IA-32 Architectures Software Developer’s Manual, Volume 1, for a discussion of the proper value to use for π in performing such reductions.

The value 1.0 is pushed onto the register stack after the tangent has been computed to maintain compatibility with the Intel 8087 and Intel287 math coprocessors. This operation also simplifies the calculation of other trigonometric functions. For instance, the cotangent (which is the reciprocal of the tangent) can be computed by executing a FDIVR instruction after the FPTAN instruction.

This instruction’s operation is the same in non-64-bit modes and 64-bit mode.

Operation:

IF ST(0) < 263
    THEN
        C2 := 0;
        ST(0) := fptan(ST(0)); // approximation of tan
        TOP := TOP − 1;
        ST(0) := 1.0;
    ELSE (* Source operand is out-of-range *)
        C2 := 1;
FI;

FPU Flags Affected:

C1:
	Set to 0 if stack underflow occurred; set to 1 if stack overflow occurred.
    Set if result was rounded up; cleared otherwise.
    Set to 1 if outside range (−263 < source operand < +263); otherwise, set to 0.
C2, C0, C3:
	Undefined.

Floating-Point Exceptions:

#IS:
	Stack underflow or overflow occurred.
#IA:
	Source operand is an SNaN value, ∞, or unsupported format.
#D:
	Source operand is a denormal value.
#U:
	Result is too small for destination format.
#P:
	Value cannot be represented exactly in destination format.

Protected Mode Exceptions:

#NM:
	CR0.EM[bit 2] or CR0.TS[bit 3] = 1.
#MF:
	If there is a pending x87 FPU exception.
#UD:
	If the LOCK prefix is used.

Real-Address Mode Exceptions:

Same exceptions as in protected mode.

Virtual-8086 Mode Exceptions:

Same exceptions as in protected mode.

Compatibility Mode Exceptions:

Same exceptions as in protected mode.

64-Bit Mode Exceptions:

Same exceptions as in protected mode.
