# Vendored source inventory

`src/manifest.toml` records Rosette's ABI/provider contracts. The separate
`canary.lock.json` records the exact Xenia Canary `third_party/`
dependency inventory at one upstream commit. The dependency sources live in
`sources/<library>/` (or a versioned subdirectory when Rosette already vendors
another version), alongside the other vendored packages. The Xenia repository
license is kept at `licenses/canary.txt`. Matching source trees such as
SDL 2.32.2 are shared instead of duplicated. This inventory is not an ABI
provider catalogue and does not make every dependency an active Rosette
runtime dependency.

Refresh it from an initialized Xenia checkout with:

```sh
python3 tools/vendor_guest_sources.py --xenia-root /path/to/xenia
```

Verify the pinned source hashes offline with `python3
tools/check_guest_vendor.py`; add `--xenia-root` to also compare the lock to the
checkout's committed tree and submodule gitlinks. The exporter reads committed
Git objects, so dirty/untracked Xenia files are not copied. Each dependency's
license files stay with its source. Dependencies without a license file are
explicitly marked for review in the lock; this inventory is not a legal
conclusion.
