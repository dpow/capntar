capntar
=======

Cap'n Tar is back, and he's conquering the NES! With Wax!

# WIP

This game is a work in progress in the early stages of planning & design, and will only be updated infrequently until the basic game is satisfactory.

Build
-----

Make sure to have the cc65 compiler installed and on your $PATH, and issue the following command(s) in your directory of choice (you can also use the pre-compiled version in `bin/capntar.nes`):

UNIX-like systems:  

              $ git clone https://github.com/dpow/capntar.git && cd capntar/
              $ make

Windows/DOS:  

              > git clone https://github.com/dpow/capntar.git
              > cd .\capntar
              > ca65 -t nes capntar.asm -o capntar.o
              > ld65 -t nes capntar.o -o capntar.nes

Play!
-----
Open your NES emulator of choice and load the capntar.nes ROM file! If you prefer to use the command line:

CLI:  `fceux capntar.nes`

Legal
-----

### License

BSD 3-Clause License. See `LICENSE` for details.

### Credits

Cap'n Tar and all other characters created by Caleb Powell, all rights reserved.

Cap'n Tar Game designed and created by Caleb Powell and Dylan Powell, Copyright (c) 2012-2013, all rights reserved.
Cap'n Tar, its Designers and Creators, and any content herein are in no way affiliated with, endorsed by, or endorse Nintendo, the NES, or anything else remotely related, and neither ask for nor receive Revenue nor Compensation for this project. This Game was solely created for the purposes of self-education and self-enjoyment.

No lesser pandas were harmed in the making of this Game. http://en.wikipedia.org/wiki/Lesser_panda
