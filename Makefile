all:
	ca65 -t nes capntar.s -o capntar.o
	ld65 -t nes capntar.o -o capntar.nes

clean:
	rm capntar.o
	rm capntar.nes
