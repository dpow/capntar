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
; Load high and low bytes into VRAM,
; using a value stored at a specific address.
;
; Params:
;	address - the address to retrieve values from
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

	ldx #$08 				; Use X as our bit rotation counter.
@__dump_bits_loop:
	lda $4016
	lsr A 					; Move bit 0 in A into Carry.
	rol buttons 			; Move Carry into bit 0 in 'buttons'.
	dex 
	bne @__dump_bits_loop	; Do this until Zero flag is set.

	; Now we have our controller status stored in 'buttons', we are done.

	pla 			; Pop X then A off stock
	tax 
	pla 
.endmacro


;
; Set the params for finding the tile in 
; nametable at point (x, y).
; 
; Params: 
;	add_x - value to add to X position.
;	add_y - value to add to Y position.
;
.macro tile add_x, add_y
	lda ball_x
	adc add_x
	sta $00 			; Param for X-coordinate in get_tile
	lda ball_y
	adc add_y
	sta $01 			; Param for Y-coordinate in get_tile
	jsr get_tile
.endmacro


;
; Store a single 16-bit value in zero-page.
;
; Params:
;	value - the 16-bit value to store.
;
.macro addr value 
	pha
	lda #.LOBYTE(value)
	sta $00
	lda #.HIBYTE(value) 
	sta $01
	pla
.endmacro


;
; Store two 16-bit values in zero-page.
; 
; Params:
;	v1 - the first 16-bit value to store.
;	v2 - the second 16-bit value to store.
.macro addr2 v1, v2
	pha
	lda #.LOBYTE(v1)
	sta $00
	lda #.HIBYTE(v1)
	sta $01
	lda #.LOBYTE(v2)
	sta $02
	lda #.HIBYTE(v2)
	sta $03
	pla
.endmacro


;
; Load the specified attribute table. (??? - verify)
;
; Params:
;	label - the name of the attribute table to laod.
;
.macro load_attrs label
.scope
	vram #$23, #$c0
	ldx #$00
@__load_attrs_loop:	
	lda label, x
	sta $2007
	inx
	cpx #$40
	bne @__load_attrs_loop
.endscope
.endmacro


;
; Get the block row. (??? - verify)
; (Not sure whether "block_row" refers to
;  row # of blocks that are hit by ball or
;  a "block" or tile in namespace or pattern table.)
;
.macro block_row hi, lo
.scope
	vram hi, lo
	ldx #$0e
@__block_row_loop:
	lda #$42
	sta $2007
	lda #$43
	sta $2007
	dex
	bne @__block_row_loop
.endscope
.endmacro


;;;;;;;;;;;;;; Main Program ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
main:
	; Load the default palette
	jsr load_palette

	; Set the game state to the title screen
	lda #GameState::PLAYING
	sta $00 		; Param for change_state - reflects initial game state
	jsr change_state

	; Reset VRAM address
	vram #0, #0

forever:
	jmp forever


;;;;;;;;;;;;;; Game Loop (NMI) ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
game_loop:
	lda game_state

@play:	
	cmp #GameState::PLAYING
	;bne @pause
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
	lda buttons
	and #%10000000
	beq @no_button_pressed
	

@no_button_pressed:

	rts


;
; Sets the game state
;
; Params:
;	$00 - The state to set
;
;change_state:
;	; Store the new game state
;	lda $00
;	sta game_state
;
;@title:	cmp #GameState::TITLE
;	bne @new_game
;
;@return:
;	rts


;
;



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
; Clear nametable memory
;
clear_nametable:
	ldx #$00
	ldy #$04
	lda #$FF
	vram #$20, #$00
@loop:	
	sta $2007
	inx
	bne @loop
	dey
	bne @loop
	rts


;
; Draw off-screen part of level
;



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

sprites:
	; Cap'n Tar (sprite 0)
	.byte (PADDLE_Y - $08), $4a, %00000001, $7c

	; Paddle
	.byte PADDLE_Y, $40, %00000000, $70
	.byte PADDLE_Y, $41, %00000000, $78
	.byte PADDLE_Y, $41, %01000000, $80
	.byte PADDLE_Y, $40, %01000000, $88

	; Lives Row Ball
	.byte $07, $4a, %00000001, $0e

level_attr:
	.byte $0f, $0f, $0f, $0f, $0f, $0f, $0f, $0f
	.byte $84, $a5, $a5, $a5, $a5, $a5, $a5, $21
	.byte $84, $a5, $a5, $a5, $a5, $a5, $a5, $21
	.byte $84, $a5, $a5, $a5, $a5, $a5, $a5, $21
	.byte $84, $a5, $a5, $a5, $a5, $a5, $a5, $21
	.byte $84, $a5, $a5, $a5, $a5, $a5, $a5, $21
	.byte $84, $a5, $a5, $a5, $a5, $a5, $a5, $21
	.byte $84, $a5, $a5, $a5, $a5, $a5, $a5, $21


;;;;;;;;;;;;;; Strings ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

title_text:		.asciiz "CAP'N TAR" 
game_over_text:	.asciiz "GAME OVER"


;;;;;;;;;;;;;; BCD Constants ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

;bcd_zero:	.byte 0,0,0,0,0,0,0,0


;;;;;;;;;;;;;; Pattern Table (CHR-ROM) ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
.segment "CHARS"
;.include "include/title.s"			; $00 - $??
;.include "include/capn.s"			; $?? - $??
;.include "include/enemies.s"		; $?? - $??
;.include "include/bosses.s"		; $?? - $??
;.include "include/concarne.s"		; $?? - $??
;.include "include/summerman.s"		; $?? - $??
.include "include/font.s"			; $00 - $65 (101 tiles)


;;;;;;;;;;;;;; Vectors ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
.segment "VECTORS"
.word 0, 0, 0, game_loop, reset, 0
