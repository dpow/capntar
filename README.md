Cap'n Tar
=========

Cap'n Tar is back, and he's conquering the NES! With Wax!

# WIP

This game is a work in progress in the early stages of planning & design, and will only be updated infrequently until the basic game is satisfactory.

Build
-----

Make sure to have the `cc65` compiler suite installed and on your $PATH, and issue the following command(s) in your directory of choice (you can also use the pre-compiled version in `bin/capntar.nes`):

UNIX-like systems (& Windows with `make` installed):  

              $ git clone https://github.com/dpow/capntar.git && cd capntar/
              $ make

Windows/DOS:  

              > git clone https://github.com/dpow/capntar.git
              > cd .\capntar
              > ca65 -t nes capntar.asm -o capntar.o
              > ld65 -t nes capntar.o -o capntar.nes

### Dependencies
* `cc65` - "the 6502 compiler":  compiler suite targeting 65(C)02-based platforms. Includes an assembler (`ca65`), linker (`ld65`), C compiler (`cc65`), disassembler (`da65`), and other handy tools. Available free at http://www.cc65.org/.
* `GnuWin32` - port of GNU tools to modern Windows systems. If you're stuck on Windows, consider installing `make`, which will "make" compiling and cleaning much easier. Obtain from http://gnuwin32.sourceforge.net/. A handy auto-downloader-installer is available at http://sourceforge.net/projects/getgnuwin32/.
* `fceux` - excellent NES emulator with many debugging features. Other emulators will probably work just fine, but this is the one the game is being consistently tested against. NEStopia is also a good one, especially if you're on OSX. http://www.fceux.com/web/home.html

Play!
-----
Open your NES emulator of choice and load the capntar.nes ROM file! If you prefer to use the command line, enter the following from the `capntar/` directory:

CLI:  `fceux bin/capntar.nes`

Milestones
----------
* ~~Define basic game-state logic~~
* Make a simple test / debug screen where Cap'n Tar jumps & moves on player input
* Design & configure Title Screen
* Design sprites & level blocks
* Convert sprites & level blocks to pattern tables
* Configure basic empty level to test sprites & player actions

Legal
-----

### License

BSD 3-Clause License. See `LICENSE` for details.

### Credits

Cap'n Tar and all other Characters created by Caleb Powell, all rights reserved. The Characters are not covered under the LICENSE, and may not be re-used or otherwise reproduced without the express written consent of Caleb Powell.

Cap'n Tar Game designed and created by Caleb Powell and Dylan Powell, Copyright (c) 2012-2013, all rights reserved.
Cap'n Tar, its Designers and Creators, and any content herein are in no way affiliated with, endorsed by, or endorse Nintendo, the NES, or anything else remotely related, and neither ask for nor receive Revenue nor Compensation for this project. This Game was solely created for the purposes of self-education and self-enjoyment.

No lesser pandas were harmed in the making of this Game. http://en.wikipedia.org/wiki/Lesser_panda
