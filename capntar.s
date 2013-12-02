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

; Bits in 'buttons' are ordered: A, B, select, start, up, down, left, right.
BUTTON_A_PRESSED	= %10000000
BUTTON_B_PRESSED	= %01000000
BUTTON_SE_PRESSED	= %00100000	; Select
BUTTON_ST_PRESSED	= %00010000	; Start 
BUTTON_UP_PRESSED	= %00001000
BUTTON_DN_PRESSED	= %00000100
BUTTON_LE_PRESSED	= %00000010
BUTTON_RT_PRESSED	= %00000001

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
	sta $4016

	; Now controller status is available in $4016.

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
; Add delta-x and delta-y values to
; a character's current position.
; 
; Params: 
;	add_x - value to add to current X position.
;	add_y - value to add to current Y position.
;
.macro tile add_x, add_y
	lda ball_x
	adc add_x
	sta $00
	lda ball_y
	adc add_y
	sta $01
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
	lda #GameState::TITLE
	sta $00 		; Param for change_state - reflects initial game state
	jsr change_state

	; Reset VRAM address
	vram #0, #0

forever:
	jmp forever


;;;;;;;;;;;;;; Game Loop (NMI) ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
game_loop:
	lda game_state

@title:	bne @play
	jsr title_loop
	jmp cleanup

@play:	cmp #GameState::PLAYING
	bne @pause
	jsr play_loop
	jmp cleanup

@pause:	cmp #GameState::PAUSED
	bne @over
	jsr pause_loop
	jmp cleanup

@over:  cmp #GameState::GAMEOVER
	bne cleanup
	jsr game_over_loop

cleanup:
	lda #$00 		; Draw sprites
	sta $2003
	lda #$02
	sta $4014
	vram #0, #0 	; Clear VRAM Address
	rti


;;;;;;;;;;;;;; Subroutines ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

;
; Sets the game state
;
; Params:
;	$00 - The state to set
;
change_state:
	; Store the new game state
	lda $00
	sta game_state

@title:	cmp #GameState::TITLE
	bne @new_game

	; Disable NMI, sprites, and background
	lda #$00
	sta $2000
	sta $2001

	; Load the title screen
	jsr clear_sprites
	jsr draw_title

	; Wait for VBLANK
@wait:	bit $2002
	bpl @wait

	; Enable NMI
	lda #%10000000
	sta $2000

	; Enable background
	lda #%00001000
	sta $2001

	jmp @return

@new_game:
	cmp #GameState::NEW
	bne @lose_life

	; Disable NMI, sprites, and background
	lda #$00
	sta $2000
	sta $2001

	; Load sprites for main game play
	jsr clear_sprites
	jsr load_sprites

	; Reset the palette timer and paddle palette state
	lda #$00
	sta palette_timer
	sta paddle_state

	; Reset the ball dx, dy
	sta ball_dx
	sta ball_dy

	; Reset ball moving and game paused
	sta ball_moving

	; Reset lives to 3
	lda #3
	sta lives

	; Reset score to 0
	ldx #0
	lda #0
@score:	sta score, x
	inx
	cpx #8
	bne @score

	; Set the game state to "playing"
	lda #GameState::PLAYING
	sta game_state

	; Draw the game board
	jsr draw_board

	; Wait for VBLANK
@wait2:	bit $2002
	bpl @wait2

	; Enable NMI, sprites and background
	lda #%10000000
	sta $2000
	lda #%00011110
	sta $2001

	jmp @return

@lose_life:
	cmp #GameState::LOSE_LIFE
	bne @playing

	; Disable NMI
	lda #$00
	sta $2000

	; Decrement Lives
	dec lives
	ldx lives
	bne @game_continue

	; Lives == 0, game is now over
	lda #GameState::GAMEOVER
	sta game_state
	jmp @game_over

@game_continue:
	; Draw the update lives to the board
	jsr draw_lives

	; Reset ball and paddle position
	lda #$00
	sta ball_dx
	sta ball_dy
	sta ball_moving
	jsr load_sprites

	; Jump into the "playing state"
	lda #GameState::PLAYING
	sta game_state

	; Enable NMI
	lda #%10000000
	sta $2000

	jmp @return

@playing:
	cmp #GameState::PLAYING
	bne @paused

	; Swtich to color mode
	lda #%00011110
	sta $2001

	jmp @return

@paused:
	cmp #GameState::PAUSED
	bne @game_over

	; Switch to monochrome mode
	lda #%00011111
	sta $2001

	jmp @return

@game_over:
	; Disable NMI, sprites, and background
	lda #$00
	sta $2000
	sta $2001

	; Draw the game over screen
	jsr draw_game_over

	; Wait for vblank
@wait3:	bit $2002
	bpl @wait3

	; Enable the background and NMI
	lda #%10000000
	sta $2000
	lda #%00001000
	sta $2001

@return:
	rts


;;;;;;;;;;;;;; Drawing Subroutines ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;



;;;;;;;;;;;;;; Lookup & Math Subroutines ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

; Performs a 16-bit arithmetic shift left.
; 
; Params:
; 	$00 - Low byte of the 16-bit value operand
; 	$01 - High byte of the 16-bit value operand
; 	$02 - Shift operand
;
; Return:
; 	$00 - The low byte of the result
;	$01 - The high byte of the result
asl16:
	ldx $02
@loop:	asl $01
	asl $00
	bcc @cont
	inc $01
@cont:	dex
	bne @loop
	rts


; Performs an add with two 16-bit operands storing
; the result in the first operand.
;
; Params:
; 	$00 - Low byte of the first operand
; 	$01 - High byte of the first operand
; 	$02 - Low byte of the second operand
; 	$03 - High byte of the second operand
;
; Return:
; 	$00 - The low byte of the result
;	$01 - The high byte of the result
add16:
	clc
	lda $02
	adc $00
	sta $00
	lda $03
	adc $01
	sta $01
	rts


;
; Adds two 8-byte BCD values and stores the result in the first.
;
; Params:
;	$00 - Low byte to address of first operand
;	$01 - High byte to address of the first operand
;	$02 - Low byte to address of second operand
;	$03 - High byte to the address of the second operand
;
bcd_add:
	clc
	ldy #0
@loop:	lda ($00), y
	adc ($02), y
	cmp #10
	bne @skip
	adc #5
	and #$0f
	sta ($00), y
	iny
	cpy #8
	sec
	bne @loop
@skip:	sta ($00), y
	iny
	cpy #8
	bne @loop
	rts


; Find the tile in the nametable at the point (x, y).
;
; Params:
; 	$00 - x-coordinate
;	$01 - y-coordinate
;
; Return:
; 	A   - The value of the tile at that address
;	$00 - The low byte of the address
; 	$01 - The high byte of the address
get_tile:
	; Nab the x value and hold onto it
	ldy $00 

	; Calculate the offset into VRAM
	; Tile(x, y) = ($00, $01) = (y / 8) * 32 + (x / 8)

	; (y / 8) * 32 = (y & #$f8) << 2
	lda $01
	and #$f8
	sta $00
	lda #0
	sta $01
	lda #2
	sta $02
	jsr asl16

	; (x / 8)
	tya
	lsr
	lsr
	lsr

	; [(y/8) * 32] + (x/8)
	sta $02
	lda #0
	sta $03
	jsr add16


	; Find that tile in VRAM
	lda $01
	adc #$20
	sta $2006
	sta $01

	lda $00
	sta $2006

	lda $2007
	lda $2007

	rts


;;;;;;;;;;;;;; Palettes, Nametables, etc. ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

; All palettes & nametables are placeholders for the time being!

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
	; Ball (sprite 0)
	.byte (PADDLE_Y - $08), $4a, %00000001, $7c

	; Paddle
	.byte PADDLE_Y, $40, %00000000, $70
	.byte PADDLE_Y, $41, %00000000, $78
	.byte PADDLE_Y, $41, %01000000, $80
	.byte PADDLE_Y, $40, %01000000, $88

	; Lives Row Ball
	.byte $07, $4a, %00000001, $0e

title_attr:
	.byte $00, $00, $00, $00, $00, $00, $00, $00
	.byte $00, $00, $00, $00, $00, $00, $00, $00
	.byte $00, $00, $00, $00, $00, $00, $00, $00
	.byte $00, $00, $00, $00, $00, $00, $00, $00
	.byte $00, $00, $55, $55, $55, $55, $00, $00
	.byte $00, $00, $00, $00, $00, $00, $00, $00
	.byte $00, $00, $00, $00, $00, $00, $00, $00
	.byte $00, $00, $00, $00, $00, $00, $00, $00

game_over_attr:
	.byte $ff, $ff, $ff, $ff, $ff, $ff, $ff, $ff
	.byte $ff, $ff, $ff, $ff, $ff, $ff, $ff, $ff
	.byte $ff, $ff, $ff, $ff, $ff, $ff, $ff, $ff
	.byte $ff, $ff, $ff, $ff, $ff, $ff, $ff, $ff
	.byte $ff, $ff, $ff, $ff, $ff, $ff, $ff, $ff
	.byte $ff, $ff, $ff, $ff, $ff, $ff, $ff, $ff
	.byte $ff, $ff, $ff, $ff, $ff, $ff, $ff, $ff
	.byte $ff, $ff, $ff, $ff, $ff, $ff, $ff, $ff

board_attr:
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
score_text:		.asciiz "SCORE:"
game_over_text:	.asciiz "GAME OVER"


;;;;;;;;;;;;;; BCD Constants ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

bcd_zero:	.byte 0,0,0,0,0,0,0,0


;;;;;;;;;;;;;; Pattern Table (CHR-ROM) ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
.segment "CHARS"
;.include "include/title.s"		; $00 - $??
;.include "include/blocks.s"		; $?? - $??
;.include "include/capn.s"		; $?? - $??
;.include "include/enemies.s"		; $?? - $??
;.include "include/bosses.s"		; $?? - $??
;.include "include/concarne.s"		; $?? - $??
;.include "include/summerman.s"		; $?? - $??


;;;;;;;;;;;;;; Vectors ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
.segment "VECTORS"
.word 0, 0, 0, game_loop, reset, 0
