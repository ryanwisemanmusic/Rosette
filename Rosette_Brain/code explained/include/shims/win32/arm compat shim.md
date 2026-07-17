When it comes to how Windows handles data types compared to macOS's ARM64 environment, there are a few small issues that may expand later on, especially when dealing with the low level. You cannot just assume that Apple and Windows know what the fuck they are referring to when you deal with any data types. There is zero-trust with regards to this

Microsoft defines a lot of their variable types under MSVC, aka the Microsoft Visual C++ compiler. And thus, the preprocessor macro that is used is:
```
_MSC_VER
```

Since macOS is far from capable of using this compiler, we use a preprocessor macro in this format, to specify that we are not using MSVC:
```arm_compat.h
#if !defined(_MSC_VER)
#endif
```

When defining variables, int64 and uint64, you must explicitly substantiate their sizes:
- int64 is represented as a long long
- uint64 is represented as an unsigned long long

Since the special flavor of int64 and uint64 are never defined, it's why things take the form of:
```arm-compat
#ifndef __int64

#define __int64 long long
```
and
```arm-compat.h
#ifndef __uint64

#define __uint64 unsigned long long
```

Likely, there are other MSVC related definitions I haven't substantiated, nor, found any documentation about. I'm making a tagged note about this as a growing list of TODOs (which will be most useful in knowing what else to handle)

#TODO: Find MSVC documentation about how the compiler works under the hood, in case there are specfic windows behaviors that are missing
