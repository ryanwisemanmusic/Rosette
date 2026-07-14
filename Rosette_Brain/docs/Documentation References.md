For x86, so much research was required to make this project work. Assembly luckily is well documented, even if it can be tough to find amazing resources.

The first is [Felix Cloutier x86 and amd64 instruction reference](https://www.felixcloutier.com/x86/), which is a fantastic introduction into many of the most common x86 instructions. I used this as the starting point of building my ISA layer. The process was to bring this documentation into Rosette as .md files, format them to look readable whilst in VSCode, and then have OpenCode implement the x86 to NEON conversion aspect. 
