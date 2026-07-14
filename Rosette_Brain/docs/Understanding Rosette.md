Rosette is an x86 to NEON compiler project that was developed primarily for use with Xenia Canary, however, was created to replace Apple's Rosetta 2. Apple will be getting rid of this in 2028, and its why I'm going through the hassle of making this work.

To understand why Rosette, you have to wonder why Rosetta 2 just isn't good enough. Rosetta 2 is a lazy DBT (dynamic binary translator). Sure, it may work with AVX/SSE, and all of that prior to its discontinuation, but it is a lazy implementation. Because being able to translate x86 to NEON is just half the job, and most programs have to deal with incredibly complex x86 interactions. 

So Rosette already was starting at an even harder problem, true x86 integration. Assembly is not as simple as just implementing translations, but how they interact with memory and interface within the low level. This means at every aspect, our program must be able to handle these contexts in which something is unsupported. 

Xenia Canary, especially the PR I'm finishing, requires a strong compatibility layer, and hence, is the best choice of software as the first substantial program to support. 
