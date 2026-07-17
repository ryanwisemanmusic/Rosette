Whenever you deal with a zero-trust DBT that needs to maximize the amount of instructions executed, you must ensure that Zig is never put in this state:
```output
Debug (default) Optimations off, safety on
```

Turning on safety, and turning optimizations, means that your program will then run at about 180k instructions per second. Safety on is only useful when you do not mind a lengthy runtime. Safety on defeats the purpose of how the DBT works when you are trying to run x86 intensive programs. 

Below is the most integral piece of optimization, ensuring that we always are speedy like Sonic:
```Makefile
ROSETTE_RUNTIME_OPTIMIZE ?= ReleaseFast
```

