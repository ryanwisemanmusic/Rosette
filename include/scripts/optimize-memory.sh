#!/bin/bash
# Preflight for large *virtual address-space* reservations on macOS.
# Xenia's 4 GiB reservation is sparse and does not require 4 GiB of RAM, SysV
# shared-memory tuning, manual swap creation, or elevated privileges.

set -eu

echo "=== System Memory Optimization ==="
echo "Current memory status:"
memory_pressure
echo ""
echo "Current swap status:"

if sysctl vm.swapusage 2>/dev/null; then
    :
else
    echo "Swap status unavailable in this sandbox"
    echo ""
    echo "using vm_stat instead:"
    vm_stat
fi

echo "Note: macOS uses automatic swap management via dynamic pager"
echo "Current swap files in /private/var/vm:"
ls -lh /private/var/vm/swapfile* 2>/dev/null || echo "No swap files found"

echo ""
echo "Checking disk space for swap operations..."
AVAILABLE_SPACE=$(df -k /System/Volumes/Data | tail -1 | awk '{print $4}')
REQUIRED_SPACE=$((16 * 1024 * 1024)) # 16GB in KB

if [ "$AVAILABLE_SPACE" -lt "$REQUIRED_SPACE" ]; then
    echo "WARNING: Less than 16GB available disk space for swap operations"
    echo "Available: $((AVAILABLE_SPACE / 1024 / 1024))GB, Required: 16GB"
else
    echo "Sufficient disk space available for swap operations: $((AVAILABLE_SPACE / 1024 / 1024))GB"
fi

echo ""
echo "Checking process address-space limit..."
ADDRESS_LIMIT=$(ulimit -v 2>/dev/null || echo unlimited)
if [ "$ADDRESS_LIMIT" != "unlimited" ] && [ "$ADDRESS_LIMIT" -lt 4194304 ]; then
    echo "ERROR: virtual-memory limit is below 4 GiB: ${ADDRESS_LIMIT} KiB"
    exit 1
fi
echo "Address-space limit: $ADDRESS_LIMIT"

echo ""
echo "Final memory status:"
memory_pressure
echo ""
echo "Final swap status:"

if sysctl vm.swapusage 2>/dev/null; then
    :
else
    echo "Swap status unavailable in this sandbox"
    echo ""
    echo "using vm_stat instead:"
    vm_stat
fi

echo ""
echo "=== Preflight Complete ==="
echo "No kernel changes are required. Rosette must route Xenia's anonymous"
echo "PROT_NONE reservation through its sparse virtual-memory manager."
