# Rosette

ANNOUNCEMENT [6/7/26]: THIS PROJECT AIMS FOR BROAD SYSTEMS SUPPORT THROUGH A VARIETY OF SOFTWARE TESTS, AND IS INTENDED FOR USE IN XENIA/XENIA CANARY EVENTUALLY. 

Apple announced for 2028, that it's dropping Rosetta 2. This significant announcement means that for macOS 28, Rosetta 2 will be relegated to only limited contexts, and this abandonment of x86 to ARM64 is why I am writing Rosette. Losing access to this software means many developers are in need of a replacement tool that integrates into current Rosetta 2 reliant projects. This framework project aims to provide support at a global shell level, with the aims of easy accessibility and a headache-less setup

Rosette is intended to not only translate x86/x64/DOS (and CPU Instructions) to ARM64, but also tackle win32 related code. Additional issues such as casting discrepancies, angle bracket discrepancies, and the headache of dealing with x86 platform requirements, will also be handled.

For UNLV CS218 Students:
This program is designed for Mac users to (eventually) run x86-64 code needed for this Assembly based class. At the moment, Version 0.04, the implementation of this feature is far from complete. This project lacks a battle-tested global shell

The included installer .dmg will configure your global shell to work invisibly under the hood, allowing the make command to trigger Rosette if it detects the typical x86-64 project scaffolding that is provided to CS218 students. No additional configuration should be required on your end, the goal is for this shell to run seamlessly without poisoning anything else configured in your shell. It is recommended that if you have a complex shell setup, you configure a profile in which Rosette installs to, or backup your current shell in case some edge case has not been accounted for.

Many x86-64 instructions are translated to ARM64 NEON, however, given that there are over 4000 instructions, there still are many missing integral instructions. Zig is used as a means of evaluating registers before and after function calls, and after each Assembly instruction, to ensure Windows and macOS are on the same page and that the x86-64 output is what NEON also gets. 

Here is how I recommend contacting me (which is on Reddit @): u/ryanwisemanmusic :: if you are dealing with any additional problems. 