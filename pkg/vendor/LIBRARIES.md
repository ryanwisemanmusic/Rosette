# Rosetta vendored-library catalogue

This directory is the reproducible source baseline for third-party libraries
that Xenia depends on. Version, upstream commit, license, and source-tree hash
are recorded once in [`src/manifest.toml`](src/manifest.toml). The nine
`target.toml` files under `x86`, `ARM64`, and `PPC` contain only the
architecture/platform ABI and provider choice, so version drift cannot be
introduced by copying a number into one assembly flavor and forgetting the
other two.

## Handled in this pass

| Library | Pinned source | Xenia relationship | Status |
| --- | --- | --- | --- |
| Vulkan-Headers | 1.4.313, `409c16be` | Xenia build include; the same header baseline is used for Windows and macOS | Handled |
| Vulkan-Loader | 1.4.313, `fb786074` | Source fallback for Windows `vulkan-1.dll` and macOS `libvulkan.1.dylib` providers | Handled as source |
| MoltenVK | 1.4.2, `db660224` | Metal-backed macOS Vulkan ICD for both x86_64 and ARM64 target records | Handled as source |
| SDL2 | 2.32.2, `e11183ea` | Xenia builds it from source on Windows and consumes a system framework on macOS | Handled |
| Vulkan Memory Allocator | 3.2.1, `c788c521` | Vulkan allocation source used by the graphics path | Handled |

“Handled as source” is deliberate. The full source is present and hashed,
but this pass does not silently replace a system loader or Metal driver with a
newly built binary. That choice belongs to the runtime provider selector in
`lib` after ABI and architecture checks have passed.

## Xenia Vulkan facts

The Xenia checkout currently pins Vulkan-Headers 1.4.313 and uses the same
header path for all host platforms; there is no separate “Windows Vulkan
header version” in Xenia. Its instance default is Vulkan 1.0 and its documented
runtime minimum is Vulkan 1.0. A loader/ICD may negotiate a newer API after
enumeration. Therefore the checker keeps these facts separate:

1. build-time header/source identity;
2. runtime minimum and requested instance API;
3. the actual loader/ICD provider and its Mach-O architecture slices.

The current local macOS providers are detected rather than trusted. The audit
found multiple SDL/Vulkan header providers, including newer versions, and a
universal x86_64/arm64 Vulkan loader. Xenia should use the vendored Vulkan
include path, while the runtime provider remains subject to capability checks.

## Verification

Run the source, matrix, Xenia-submodule, host-provider, and cross-architecture
header audit with:

```sh
python3 tools/check_vendor_libraries.py \
  --xenia-root '/Volumes/2023 Drive/xenia/xenia'
```

The machine-readable result is written to
`.rosette/vendor-library-report.json`. `make vendor-audit` runs the same audit;
`make shell-update` includes it in the normal shell-helper gate. Add
`--strict` when source or Xenia working-tree drift should fail the command.
The current Xenia submodules have local edits, so the default audit reports
those edits as warnings while comparing their committed baseline exactly.

The Zig build also embeds this catalogue as the `rosette-vendored-library`
package. The next Rosetta process startup will add
`[PASS] vendor-library-contract` to `.rosette/rosette-pkg.log`; the filesystem
and provider audit remains an explicit tool because it is host I/O.
If the checker reports that Xenia's current package log predates this contract,
that is expected until the next startup; it is a warning rather than permission
to rewrite a generated run log by hand.

## Useful libraries still pending

These are visible in Xenia’s dependency graph but are not yet copied into the
catalogue:

- glslang, SPIRV-Tools, and SPIRV-Cross — shader translation and reflection;
- Vulkan-Utility-Libraries — shared Vulkan helper code;
- the exact MoltenVK external revisions listed in its `ExternalRevisions/`
  directory, if Rosetta needs to rebuild the ICD rather than consume the
  pinned source tree;
- FFmpeg and Xenia’s remaining audio/media support libraries;
- platform window/input providers beyond SDL2.

They should be added one source snapshot at a time, with a commit and tree
hash, after the graphics provider audit identifies a concrete need. The
current catalogue intentionally avoids claiming that a source mirror is a
working runtime replacement.
