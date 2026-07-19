---
title: optimize-memory.sh- ls -lh /private/var/vm/swapfile*
language: Shell
framework: Rosette
tags:
  - scripts
description: When we list all the files contained /private/var/vm, we do this because the swap files aren't located in any other location. This is the standard practice on where swap files are stored on macOS.
created: 2026-07-19
---

## optimize-memory.sh- ls -lh /private/var/vm/swapfile*

```bash
echo "Note: macOS uses automatic swap management via dynamic pager"
echo "Current swap files in /private/var/vm:"
ls -lh /private/var/vm/swapfile* 2>/dev/null || echo "No swap files found"
```

## Links

- 