Programs can often allocate large amounts of memory that exceeds what macOS can keep up with. Because of that, we must ensure that Rosette can handle large amounts of memory and check the health of our system to do so

```Bash
echo "=== System Memory Optimization ==="
echo "Current memory status:"
memory_pressure
```

'memory_pressure' is a macOS command-line utility that helps analyze the state of your memory, and it is a very useful in the health of your system. Analyzing memory pressure is a key part of seeing where things in the pipeline go wrong when they appear, and hence, why it's in the .sh file.

We use a sysctl approach after this to then go about checking any swaps, but fallback to vm_stat in case sysctl fails. 

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

Now, when we list all the files contained /private/var/vm, we do this because the swap files aren't located in any other location. This is the standard practice on where swap files are stored on macOS. I do not know where these are typically are stored on Windows and Linux, given that the optimize memory script is macOS only. And then if we find none, we return that we've found none:
```bash
echo "Note: macOS uses automatic swap management via dynamic pager"
echo "Current swap files in /private/var/vm:"
ls -lh /private/var/vm/swapfile* 2>/dev/null || echo "No swap files found"
```

The next comes down to memory allocations and ensuring that we have enough for what the program demands. Most programs will never be at a point where the amount of memory you need will ever run out. So, let go into how and why the below code was chosen regarding the snippet below this region:
```bash
echo "Checking disk space for swap operations..."
```

The available space is something we check as a means to compare against. Whether this be your internal drive, your external drive, we reference '/System/Volumes/Data' since this is the overall internal path that your storage location takes up. 'df -k' is a command that checks how much disk is free in kilobytes. The tail -1 just ensures that you don't include the header whenever you pull this. We also print the 4th column because 3rd column contains used space
```bash
AVAILABLE_SPACE=$(df -k /System/Volumes/Data | tail -1 | awk '{print $4}')
```

This is just letting the system know that we are preserving 16GB as a mandatory requirement:
```bash
REQUIRED_SPACE=$((16 * 1024 * 1024)) # 16GB in KB
```

On this, we do a comparison between AVAILABLE SPACE AND REQUIRED SPACE. If our AVAILABLE SPACE is less than our REQUIRED SPACE, then we complain to the user/dev, but otherwise, they are clear to go.

#TODO: Consider putting an exit here if we get to applications in which this becomes a significant problem
```bash
if [ "$AVAILABLE_SPACE" -lt "$REQUIRED_SPACE" ]; then
echo "WARNING: Less than 16GB available disk space for swap operations"
echo "Available: $((AVAILABLE_SPACE / 1024 / 1024))GB, Required: 16GB"

else
echo "Sufficient disk space available for swap operations: $((AVAILABLE_SPACE / 1024 / 1024))GB"

fi
```

We create an address space limit checker. Then, if its the case that we aren't using unlimited address space and the amount of storage that we have is under 4 GB, we complain because it is likely that Rosette is being used in a location with far too little space. Keep in mind, whilst Rosette does only package to about 40-50MB signed, we do want some overhead for the potential of storing addresses. 
```bash
echo "Checking process address-space limit..."
ADDRESS_LIMIT=$(ulimit -v 2>/dev/null || echo unlimited)
if [ "$ADDRESS_LIMIT" != "unlimited" ] && [ "$ADDRESS_LIMIT" -lt 4194304 ]; then
echo "ERROR: virtual-memory limit is below 4 GiB: ${ADDRESS_LIMIT} KiB"
exit 1

fi
```

NOTE: While I do understand this may make some people irritated regarding the minimum demands I have, feel free to allocate to a smaller size if you truly are that annoyed. 

Something I do think that is necessary eventually is improve the optimization of memory to autoscale if we ever need it. It is highly unlikely that we will ever use more than 16GB of memory, however, we want to ensure that REQUIRED_SPACE scales if we hit an instance where the amount of memory is too little. For example, AAA titles likely require large amounts of memory allocations, and while we are far from ever touching those, I do think its an important: "what if" case worth addressing.

#TODO: Allow for REQUIRED_SPACE to autoscale if the reserved space needed exceeds 16 GB
