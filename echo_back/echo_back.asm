; =================================================================
; DENSAN V53 VME board "Echo Back" test ROM
; =================================================================

; ▼▼▼ ROMサイズ設定 (ここを環境に合わせる) ▼▼▼
%define ROM_SIZE_1024  0x20000  ; 27C010 (128KB)
; 使用するROMサイズを選択
%define ROM_TOTAL     ROM_SIZE_1024
; ▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲▲

; ==========================================
; V53 System Register
; ==========================================
%define SCTL    0x0FFFE ; システム・コントロール・レジスタ
%define OPSEL   0x0FFFD ; 内蔵ペリフェラル選択レジスタ
%define OPHA    0x0FFFC ; 内蔵ペリフェラル・リロケーション・レジスタ
%define DULA    0x0FFFB ; 
%define IULA    0x0FFFA ; 
%define TULA    0x0FFF9 ; 
%define SULA    0x0FFF8 ; SCUリロケーション・レジスタ 
%define WCY4    0x0FFF6 ; 
%define WCY3    0x0FFF5 ; 
%define WCY2    0x0FFF4 ; 
%define WMB1    0x0FFF3 ; 
%define RFC     0x0FFF2 ; 
%define SBCR    0x0FFF1 ; 
%define TCKS    0x0FFF0 ; 
%define WAC     0x0FFED ; 
%define WCY0    0x0FFEC ; 
%define WCY1    0x0FFEB ; 
%define WMB0    0x0FFEA ; 
%define BRC     0x0FFE9 ; ボー・レート・カウンタ
%define BADR    0x0FFE1 ; 
%define BSEL    0x0FFE0 ; 
%define XAM     0x0FF80 ; 
%define PGR     0x0FF00 ; 

; SCUレジスタ (SCUは1260Hに配置）
%define SCU_DATA 0x01260 ; 送受データ・レジスタ(R:SRB/W:STB)
%define SCU_SST  0x01261 ; ステータス・レジスタ(R:SST)
%define SCU_SCM  0x01261 ; コマンドレジスタ(W:SCM)
%define SCU_SMD  0x01262 ; シリアルモード設定(W:SMD)
%define SCU_SIMK 0x01263 ; シリアル割り込みマスクレジスタ(R/W:SIMK)

cpu 186
bits 16

; ==========================================
; コードセクション (ROMの先頭付近)
; ==========================================
section .text
org 0

; -----------------------------------------------------------------
; Entry Point (Offset 0x0000)
; -----------------------------------------------------------------
start:
    cli             ; 割り込み禁止

    ; ---------------------------------------------
    ; 1. セグメントレジスタ初期化
    ; ※CSはJMP命令で設定されるので、DS/ES/SSを設定する
    ; ---------------------------------------------
    mov ax, 0x0000
    mov ds, ax
    mov es, ax
    mov ss, ax
    mov sp, 0x1000
    
    ; ---------------------------------------------
    ; 2. システム・コントロール・レジスタ (SCTL) の設定
    ; ビット4 (SC) = 1 : 内蔵BRGを使用
    ; ビット0 (IOAG) = 1 : 8ビット・バウンダリ（連続配置）
    ; ---------------------------------------------
    mov dx, SCTL
    mov al, 00010001b
    out dx, al

    ; ---------------------------------------------
    ; 3. ボーレートジェネレータ (BRG) の設定
    ;  38400bps設定 (fx=16MHz, factor=x16)
    ;  16,000,000/(16×38400) ≈ 26
    ; ---------------------------------------------
    mov dx, BRC
    mov al, 26
    out dx, al

    ; ---------------------------------------------
    ; 4. IOアドレスの設定 (0x1260にSCUを配置)
    ; OPHA (FFFCH) に 12H を設定 (ベースアドレス上位8ビット)
    ; SULA (FFF8H) に 60H を設定 (SCUのオフセット)
    ; ---------------------------------------------
    mov dx, OPHA
    mov al, 0x12    ; 上位アドレス
    out dx, al

    mov dx, SULA
    mov al, 0x60    ; 下位アドレス
    out dx, al
    
    ; ---------------------------------------------
    ; 5. 内蔵周辺選択レジスタ (OPSEL) でSCUを有効化
    ; ビット3 (SS) = 1 : SCUの使用を許可
    ; ---------------------------------------------
    mov dx, OPSEL
    mov al, 00001000b   ; Bit3 (SS): SCUの使用を許可
    out dx, al

    ; ---------------------------------------------
    ; 6. SCU内部レジスタの初期化 (配置した1260Hを使用)
    ; ---------------------------------------------
    ; 動作モード設定 SMDレジスタ
    ; Mode: 非同期, 8bit, パリティなし, 1ストップビット, x16クロック
    ; 01 00 11 10
    mov dx, SCU_SMD
    mov al, 01001110b
    out dx, al

    ; コマンド設定  SCMレジスタ
    ; Cmd: 送受信イネーブル, エラーリセット, DTR/RTSアクティブ
    ; 00 0 1 0 1 0 1
    mov dx, SCU_SCM
    mov al, 00010101b   ; RTS/DTR ON, RX/TX Enabl
    out dx, al

    ; 割り込みはマスクする  SIMKレジスタ
    mov dx, SCU_SIMK
    mov al, 00000011b
    out dx, al

    ; ---------------------------------------------
    ; 7. 受信したデータをそのまま送信するループ
    ; ---------------------------------------------
main_loop:
    call com_recv
    call com_send
    jmp main_loop

    ; ---------------------------------------------
    ; シリアル受信ルーチン
    ; シリアル受信データをalレジスタに格納。dxは破壊される。
    ; ---------------------------------------------
com_recv:
    mov dx, SCU_SST
.wait_rx:
    in al, dx
    test al, 00000010b  ; RX Ready?
    jz .wait_rx
 
    mov dx, SCU_DATA
    in al, dx
    ret

    ; ---------------------------------------------
    ; シリアル送信ルーチン
    ; alレジスタの内容をシリアル送信。dx, blは破壊される。
    ; ---------------------------------------------
com_send:
    ; 送信データを退避
    mov bl,al

    mov dx, SCU_SST
.wait_tx:
    in al, dx
    test al, 00000001b  ; TX Ready?
    jz .wait_tx
    
    mov dx, SCU_DATA
    mov al, bl
    out dx, al
    ret

; -----------------------------------------------------------------
; Padding (空白埋め)
; コードの終わりから、リセットベクタの手前までを0xFFで埋める
; -----------------------------------------------------------------
    times ROM_TOTAL - 16 - ($ - $$) db 0xFF

; -----------------------------------------------------------------
; Reset Vector (Physical Address FFFF0h)
; CPUは電源ON時、ここ(ROMの末尾16バイト地点)を実行する
; -----------------------------------------------------------------
reset_vector:
    ; ROMの先頭(start)へジャンプする
    ; 1MBit ROMの場合、物理アドレスは E0000h～FFFFFh にマップされる想定
    ; なので、セグメント E000h, オフセット 0000h へ飛べばよい
    
    jmp 0xE000:0000   ; Far Jump to start of 128KB ROM

    ; ファイルサイズがぴったりROMサイズになるよう調整
    times 16 - ($ - reset_vector) db 0xFF