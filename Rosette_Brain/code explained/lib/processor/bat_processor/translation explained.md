Windows .bat files convert into .cmd files, which means that the options regarding what can be contained in them is very much one that will require a lot of handling. So long as this is a launch means, it often is the case that we want to handle cases of this.

Now, it is highly unlikely that you'll ever deal with this regarding parsing .exe files, as all of it is wrapped together into tokens that you can parse through. However, for the sake of running Window applications that you have the source code to, it is just easier to parse these files and ensure that they work on macOS. It really isn't a big deal to do this anyways, given that your idea is just to interpret the code in question and create a macOS equivalent.

So lets break down some of the things that you might come across, and how to interpret these:
- @echo on: this means that you will be able to see the entire contents of the .bat file in question. This is extremely useful for debugging when you need to see a problematic section. So ensure that you test out what happens when echo is set to on.
- @echo off: this disables the ability for the .bat file to be read into your terminal unless an echo is explicitly mentioned. 
- GOTO: Whenever this is seen, you go to whatever section is marked with ':', albeit with whatever tag proceeds GOTO. For example, 'GOTO start', would jump to ':start'
- echo: These are done when you want to explicitly mention something to the terminal, even with echo turned off

#TODO: Convert .bat file processor from Python into Zig