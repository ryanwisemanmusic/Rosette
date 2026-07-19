---
title: "elf-loader.zig: Header Offsets"
language: Zig
framework: processor
tags:
  - ELF_Processor
description: Below, EI_MAG0 to EI_MAG3 refer to the byte sequences used involving the identification of the file type. EI_CLASS is also apart of the byte sequence, and this identifies whether or not you are working with 32 or 64 bit files. EI_DATA is also apart of the byte sequence, and refers to the endianness that is assigned. So, whether or not we are dealing with big or little endian.
created: 2026-07-19
---

## Header Offsets

```
const EI_MAG0: u8 = 0;
const EI_MAG1: u8 = 1;
const EI_MAG2: u8 = 2;
const EI_MAG3: u8 = 3;
const EI_CLASS: u8 = 4;
const EI_DATA: u8 = 5;
```

## Links

[[loader explained]]