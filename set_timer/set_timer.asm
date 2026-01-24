;======================================================================
; V53 Internal Peripheral Initialization
; Enable TCU (Timer Counter Unit) & Set Base Address
;======================================================================

BITS 16
ORG 0x0000
cpu 186

; --- システム制御レジスタ ---
OPSEL_ADDR  EQU  0x0FFFD        ; OPSEL: Internal Peripheral Selection
TULA_ADDR   EQU  0x0FFF9        ; TULA:  Relocation Register

; --- TCUレジスタ ---
TM0_CNT     EQU  0x1270         ; Timer 0 Counter
TM1_CNT     EQU  0x1271         ; Timer 1 Counter
TM2_CNT     EQU  0x1272         ; Timer 2 Counter
TM_CTL      EQU  0x1273         ; Timer Control
TCKS_REG    EQU  0x0FFF0        ; Clock Selection

; --- 分周比設定 ---
; Input 1.2288 MHz / Target 307.2 kHz = 4.0
DIV_LOW     EQU  4
DIV_HIGH    EQU  00H

SECTION .text

;----------------------------------------------------------------------
; Init_V53_Peripherals:
; 1. OPSEL で TCU を有効化
; 2. TULA  で TCU のI/O アドレスを 1270h に配置
; 3. タイマーを Mode 3 (矩形波) に設定しクロック出力開始
;----------------------------------------------------------------------
Init_V53_Peripherals:
    ;------------------------------------------
    ; 1. 内蔵周辺機能の有効化 (OPSEL)
    ;------------------------------------------
    mov  dx, OPSEL_ADDR
    in   al, dx          ; 現在の値を読み出す（安全のため）
    or   al, 00000100b   ; Bit 2 TCU (Timer) Enableをセット
    out  dx, al

    ;------------------------------------------
    ; 2. レジスタ配置アドレスの設定 (TULA)
    ;------------------------------------------
    mov dx, TULA_ADDR
    mov al, 0x70        ; 下位アドレス
    out dx, al

    ;------------------------------------------
    ; 3. TCKS: タイマクロック入力選択
    ;------------------------------------------
    mov  dx, TCKS_REG
    mov  al, 00011100b  ; 全Timer: TCLK端子入力使用
    out  dx, al
    
    ;------------------------------------------
    ; 3. タイマー初期化 (Mode 3 / Square Wave)
    ;------------------------------------------
    mov  dx, TM_CTL

    ; --- Timer 0 Setup ---
    mov  al, 0x36         ; Mode 3, Binary, LSB/MSB
    out  dx, al
    
    ; --- Timer 1 Setup ---
    mov  al, 0x76         ; Mode 3, Binary, LSB/MSB
    out  dx, al

    ; --- Timer 2 Setup ---
    mov  al, 0xB6        ; Mode 3, Binary, LSB/MSB
    out  dx, al

    ;------------------------------------------
    ; 4. カウンタ値 (分周比) のロード
    ;------------------------------------------
    ; Timer 0
    mov  dx, TM0_CNT
    mov  al, DIV_LOW
    out  dx, al
    mov  al, DIV_HIGH
    out  dx, al

    ; Timer 1
    mov  dx, TM1_CNT
    mov  al, DIV_LOW
    out  dx, al
    mov  al, DIV_HIGH
    out  dx, al

    ; Timer 2
    mov  dx, TM2_CNT
    mov  al, DIV_LOW
    out  dx, al
    mov  al, DIV_HIGH
    out  dx, al

    jmp 0x2000:0000   ; Far Jump to start of RAM monitor