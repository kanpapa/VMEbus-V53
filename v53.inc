; =================================================================
; NEC V53 (uPD70236) Internal I/O Definition File for NASM
; Based on Standard Reset Location (I/O Address 0xFF00 - 0xFFFF)
; =================================================================

%ifndef V53_INC
%define V53_INC

; -----------------------------------------------------------------
; Base Address of Internal Peripheral Area
; Note: V53 allows relocating this via the OPH register.
;       Default after reset is 0xFF00.
; -----------------------------------------------------------------
%define V53_BASE        0xFF00

; -----------------------------------------------------------------
; Unit Offsets
; -----------------------------------------------------------------
%define INT_OFFSET      0x00    ; Interrupt Control Unit
%define DMA_OFFSET      0x80    ; DMA Control Unit
%define TMR_OFFSET      0x20    ; Timer Control Unit
%define SER_OFFSET      0x60    ; Serial Control Unit
%define REF_OFFSET      0x40    ; Refresh Control Unit
%define WTC_OFFSET      0x78    ; Wait Control Unit

; -----------------------------------------------------------------
; Serial Interface Unit (SCU) - 最重要: コンソール通信用
; -----------------------------------------------------------------
; 非同期シリアル通信(UART)の設定に使います
%define V53_SCU_DATA    (V53_BASE + SER_OFFSET + 0x00) ; Rx/Tx Data Register (8bit)
%define V53_SCU_STS     (V53_BASE + SER_OFFSET + 0x02) ; Status Register (8bit)
%define V53_SCU_MODE    (V53_BASE + SER_OFFSET + 0x04) ; Mode Register (8bit)
%define V53_SCU_CMD     (V53_BASE + SER_OFFSET + 0x06) ; Command Register (8bit)
%define V53_SCU_BRG     (V53_BASE + SER_OFFSET + 0x08) ; Baud Rate Generator (8bit)

; Serial Status Bit Definitions
%define SCU_STS_RXRDY   0x02    ; Receive Data Ready
%define SCU_STS_TXRDY   0x01    ; Transmit Buffer Empty
%define SCU_STS_ERR     0x38    ; Error bits mask

; Baud Rate Generator Values for 19.6608MHz
; Formula: 19660800 / (16 * Baud)
%define BRG_9600    0x80    ; 128
%define BRG_19200   0x40    ; 64
%define BRG_38400   0x20    ; 32
; %define BRG_57600 0x15    ; 21 (誤差あり、一旦保留)

; -----------------------------------------------------------------
; Timer Control Unit (TCU)
; -----------------------------------------------------------------
; 3chの16bitタイマ
%define V53_TMR0_CNT    (V53_BASE + TMR_OFFSET + 0x00) ; Timer 0 Count
%define V53_TMR0_CPT    (V53_BASE + TMR_OFFSET + 0x02) ; Timer 0 Capture
%define V53_TMR0_MOD    (V53_BASE + TMR_OFFSET + 0x04) ; Timer 0 Mode
%define V53_TMR1_CNT    (V53_BASE + TMR_OFFSET + 0x08) ; Timer 1 Count
%define V53_TMR1_CPT    (V53_BASE + TMR_OFFSET + 0x0A) ; Timer 1 Capture
%define V53_TMR1_MOD    (V53_BASE + TMR_OFFSET + 0x0C) ; Timer 1 Mode
%define V53_TMR2_CNT    (V53_BASE + TMR_OFFSET + 0x10) ; Timer 2 Count (Watchdog/Prescaler)
%define V53_TMR2_MOD    (V53_BASE + TMR_OFFSET + 0x14) ; Timer 2 Mode

; -----------------------------------------------------------------
; DMA Control Unit (DMAU)
; -----------------------------------------------------------------
; 4ch DMA Controller
%define V53_DMA0_SRC_L  (V53_BASE + DMA_OFFSET + 0x00) ; Ch0 Source Addr Low
%define V53_DMA0_SRC_H  (V53_BASE + DMA_OFFSET + 0x02) ; Ch0 Source Addr High
%define V53_DMA0_DST_L  (V53_BASE + DMA_OFFSET + 0x04) ; Ch0 Dest Addr Low
%define V53_DMA0_DST_H  (V53_BASE + DMA_OFFSET + 0x06) ; Ch0 Dest Addr High
%define V53_DMA0_CNT    (V53_BASE + DMA_OFFSET + 0x08) ; Ch0 Transfer Count
%define V53_DMA0_MOD    (V53_BASE + DMA_OFFSET + 0x0A) ; Ch0 Mode

; (Ch1-3は省略していますが、必要ならオフセット +0x10 ずつ加算です)

; -----------------------------------------------------------------
; Interrupt Control Unit (ICU)
; -----------------------------------------------------------------
%define V53_ICU_IMR     (V53_BASE + INT_OFFSET + 0x02) ; Interrupt Mask Register
%define V53_ICU_IRR     (V53_BASE + INT_OFFSET + 0x00) ; Interrupt Request Register
%define V53_ICU_POLL    (V53_BASE + INT_OFFSET + 0x04) ; Poll Register

; -----------------------------------------------------------------
; System Control (Wait, Clock, etc.)
; -----------------------------------------------------------------
%define V53_WTC         (V53_BASE + WTC_OFFSET + 0x00) ; Wait Control Register
%define V53_OPH         0xFFFF                         ; On-chip Peripheral relocate Address (I/O)

; =================================================================
; Useful Macros for V53
; =================================================================

; マクロ: シリアルポートへの1文字出力 (Polling)
; 引数: 出力したい文字(またはレジスタ)
; 使用例: V53_PUTC 'A'
%macro V53_PUTC 1
    push ax
    push dx
%%wait_tx:
    mov dx, V53_SCU_STS
    in al, dx
    test al, SCU_STS_TXRDY
    jz %%wait_tx         ; 送信バッファが空くまで待つ
    
    mov dx, V53_SCU_DATA
    mov al, %1
    out dx, al           ; 送信
    
    pop dx
    pop ax
%endmacro

%endif ; V53_INC