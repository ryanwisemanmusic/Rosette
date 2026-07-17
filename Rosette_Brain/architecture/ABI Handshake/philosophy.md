The idea of an ABI handshake layer is because Rosette has an issue of trust. See when it comes to translating x86 to NEON, since we do not have another piece of hardware we can communicate with, as in, a Windows/Linux environment, that means we must take an interesting process of ensuring trust

This is by ensuring that macOS and Windows talk together and are on the same page by a method of verification. If for example, two OSses have a different concept of how big a piece of data can be, we need to be able to find mismatches. 

One of the biggest goals is to abide by nondeterministic behavior. Since we may be dealing with thousands of programs with all different approaches, it is crucial that hardcoded address handling (for example, in the context of decoding), is not relegated to certain behaviors, unless there is something very absolute that cannot be overwritten
