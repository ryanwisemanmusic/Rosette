Rosette assembler references and normalization layers live here.

This folder is the workspace-owned home for assembler-dialect handling that
should stay separate from the raw `.rosette` reference drop. The current
focus is on:

- `aasm`: Rosette's dialect-agnostic assembly normalization layer
- MASM / Irvine32 compatibility notes for Win32 titles
- DOS-oriented MASM/FASM/NASM handling notes for 16-bit titles

The `.rosette/Assemblers` directory remains reference-only.

Current curation policy:

- `fasm/`: keep the assembler source tree and primary docs that define syntax,
  directives, formats, and macro behavior used for dialect detection.
- `masm/`: keep the reference manuals, README material, and curated include
  files that help model MASM/DOS/Win32 semantics.
- `nasm/`: keep the assembler, disassembler, macro, output-format, and
  instruction-definition source trees plus the user docs.

Intentionally removed from this workspace copy:

- installer disk images and setup payloads
- CI, test, packaging, NSIS, and editor-integration scaffolding
- upstream helper tools that do not improve Rosette dialect detection or
  translation behavior

Current prodder-facing assembler mappings:

- `PACMAN-x86`: MASM with Irvine32 profile
- `Rocket-Shooting`: MASM-style DOS profile
- `snax86`: NASM Win32 console profile
- `tetrisx86` DOS + Win32 variants: MASM-style profiles

Current invocation status in `make prodder`:

- `snax86`: real NASM invocation is enabled and validated before the host wrapper runs
- MASM-based suites: external invocation is requested, but currently falls back with
  an explicit host limitation note because the available MASM payloads are legacy
  DOS/Windows tools and are not directly runnable on this macOS host

All titles still run through Rosette’s translation/runtime layer after the
assembler validation phase.
