CA 	= ca65
LD 	= ld65
CL 	= cl65 

SOURCES_NES	= capntar.s 
OBJECTS_NES = capntar.o 
PROGRAM_NES = capntar
CFLAGS_NES	= -t nes -o $(OBJECTS_NES) 
LDFLAGS_NES	= -t nes -o $(PROGRAM_NES).nes  

SOURCES_SYMON	= t/test.s 
OBJECTS_SYMON	= t/test.o 
PROGRAM_SYMON 	= test
CFLAGS_SYMON	= -t none -o $(PROGRAM_SYMON).prg 

###############################################

# assemble the NES game
all: 
	$(CA) $(CFLAGS_NES) $(SOURCES_NES)
	$(LD) $(LDFLAGS_NES) $(OBJECTS_NES)

# assemble program for testing individual  
# subroutines separately in Symon 6502 simulator
test: 
	#$(CL) -t none -o test.prg t/test.s
	$(CL) $(CFLAGS_SYMON) $(SOURCES_SYMON) 

clean:
	rm -f *.o *.nes *.prg t/*.o 
