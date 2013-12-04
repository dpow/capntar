;;;;;;;;;;;;;; Cap'n Tar ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;;;;;;;;;;;; Assemble with ca65. ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;;;;;;;;;;;; See LICENSE and README.md for licensing terms. ;;;;;;;;;;;;;;;;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

;;;;;;;;;;;;;; Header / Startup Code ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
.segment "HEADER"
	.byte 	"NES", $1A		; iNES header identifier
	.byte 	2				; 2x 16KB PRG code
	.byte 	1 				; 1x  8KB CHR data
	.byte	$01, $00		; Mapper 0, vertical mirroring

.segment "STARTUP"			; required by assembler to find entry point

.segment "CODE"

;
; Reset subroutine
; Largely hardware-dependent - do not alter
; 
reset:
	sei				; Disable IRQs
	cld				; Disable decimal mode 
	ldx #$40
	stx $4017		; Disable APU frame IRQ
	ldx #$FF		; Set up stack
	txs				; .
	inx				; Now X = 0
	stx $2000		; Disable NMI
	stx $2001		; Disable rendering
	stx $4010		; Disable DMC IRQs

@wait:				; Wait for VBLANK
	bit $2002
	bpl @wait

@clear:				; Clear RAM
	lda #$00
	sta $0000, x
	sta $0100, x
	sta $0200, x
	sta $0300, x
	sta $0400, x
	sta $0500, x
	sta $0600, x
	sta $0700, x
	inx
	bne @clear

@wait2: 			; Wait for VBLANK (again)
	bit $2002		
	bpl @wait2


;;;;;;;;;;;;;; Global Variables ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

; Constants (many of these are placeholders for now)
GRAV_MAX			= 3 		; Force = mass * acceleration
GRAV_INTERVAL		= 10
MOVE_INC_INTERVAL	= 10
MOVE_INC_START		= 6
MOVE_DEC_INTERVAL	= 3

PLAYER_ATTACK_DEL	= 5			; Delay before player attack hits 
PLAYER_JUMP_DEL		= 3			; Delay before player jumps

PLAYER_HPT_MAX		= 5	

; Variables
game_state:			.res 1 		; Current master game state
score:	 			.res 8 		; Score in BCD form (8-bytes)
buttons:			.res 1 		; Status of controller buttons

player_hpt:			.res 1 		; Player current hitpoints
player_x:	 		.res 1 		; Player x-coordinate
player_y:			.res 1 		; Player y-coordinate 

; Game States
.enum GameState
	;TITLE
	;NEW
	PLAYING
	;LOSE_LIFE
	;PAUSED
	;GAMEOVER
.endenum


;;;;;;;;;;;;;; Macros ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

; 
; Load input params hi and lo into VRAM, 
; using separately specified high and low bytes.
;
; Params:
;	hi - high byte to load into VRAM 
;	lo - low byte to load into VRAM 
;
.macro vram hi, lo 	
	pha 					; Push Accumulator first just in case...
	lda hi
	sta $2006
	lda lo
	sta $2006
	pla 					; ... pop it back off when we are done.
.endmacro


;
; Load a value stored at a specific address into VRAM.
;
; Params:
;	address - the address of value to load into VRAM
;
.macro vram_addr address 
	pha
	lda #.HIBYTE(address)
	sta $2006
	lda #.LOBYTE(address)
	sta $2006
	pla
.endmacro


;
; Strobe the controllers (i.e. get their input).
; Controller data is accessed at $4016 and $4017, 
; write 1 and 0 to $4016 to fetch their data.
;
; Returns:
;	Value of 1 for each button pressed in variable 'buttons'.
;	Bits in 'buttons' are ordered: A, B, select, start, up, down, left, right.
;	This order is the reverse of the original bit order.
;
.macro strobe 
	pha 			; Push A, then X to stack
	txa
	pha
	
	lda #$01 		; Fetch controller data
	sta $4016
	lda #$00
	sta $4016		; Now controller status is available in $4016.

;	ldx #$08 				; Use X as our bit rotation counter.
;@__dump_bits_loop:
;	lda $4016
;	lsr A 					; Move bit 0 in A into Carry.
;	rol buttons 			; Move Carry into bit 0 in 'buttons'.
;	dex 
;	bne @__dump_bits_loop	; Do this until Zero flag is set.
;
;	; Now we have our controller status stored in 'buttons', we are done.

	pla 			; Pop X then A off stock
	tax 
	pla 
.endmacro


;;;;;;;;;;;;;; Main Program ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
main:
	; Load the default palette
	jsr load_palette

	; Reset VRAM address
	vram #0, #0

forever:
	jmp forever


;;;;;;;;;;;;;; Game Loop (NMI) ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
game_loop:
	jsr clear_sprites
	jsr load_sprites
	jsr play_loop
	jmp cleanup

cleanup:
	lda #$00 		; Draw sprites
	sta $2003
	lda #$02
	sta $4014
	vram #0, #0 	; Clear VRAM Address
	rti


;;;;;;;;;;;;;; Subroutines ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

;
; Game loop code for the main game
;
play_loop:
	strobe 		; Strobe the controller

	; A - Make the Cap'n jump
button_a:
	lda #$01
	and $4016
	beq @return 
	lda #$01 
	sta player_y

@return: 
	rts


;;;;;;;;;;;;;; Drawing Subroutines ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

;
; Clear sprite memory
;
clear_sprites:
	lda #$ff
	ldx #$00
@clear:	
	sta $0200, x
	inx
	bne @clear
	rts


;
; Load sprites into sprite memory
;
;
load_sprites:
	ldx #$00 			; Start at 0
@loop:	
	lda sprites, x 		; Load data from address (sprites + x)
	sta $0200, x 		; Store data into RAM address ($200 + x)
	inx 
	cpx #$0f  			; Compare X to max number of sprite bytes to load (4 x # of sprites)
	bne @loop 			; Keep loading into RAM until all tiles are loaded
	rts


;;;;;;;;;;;;;; Lookup & Math Subroutines ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;


;;;;;;;;;;;;;; Palettes, Nametables, etc. ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

palette:
	; Background
	.byte $0f, $03, $19, $00
	.byte $0f, $00, $10, $20
	.byte $0f, $09, $19, $29
	.byte $0f, $20, $10, $00
	; Sprites
	.byte $0f, $00, $08, $10
	.byte $0f, $06, $16, $27
	.byte $0f, $00, $00, $00
	.byte $0f, $00, $00, $00


; Each sprite has 4 bytes of data assinged to it:
; vertical position, tile #, tile attributes, and horizontal position.
; Y-pos:   $00 is the top of the screen, > $EF is off the bottom of screen.
; Tile:	   tile number (0 - 256) for the graphic to be taken from pattern table.
; Attr.s:  color and displaying info (mirroring, priority, palette).
; X-pos:   $00 is left side of screen, > $F9 is off right of screen.
; To edit Sprite 0, change bytes $0200-0203; Sprite 1 is $0204-0207, etc.
sprites:
	;      Y,   T,   A,   X
	; Sprite 0 - Cap'n Tar
	.byte $80, $00, $00, $80		; Capn's left head half
	.byte $80, $01, $00, $88		; Capn's right head half
	.byte $88, $02, $00, $80		; Capn's left leg
	.byte $88, $03, $00, $88		; Capn's right leg


;;;;;;;;;;;;;; Strings ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

;title_text:		.asciiz "CAP'N TAR" 
;game_over_text:	.asciiz "GAME OVER"


;;;;;;;;;;;;;; BCD Constants ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

;bcd_zero:	.byte 0,0,0,0,0,0,0,0


;;;;;;;;;;;;;; Pattern Table (CHR-ROM) ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
.segment "CHARS"
.include "include/capn.s"			; $00 - $04 (4 tiles)
;.include "include/enemies.s"		; $?? - $??
;.include "include/bosses.s"		; $?? - $??
;.include "include/concarne.s"		; $?? - $??
;.include "include/summerman.s"		; $?? - $??
.include "include/font.s"			; $00 - $65 (101 tiles)
;.include "include/title.s"			; $00 - $??


;;;;;;;;;;;;;; Vectors ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
.segment "VECTORS"
.word 0, 0, 0, game_loop, reset, 0
