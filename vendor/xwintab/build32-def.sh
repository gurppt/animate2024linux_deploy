#!/bin/bash

# winegcc -m32 -I/usr/include/wine/wine/windows produces a normal native ELF shared object that has additional
# information embedded in it that allows its exports to be loaded by Windows
# code. It will feed the '.spec' file to the confusingly named 'winebuild' tool
# which generates some assembly source code with the needed information.
winegcc -m32 -I/usr/include/wine/wine/windows -o XWinTabHelper.dll.so -shared -O2 src/XWinTabHelper.c src/XWinTabHelper.dll.spec -lxcb -lxcb-xinput

# The actual wintab DLL is written as a Windows DLL to avoid relying on
# any wine interals. Therefore you also need the mingw cross compiler.
i686-w64-mingw32-gcc -shared -O2 -o wintab32.dll src/WinTab.c src/wintab32.def
