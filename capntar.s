;;;;;;;;;;;;;; Cap'n Tar ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;;;;;;;;;;;; Code template based on NES-Breakout by rsandor, ;;;;;;;;;;;;;;;;
;;;;;;;;;;;;;; available at https://github.com/rsandor/NES-Breakout. ;;;;;;;;;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;;;;;;;;;;;; Assemble with ca65. ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;;;;;;;;;;;;;; See LICENSE and README.md for licensing terms. ;;;;;;;;;;;;;;;;;
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

;;;;;;;;;;;;;; Header / Startup Code ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
.segment "HEADER"
	.byte 	"NES", $1A		; iNES header identifier
	.byte 	2			; 2x 16KB PRG code
	.byte 	1 			; 1x  6KB CHR data
	.byte	$01, $00		; Mapper 0, vertical mirroring

.segment "STARTUP"

.segment "CODE"

; Use this routine as a ".include" if you don't want it in the main file
reset:
;.include "include/reset.s"
	sei			; Disable IRQs
	cld			; Disable decimal mode 
	ldx #$40
	stx $4017		; Disable APU frame IRQ
	ldx #$FF		; Set up stack
	txs				; .
	inx				; Now X = 0
	stx $2000		; Disable NMI
	stx $2001		; Disable rendering
	stx $4010		; Disable DMC IRQs

@wait:	bit $2002		; Wait for VBLANK
	bpl @wait

@clear:	lda #$00		; Clear RAM
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

@wait2: bit $2002		; Wait for VBLANK (again)
	bpl @wait2


;;;;;;;;;;;;;; Macros ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

; Define macros here...
.macro vram hi, lo
	pha
	lda hi
	sta $2006
	lda lo
	sta $2006
	pla
.endmacro

.macro vram_addr address
	pha
	lda #.HIBYTE(address)
	sta $2006
	lda #.LOBYTE(address)
	sta $2006
	pla
.endmacro

.macro strobe
	pha
	lda #$01
	sta $4016
	lda #$00
	sta $4016
	pla
.endmacro

.macro tile add_x, add_y
	lda ball_x
	adc add_x
	sta $00
	lda ball_y
	adc add_y
	sta $01
	jsr get_tile
.endmacro

.macro addr label
	pha
	lda #.LOBYTE(label)
	sta $00
	lda #.HIBYTE(label)
	sta $01
	pla
.endmacro

.macro addr2 l1, l2
	pha
	lda #.LOBYTE(l1)
	sta $00
	lda #.HIBYTE(l1)
	sta $01
	lda #.LOBYTE(l2)
	sta $02
	lda #.HIBYTE(l2)
	sta $03
	pla
.endmacro

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


;;;;;;;;;;;;;; Global Variables ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

;.include "include/vars.s"	; Uncomment once variables are migrated

game_state 		= $0300 ; Master game states
start_down 		= $0301 ; Whether or not start was down last frame

player_hpt		= $0302	; Player hitpoints

score 			= $0308 ; Score in BCD form (8-bytes)

; Player position
player_x = $0203
player_y = $0200

; Enemy position
;enemy_x = $0207
;enemy_y = $0205

; Constants (zero-page memory values)
ATTACK_DELAY	= $0b	; Delay in player's attack - decreases with better weapons
JUMP_DELAY	= $1b	; Delay in player's jump - decreases with better weapons
PLAYER_HPT_MAX	= $2b	; Player max hitpoints

; Game States
.enum GameState
	TITLE
	NEW
	PLAYING
	LOSE_LIFE
	PAUSED
	GAMEOVER
.endenum

; Player states
.enum PlayerState
	ALIVE
	HIT
	DYING
	DEAD
.endenum


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



;;;;;;;;;;;;;; Palettes, Nametables, etc. ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;



;;;;;;;;;;;;;; Strings ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;



;;;;;;;;;;;;;; BCD Constants ;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;



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
.word 0, 0, 0, nmi, reset, 0
