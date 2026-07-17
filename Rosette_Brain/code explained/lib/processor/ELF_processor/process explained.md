The foundational aspects to ELF object files is that they take in a series of system calls:
- SYS_close
- SYS_creat
- SYS_exit
- SYS_arch_prctl
- SYS_gettid
- SYS_open
- SYS_read
- SYS_write

These are the most commonly used ones. Over 400 various system calls do exist, which means that this is rather incomplete part of the code.

#TODO :  Implement a separate file to handle all syscalls that an ELF object file might stumble into
