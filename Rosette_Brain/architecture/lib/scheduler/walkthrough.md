Applications that were primarily written for Windows/Linux usually has a big problem, the method of scheduling for threads is abysmal. If a process that gets spun up into its own thread is not perfectly handled for macOS, you meet a problem of deadlocking that becomes near impossible to fix internally in Xenia. 

Synchronous logging is fast at exposing problems, as it expects you to answer off of its demands sort of like how Zig demands you handle its errors. UI threading debugging has been a big pain under an async logger, with it impossible to fetch details about said thread.

On the outside, being able to observe the processes that are being executed on an application, and having a global shell, means I have a lot of freedom at runtime to intercept any problems at runtime and handle them accordingly. Rosette is incredibly powerful in this way. 

Adding my own improvements in how macOS handles threads means that I can poll information about why the thread is infinitely hanging and resolve the issues that way. In addition, I can also control the handoff and when this happens, which eliminates the issue of finding a solution that is program specific. 

A custom scheduler policy that aids in improving the ability for applications to run is integral in a system where you cannot control the contents of the source code. 