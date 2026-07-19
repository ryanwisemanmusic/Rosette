---
title: "optimize-memory.sh: sysctl vm.swapusage"
language: Shell
framework: Rosette
tags:
  - scripts
description: We use a sysctl approach after this to then go about checking any swaps, but fallback to vm_stat in case sysctl fails.
created: 2026-07-19
---

## optimize-memory.sh

```bash
if sysctl vm.swapusage 2>/dev/null; then
:

else
echo "Swap status unavailable in this sandbox"
echo ""
echo "using vm_stat instead:"
vm_stat

fi
```

## Links

[[optimize-memory]]