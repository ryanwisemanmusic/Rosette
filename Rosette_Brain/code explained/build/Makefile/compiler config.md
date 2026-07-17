Currently, the approach is that we use clang as the means of compiling our code

``` Makefile
CC ?= clang

CXX ?= clang++

CFLAGS ?= -Wall -Wextra -Wno-ignored-attributes
```

However, the biggest feature that we need to add at some point is the ability to select the compiler based off of what is detected. At the moment, this isn't implemented and is a big problem to future programs in which we cannot be deterministic in what we choose.

#TODO: Create a non-deterministic compiler interpreter. This will be able to exact what compiler to use and then ensure we are routing all our code into it


