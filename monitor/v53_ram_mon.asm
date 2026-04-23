; =================================================================
; V53 Monitor System v0.13 2026-04-23
; Target: V53 VME Board & DOSBox-X Simulation
; =================================================================

; --- ビルド方法 ---
; DOSBox: nasm -f bin -dSIM v53_ram_mon.asm -o v53_ram_mon.com -l v53_ram_mon.lst
; Real:   nasm -f bin v53_ram_mon.asm -o v53_ram_mon.bin -l v53_ram_mon.lst
; objcopy -I binary -O ihex --change-addresses=0x0000 v53_ram_mon.bin v53_ram_mon.hex
; -----------------

; ==========================================
; V53 System Register
; ==========================================
%define SCTL    0x0FFFE ; システム・コントロール・レジスタ
%define OPSEL   0x0FFFD ; 内蔵ペリフェラル選択レジスタ
%define OPHA    0x0FFFC ; 内蔵ペリフェラル・リロケーション・レジスタ
%define DULA    0x0FFFB ; 
%define IULA    0x0FFFA ; ICUリロケーション・レジスタ
%define TULA    0x0FFF9 ; TCUリロケーション・レジスタ
%define SULA    0x0FFF8 ; SCUリロケーション・レジスタ 
%define WCY4    0x0FFF6 ; プログラマブル・ウェイト・サイクル数設定レジスタ4
%define WCY3    0x0FFF5 ; プログラマブル・ウェイト・サイクル数設定レジスタ3
%define WCY2    0x0FFF4 ; プログラマブル・ウェイト・サイクル数設定レジスタ2
%define WMB1    0x0FFF3 ; プログラマブル・ウェイト・メモリ領域設定レジスタ1
%define RFC     0x0FFF2 ; リフレッシュ・コントロール・レジスタ
%define SBCR    0x0FFF1 ; 
%define TCKS    0x0FFF0 ; タイマー・クロック選択レジスタ
%define WAC     0x0FFED ; プログラマブル・ウェイト・メモリ・アドレス・コントロール・レジスタ
%define WCY0    0x0FFEC ; プログラマブル・ウェイト・サイクル数設定レジスタ0
%define WCY1    0x0FFEB ; プログラマブル・ウェイト・サイクル数設定レジスタ1
%define WMB0    0x0FFEA ; プログラマブル・ウェイト・メモリ領域設定レジスタ0
%define BRC     0x0FFE9 ; ボー・レート・カウンタ
%define BADR    0x0FFE1 ; 
%define BSEL    0x0FFE0 ; 
%define XAM     0x0FF80 ; 
%define PGR     0x0FF00 ; 



%ifdef SIM
    ; --- Simulation Mode ---
    org 0x100
    cpu 186

    %define SCU_DATA   0x3F8
    %define SCU_SST    0x3FD
    %define TX_READY    0x20                                 
    %define RX_READY    0x01
%else
    ; --- Real Hardware Mode ---
    org 0
    cpu 186

    ; V53 SCU (F060Hに配置）
    %define SCU_DATA    0x0F060 ; 送受データ・レジスタ(R:SRB/W:STB)
    %define SCU_SST     0x0F061 ; ステータス・レジスタ(R:SST)
    %define SCU_SCM     0x0F061 ; コマンドレジスタ(W:SCM)
    %define SCU_SMD     0x0F062 ; シリアルモード設定(W:SMD)
    %define SCU_SIMK    0x0F063 ; シリアル割り込みマスクレジスタ(R/W:SIMK)
    %define TX_READY    00000001b   ; TBRDY                                 
    %define RX_READY    00000010b   ; RBRDY

    ; V53 TCU (F070Hに配置)
    %define TM0_CNT     0x0F070 ; Timer 0 Counter
    %define TM1_CNT     0x0F071 ; Timer 1 Counter
    %define TM2_CNT     0x0F072 ; Timer 2 Counter
    %define TM_CTL      0x0F073 ; Timer Control

    ; V53 ICU (F080Hに配置)
    %define ICU_REG0    0x0F080
    %define ICU_REG1    0x0F081

    ;-----------------------------------------
    ; V53 VME Board ペリフェラル
    ;-----------------------------------------
    %define USART_DATA  0x00d8  ; μPD71051 (USART)	Data Register
    %define USART_CMD   0x00da  ; μPD71051 (USART)	Cmd/Status

    %define PIC_REG0    0x00c8  ; μPD71059 (PIC)	IRR/ISR/IW1/PCFW/MCW	
    %define PIC_REG1    0x00cA  ; μPD71059 (PIC)	IMR/IW2/IW3/IW4

    %define PPI_PORTA   0x00e0  ; μPD71055 (PPI)	Port A	
    %define PPI_PORTB   0x00e2  ; μPD71055 (PPI)	Port B	
    %define PPI_PORTC   0x00e4	; μPD71055 (PPI)	Port C	
    %define PPI_CTRL    0x00e6  ; μPD71055 (PPI)	Control
%endif

section .text

start:
%ifdef SIM
    xor ax, ax
    mov es, ax
%else
    cli             ; 初期化中は割り込み禁止

    ; ---------------------------------------------
    ; 1. セグメントレジスタ初期化
    ; CS=DS=ES を想定
    ; ---------------------------------------------
    push cs
    pop ds
    push cs
    pop es
    ; --- 【重要】スタックの初期化 ---
    ; 現在のCSセグメントの末尾 (FFFEh) にスタックを移動させます。
    ; これでコード領域との衝突を回避します。
    mov ax, cs
    mov ss, ax
    mov sp, 0xFFFE
    ; ------------------------------

    ;==============================================
    ; Interrupt Vector Setup 
    ;==============================================
Init_Interrupt_Vectors:
    ; ----------------------------------------------------
    ; 1. 全ベクタ (00h-FFh) をデフォルトハンドラで埋める
    ;    (予期せぬ割り込みによる暴走を防ぐ安全策)
    ; ----------------------------------------------------
    xor ax, ax
    mov es, ax          ; ES = 0000h (Vector Table)
    mov di, 0           ; Offset 0

    mov cx, 256         ; 256個のベクタ全てを設定
.init_loop:
    mov ax, _default_int_unknown_handler ; 共通トラップハンドラ
    stosw               ; Offset書き込み
    mov ax, cs
    stosw               ; Segment書き込み
    loop .init_loop

    ; 専用割り込みベクタを上書き登録 (0x00 - 0x05)
    xor  ax, ax
    mov  es, ax         ; ES = 0000h

    mov word [es:0x00], _isr_stub_0    ; オフセットを書き込み　0x00 * 4 = 0x00
    mov word [es:0x02], cs             ; 現在のコードセグメントを書き込み

    mov word [es:0x04], _isr_stub_1    ; オフセットを書き込み　0x01 * 4 = 0x04
    mov word [es:0x06], cs             ; 現在のコードセグメントを書き込み

    mov word [es:0x08], _isr_stub_2    ; オフセットを書き込み　0x02 * 4 = 0x08
    mov word [es:0x0A], cs             ; 現在のコードセグメントを書き込み

    mov word [es:0x0C], _isr_stub_3    ; オフセットを書き込み　0x03 * 4 = 0x0C
    mov word [es:0x0E], cs             ; 現在のコードセグメントを書き込み

    mov word [es:0x10], _isr_stub_4    ; オフセットを書き込み　0x04 * 4 = 0x10
    mov word [es:0x12], cs             ; 現在のコードセグメントを書き込み
    
    mov word [es:0x14], _isr_stub_5    ; オフセットを書き込み　0x05 * 4 = 0x14
    mov word [es:0x16], cs             ; 現在のコードセグメントを書き込み

    ; ICU割り込みベクタを上書き登録 (0x20 - 0x27)    
    ; Vector 20h (ICU INTP0) 登録
    mov word [es:0x80], _isr_stub_20    ; オフセットを書き込み　0x20 * 4 = 0x80
    mov word [es:0x82], cs              ; 現在のコードセグメントを書き込み

    ; Vector 21h (ICU INTP1) 登録
    mov word [es:0x84], _isr_stub_21
    mov word [es:0x86], cs

    ; Vector 22h (ICU INTP2) 登録
    mov word [es:0x88], _isr_stub_22
    mov word [es:0x8A], cs

    ; Vector 23h (ICU INTP3) 登録
    mov word [es:0x8C], _isr_stub_23
    mov word [es:0x8E], cs

    ; Vector 24h (ICU INTP4) 登録
    mov word [es:0x90], _isr_stub_24
    mov word [es:0x92], cs

    ; Vector 25h (ICU INTP5) 登録
    mov word [es:0x94], _isr_stub_25
    mov word [es:0x96], cs

    ; Vector 26h (ICU INTP6) 登録
    mov word [es:0x98], _isr_stub_26
    mov word [es:0x9A], cs

    ; Vector 27h (ICU INTP7) 登録
    mov word [es:0x9C], _pic_dispatch_handler
    mov word [es:0x9E], cs

    ; ---------------------------------------------
    ; 1.2 メモリウェイト値の設定
    ; オンボードRAMは35nsなので0Waitで良さそう
    ; 拡張RAMボードは70nsなので途中1waitの領域も設定
    ; ROMは70nsなので2waitに、外部I/Oは不明のためとりあえず3waitで
    ; ---------------------------------------------
    ; リセット時の値
    ; WMB0  -111-111  16MBのメモリ空間の上位、下位で8MB
    ; WMB1  -111-111　1MBメモリ空間の上位、下位で512KB
    ; WCY0-WCY3 すべて7wait
    ;
    mov dx, WMB1
    mov al, 01110011b	; L=512KB(Onboard RAM) M=384KB(VME RAM) H=128KB(Onboard ROM)
    out dx, al

    mov dx, WCY2
    mov al, 00000000b	; M=0wait L=0wait
    out dx, al

    mov dx, WCY3
    mov al, 00110010b	; IO=1wait H=1wait
    out dx, al

    ;------------------------------------------
    ; V53 内蔵ペリフェラルのIOアドレスを設定 (OPHA)
    ;------------------------------------------
    mov  dx, OPHA ; 内蔵ペリフェラル・リロケーション・レジスタ
    mov  al, 0xF0 ; 0xF0xxに配置
    out  dx, al
    ;------------------------------------------
    ; ICU レジスタ配置アドレスの設定 (IULA) 0xF080
    ;------------------------------------------
    mov dx, IULA
    mov al, 0x80    ; 下位アドレス
    out dx, al
    ;------------------------------------------
    ; TCU レジスタ配置アドレスの設定 (TULA) 0xF070
    ;------------------------------------------
    mov dx, TULA
    mov al, 0x70    ; 下位アドレス
    out dx, al
    ;------------------------------------------
    ; SCU レジスタ配置アドレスの設定 (SULA) 0xF060
    ;------------------------------------------
    mov dx, SULA
    mov al, 0x60    ; 下位アドレス
    out dx, al
    
    ;------------------------------------------
    ; V53 内蔵ペリフェラルの有効化 (OPSEL)
    ; 有効化する前にOPHA,DULA,IULA,TULA,SULAの設定が必要
    ;------------------------------------------
    mov  dx, OPSEL
    in   al, dx
    or   al, 00001110b   ; Bit 1(ICU),Bit 2(TCU),Bit 3(SCU)をセット
    out  dx, al

    ;------------------------------------------
    ; TCUの設定
    ;------------------------------------------
    ; 3. TCKS: タイマクロック入力選択
    ;------------------------------------------
    mov  dx, TCKS
    mov  al, 00011100b   ; Timer1: TCLK端子入力使用
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
    mov  al, 0xb6         ; Mode 3, Binary, LSB/MSB
    out  dx, al

    ;------------------------------------------
    ; 4. カウンタ値 (分周比) のロード
    ;------------------------------------------
    ; Timer 0 (INTP0)
    ; 1.2288MHz / 12288 = 100Hz
    mov  dx, TM0_CNT
    mov  al, 0x00
    out  dx, al
    mov  al, 0x30
    out  dx, al

    ; Timer 1 (INTP2)
    ; 1.2288MHz / 61440 = 20Hz
    mov  dx, TM1_CNT
    mov  al, 0x00
    out  dx, al
    mov  al, 0xF0
    out  dx, al

    ; Timer 2 (USART Tx/RxCLK)
    ; 1.2288MHz / 4 = 307.20KHz
    ; USART CLOCK 19200bps
    mov  dx, TM2_CNT
    mov  al, 4
    out  dx, al
    mov  al, 0
    out  dx, al

    ;------------------------------------------
    ; μPD71051 (USART) 初期化
    ;------------------------------------------
    mov al, 0
    out USART_CMD, al
 
    mul cx              ; wait
    mul cx              ; wait
    out USART_CMD, al
 
    mul cx              ; wait
    mul cx              ; wait
    out USART_CMD, al
 
    mul cx              ; wait
    mul cx              ; wait
    mov al, 0x40        ; reset
    out USART_CMD, al
 
    mul cx              ; wait
    mul cx              ; wait
    mov al, 0x4e        ; set mode
    out USART_CMD, al
 
    mul cx              ; wait
    mul cx              ; wait
    mov al, 0x37        ; rx,tx ready
    out USART_CMD, al

    ;------------------------------------------
    ; μPD71059 (PIC) 初期化
    ;------------------------------------------
    mov al, 13h         ; ICW1: Edge, Single, ICW4 needed
    out PIC_REG0, al

    mov al, 20h         ; ICW2: Vector Offset = 20h (INT 32)
    out PIC_REG1, al
                        ; ICW3 is skipped in Single Mode
    mov al, 01h         ; ICW4: 8086 Mode, Normal EOI
    out PIC_REG1, al

    mov al, 0FEh        ; OCW1: Unmask IR0 (Timer) only. (1111 1110)
    out PIC_REG1, al

    ;------------------------------------------
    ; ICUの追加設定
    ;------------------------------------------
    ; 3. 割り込みマスクの設定 (Enable INTP7)
    ;------------------------------------------
    mov dx, ICU_REG0
    mov al, 13h     ; ICW1: Edge, Single, ICW4 needed
    out dx, al

    mov dx, ICU_REG1
    mov al, 20h     ; ICW2: Vector Offset = 20h (INT 32)
    out dx, al
                    ; ICW3 is skipped in Single Mode
    mov al, 01h     ; ICW4: 8086 Mode, Normal EOI
    out dx, al

    ; Bit 7 (INTP7) を 0 (許可) にその他は禁止します。
    ;mov al, 7Fh     ; 0111 1111
    mov al, 00h     ; 0000 0000 全マスク解除
    out dx, al

    ;-------------------------------------------
    ; 割り込み許可
    ;-------------------------------------------
    sti

 %endif

    ; 変数初期化 (RAMエリアをクリア)
    mov word [dump_seg], 0x0000
    mov word [dump_off], 0x0000
    mov word [load_seg], 0x2000

    ; スタートメッセージの表示
    mov si, msg_boot
    call puts

; =================================================================
; Main Loop
; =================================================================
monitor_loop:
    mov al, '>'
    call putc
    mov al, ' '
    call putc

    call getc_echo  ; コマンド受信（エコーあり）
    mov bl, al
    
    cmp bl, 'd'     ; dump command
    je do_dump
    cmp bl, 'D'
    je do_dump
    
    cmp bl, 'l'     ; load command
    je do_load
    cmp bl, 'L'
    je do_load
    
    cmp bl, 'g'     ; go command
    je do_go
    cmp bl, 'G'
    je do_go

    cmp bl, 'w'     ; Write command
    je do_write
    cmp bl, 'W'
    je do_write

    cmp al, 'i'     ; Input Port command
    je do_in
    cmp al, 'I'
    je do_in

    cmp al, 'o'     ; Output Port command
    je do_out
    cmp al, 'O'
    je do_out

    cmp al, 's'     ; Scan I/O command
    je do_scan
    cmp al, 'S'
    je do_scan

    cmp al, 't'     ; Scan Timer wait command
    je do_timer
    cmp al, 'T'
    je do_timer

    cmp al, '?'     ; Help
    je cmd_help

    ; 知らないコマンドなら改行して戻る
    call putc_crlf
    jmp monitor_loop

; =================================================================
; Command: Dump Memory
; Usage:
;   D               -> Dump next 64 bytes
;   D <Seg> <Off>   -> Set address and dump (e.g., D 0000 8000)
; =================================================================
do_dump:
    call getc_echo      ; 区切り文字受信 (Space or Enter)
    cmp al, 0x0D        ; Enterならすぐ実行
    je .dump_run
    cmp al, ' '         ; Spaceなら引数解析
    je .parse_args
    
    ; それ以外なら無視して実行へ（またはエラー処理）
    call putc_crlf
    jmp .dump_run_start

.parse_args:
    call get_hex_word
    mov [dump_seg], ax
    call skip_space
    call get_hex_word
    mov [dump_off], ax
    ; ここでEnter待ちをするか、そのまま実行するか
    ; 今回はパラメータ入力後にEnterを押したと仮定して改行
    
.dump_run:
    call putc_crlf              ; 実行直前に改行

.dump_run_start:
    mov cx, 4                   ; 4行表示する
    
.line_loop:
    push cx
    
    mov ax, [dump_seg]          ; セグメントの表示
    call print_hex_word
    mov al, ':'                 ; 区切り文字の:を表示
    call putc
    mov ax, [dump_off]          ; オフセットの表示
    call print_hex_word
    mov al, ' '                 ; 区切り文字のスペースを表示
    call putc

    mov si, [dump_off]          ; DS変更前に、モニタ変数からオフセットをSIにロード

    push ds                     ; モニタのDSを保存
    mov ds, [dump_seg]          ; DSをターゲットセグメントに変更
    
    mov cx, 16                  ; 16回繰り返すカウンタ
.hex_loop:
    mov al, [si]
    call print_hex_byte         ; メモリ内容の表示
    mov al, ' '                 ; 区切り文字のスペースを表示
    call putc
    inc si                      ; 次のアドレスにする
    loop .hex_loop              ; 16回繰り返し    

    pop ds                      ; DSをモニタ用に戻す

    mov [dump_off], si          ; DS復帰後に、SIの値をモニタ変数に保存

    call putc_crlf              ; 改行する
    pop cx
    loop .line_loop             ; 4回繰り返す
    
    jmp monitor_loop            ; モニタのメインルーチンに飛ぶ

; =================================================================
; Command: Load Intel HEX
; Usage:
;   L           -> Load to default segment (load_seg)
;   L <Seg>     -> Set segment and Load (e.g., L 2000)
; =================================================================
do_load:
    ; 一時的に ES をロード先にするため、デフォルト値をAXへ退避
    mov ax, [load_seg]
    push es             ; RAM用ESを保存
    push ax             ; デフォルトセグメントを保存
    
    call getc_echo
    cmp al, ' '         ; スペースがあればパラメタ付きと判断
    je .parse_seg
    jmp .start_load

.parse_seg:
    pop ax              ; 不要になったデフォルトを捨てる
    call get_hex_word   ; 新しいセグメント取得
    push ax             ; 保存

.start_load:
    call putc_crlf      ; メッセージ表示前に改行
    mov si, msg_load    ; ロード開始メッセージを表示
    call puts
    
    pop ax
    mov es, ax          ; ロード先をESに設定
    
    ; ターゲット表示
    call print_hex_word ; ESの値を表示
    mov al, ':'         ; 区切り文字を表示
    call putc
    mov al, '0'         ; 本来は0000だが、0と簡易表示
    call putc
    call putc_crlf

.wait_record:
    call getc           ; 開始文字を待つ
    cmp al, ':'
    jne .wait_record

    call get_hex_byte   ; データ長を読み込み
    mov cl, al          ; データ長をcxレジスタに設定
    mov ch, 0
    
    call get_hex_byte   ; 上位アドレスを読み込み
    mov bh, al
    call get_hex_byte   ; 下位アドレスを読み込み
    mov bl, al
    
    call get_hex_byte   ; レコードタイプを読み込み
    cmp al, 01          ; End of File?
    je .handle_eof      ; EOFの処理へ
    cmp al, 00          ; Data Record?
    jne .skip_line      ; その他はスキップ
    
    jcxz .read_chk      ; データ長がゼロならチェックサム読み込み処理
    
.data_loop:
    call get_hex_byte   ; 1バイト読み取り
    mov [es:bx], al     ; ターゲット(ES)へ書き込み
    inc bx              ; 次のアドレスにする
    ; --- 追加: 64KBの境界チェック ---
    jnz .loop_next      ; bxが0にならなければそのまま
    mov ax, es          ; bxが0(一周)したら
    add ax, 0x1000      ; セグメントを64KB分(0x1000)進める
    mov es, ax
    ; -----------------------------

.loop_next:
    loop .data_loop     ; データ長分繰り返す
    
.read_chk:
    call get_hex_byte   ; チェックサム読み取り（読み飛ばし）
    mov al, '.'         ; 1行読んだことを示す"."を出力
    call putc
    jmp .wait_record    ; 次のレコード読み取りへ

.handle_eof:            ; EOFの場合
    call get_hex_byte   ; チェックサムを読み飛ばす
    jmp .finish         ; 読み込み終了処理へ

.skip_line:
    jmp .wait_record    ; 次のレコード読み込みへ

.finish:
    pop es              ; RAM用ESを復帰
    call putc_crlf
    mov si, msg_ok      ; "OK"を表示
    call puts
    jmp monitor_loop    ; モニタのメインルーチンに飛ぶ

; =================================================================
; Command: Execute
; Usage:
;   G <Seg> <Off>
; Example: G 1000 0000
; =================================================================
do_go:
    ; Gコマンドは入力後に改行
    
    call getc_echo      ; Space?
    cmp al, ' '
    jne .go_default     ; 引数なしならリターン(またはエラー)
    
    ; 1. セグメント (SSSS) を取得
    call get_hex_word   ; AX = Segment
    push ax             ; スタックに積む (あとでRETFでCSになる)
    mov bx, ax          ; DS/ES用のために保存しておく
    
    ; スペース読み飛ばし (もしあれば)
    call skip_space
    
    ; 2. オフセット (OOOO) を取得
    call get_hex_word   ; AX = Offset
    push ax             ; スタックに積む (あとでRETFでIPになる)
    
    call putc_crlf      ; 実行前に改行
    mov si, msg_go
    call puts
    call putc_crlf
    
    ; 3. 実行環境のセットアップ
    ; ジャンプ先のプログラムのために、DS, ES もセグメントに合わせておくのが親切
    mov ds, bx
    mov es, bx

    ; 必要なら割り込み禁止 (OSが自分でセットアップするまで黙らせる)
    cli

    ; 4. ジャンプ！ (Far Return)
    ; スタック上の [IP, CS] をポップして、そこへ飛ぶ
    retf                ; Jump!

.go_default:
    call putc_crlf      ; 改行して
    jmp monitor_loop    ; モニタのメインルーチンに飛ぶ

; ==============================================================
; Command: Write Memory
; Usage:
;   W <Seg> <Off> <Val>
; ==============================================================
do_write:    
    call getc_echo      ; Space?
    cmp al, ' '
    jne error           ; 引数なしならリターン(またはエラー)

    ; 1. セグメント (SSSS) を取得
    call get_hex_word   ; AX = Segment
    push ax             ; ターゲットセグメントを保存
    
    call getc_echo      ; Space?
    cmp al, ' '
    jne error           ; 引数なしならリターン(またはエラー)
    
    ; 2. オフセット (OOOO) を取得
    call get_hex_word   ; AX = Offset
    push ax             ; ターゲットオフセットを保存

    call getc_echo      ; Space?
    cmp al, ' '
    jne error           ; 引数なしならリターン(またはエラー)

    ; 3. 設定データ (VV) を取得
    call get_hex_byte_echo   ; AL = Value

    pop bx              ; bx = Offset
    pop dx              ; dx = Target Segment

    ; 次回のDコマンドのためにダンプ位置変数を更新する
    mov [dump_seg], dx
    mov [dump_off], bx
    
    mov ds, dx          ; DS再設定
    mov [ds:bx], al     ; 書き込み！
    
    push cs             ; DSを復帰 (CS=DS前提のモニタなので)
    pop ds

    mov si, msg_done
    call puts
    jmp monitor_loop

; ==============================================================
; Command: Input from Port
; Usage:
;   I <Port>
; ==============================================================
do_in:
    call getc_echo
    cmp al, ' '         ; スペースがあればパラメタ付きと判断
    jne error           ; パラメタが無い場合はエラー処理へ

    call get_hex_word   ; ポートアドレスを取得
    mov dx, ax          ; 保存
    in al, dx           ; I/O Read
    
    push ax
    call putc_crlf      ; メッセージ表示前に改行
    mov si, msg_in_res
    call puts
    pop ax

    call print_hex_byte ; 値を表示

    call putc_crlf      ; 改行して
    jmp monitor_loop    ; モニタのメインルーチンに飛ぶ

; ==============================================================
; Command: Output to Port
; Usage
;   O <Port> <Val>
; ==============================================================
do_out:
    call getc_echo
    cmp al, ' '         ; スペースがあればパラメタ付きと判断
    jne error           ; パラメタが無い場合はエラー処理へ

    call get_hex_word   ; ポートアドレスを取得
    push ax             ; スタックに積む

    call getc_echo
    cmp al, ' '         ; スペースがあれば第2パラメタがあると判断
    jne error_pop       ; 第2パラメタが無い場合はエラー処理へ
    
    call get_hex_byte_echo   ; 出力値を取得
    pop dx              ; スタックからDXにセット
    
    out dx, al          ; I/O Write
    
    mov si, msg_done    ; DONEを表示。改行付き。
    call puts
    jmp monitor_loop    ; モニタのメインルーチンに飛ぶ

error_pop:
    pop ax              ; 使わなかったスタックを捨てる
    jmp error

; ==============================================================
; Command: Scan I/O Ports
; Usage:
;   S <Start_port> <End_port>
; Description: Reads ports and prints if value is NOT 0xFF
; ==============================================================
do_scan:
    call getc_echo
    cmp al, ' '         ; スペースがあればパラメタ付きと判断
    jne error           ; パラメタが無い場合はエラー処理へ

    call get_hex_word   ; スタートポートアドレスを取得
    mov bx, ax          ; BX = Start Address
    
    call getc_echo
    cmp al, ' '         ; スペースがあれば第2パラメタがあると判断
    jne error_pop       ; 第2パラメタが無い場合はエラー処理へ

    call get_hex_word   ; エンドポートアドレスを取得
    mov cx, ax          ; CX = End Address

    cmp bx, cx          ; 開始 > 終了 ならエラー終了
    ja error

    call putc_crlf
    mov si, msg_scan_start
    call puts

.scan_loop:
    mov dx, bx          ; DXにポートアドレス設定
    in al, dx           ; I/O Read

    cmp al, 0xFF        ; 0xFF (Empty Bus) なら表示しない
    je .next_port

    push ax             ; Readした値をスタックに保存

    ; --- 有効な値が見つかった場合の表示 ---
    ; [Port]: Value
    mov ax, bx
    call print_hex_word ; ポートアドレスの表示
    mov al, ':'
    call putc
    mov al, ' '
    call putc
    
    pop ax
    call print_hex_byte ; Readした値の表示
    
    mov si, msg_space   ; "  "
    call puts

    ; 1行に見やすく並べるため、適当な間隔で改行を入れる等の工夫も可能ですが
    ; ここでは単純にリスト形式で改行します
    call putc_crlf

.next_port:
    inc bx              ; 次のアドレスへ
    
    ; キー入力チェック（長いスキャンを中断できるようにする）
    mov dx, SCU_SST
    in al, dx
    test al, RX_READY   ; RxRDY?
    jnz .abort          ; 何かキーが押されたら中断

    cmp bx, cx
    jbe .scan_loop      ; BX <= CX ならループ

    mov si, msg_done
    call puts
    jmp monitor_loop

.abort:
    ; 入力バッファを空読みしておく
    mov dx, SCU_DATA
    in al, dx
    mov si, msg_abort
    call puts
    jmp monitor_loop

; ==============================================================
; Command: Timer
;   T          -> Show current tick counter (32-bit HEX)
;   T <val>    -> Wait for <val> ticks (10ms unit)
; ==============================================================
do_timer:
    call getc_echo      ; コマンド('T')の次の文字を取得
    cmp al, 0x0D        ; Enterキー(CR)なら表示モードへ
    je .show_counter
    cmp al, ' '         ; スペースならWaitモードへ
    jne error           ; それ以外はエラー

    ; --- Wait Mode (引数あり: T 0064 等) ---
    call get_hex_word   ; AX = 待ち時間 (0064h = 1秒)

    ; 開始時刻を保存 (Start Time)
    mov bx, [tick_counter_lo]

.wait_loop:
    ; 1. 現在時刻を取得
    mov cx, [tick_counter_lo]
    
    ; 2. 経過時間を計算 (Current - Start)
    ; オーバーフローしても、この引き算の結果は正しい経過時間になる
    sub cx, bx          
    
    ; 3. 経過時間 < 待ち時間 ならループ継続
    cmp cx, ax
    jb .wait_loop       ; Jump if Below (unsigned compare)

    ; 指定時間経過した
    mov si, msg_done
    call puts
    jmp monitor_loop

.show_counter:
    ; --- Show Counter Mode (引数なし: Tのみ) ---
    call putc_crlf
    
    mov si, msg_tick    ; "Tick: "
    call puts

    ; 32bitカウンタを [High][Low] の順で表示
    mov ax, [tick_counter_hi]
    call print_hex_word
    mov ax, [tick_counter_lo]
    call print_hex_word
    
    call putc_crlf
    jmp monitor_loop

; ==============================================================
; Command: Help
; ==============================================================
cmd_help:
    call putc_crlf
    mov si, msg_help
    call puts
    jmp monitor_loop

; =================================================================
; Utilities
; =================================================================

; 文字列出力
puts:
    mov al, [cs:si]
    or al, al
    jz .ret
    call putc
    inc si
    jmp puts
.ret: ret

; 1文字出力
putc:
    push dx
    push ax
    mov dx, SCU_SST
.w: in al, dx
    test al, TX_READY  ; TX Ready?
    jz .w
    mov dx, SCU_DATA
    pop ax
    push ax
    out dx, al
    pop ax
    pop dx
    ret

; 1文字入力
getc:
    push dx
    mov dx, SCU_SST
.w: in al, dx
    test al, RX_READY  ; RX Ready?
    jz .w
    mov dx, SCU_DATA
    in al, dx
    pop dx
    ret

; 1文字入力　エコーバックあり
getc_echo:
    call getc
    push ax
    call putc
    pop ax
    ret

; 改行出力
putc_crlf:
    mov al, 0x0D
    call putc
    mov al, 0x0A
    jmp putc

; -----------------------------------------------------------------
; Helper: 1ワードを4文字のHEXで表示 (例: 0x2F3F -> "2", "F", "3", "F")
; Input: AX
; -----------------------------------------------------------------
print_hex_word:
    push ax
    mov al, ah
    call print_hex_byte
    pop ax

; -----------------------------------------------------------------
; Helper: 1バイトを2文字のHEXで表示 (例: 0x3F -> "3", "F")
; Input: AL
; -----------------------------------------------------------------
print_hex_byte:
    push ax
    push cx

    ; 上位バイトの表示
    push ax
    shr al, 4
    call .digit

    ; 下位バイトの表示
    pop ax
    and al, 0x0F
    call .digit

    pop cx
    pop ax
    ret

; 数値を16進数文字に変換して表示 (0-15 -> 0-9, A-F)
.digit:
    add al, '0'
    cmp al, '9'
    jbe .p
    add al, 7
.p: call putc
    ret

; -----------------------------------------------------------------
; Helper: 4文字のHEXを受信して1ワード(16bit)の数値にする
; Input:  Serial (例: "1", "0", "0", "0")
; Output: AX = 0x1000
; -----------------------------------------------------------------
get_hex_word:
    push bx
    call get_hex_byte_echo
    mov bh, al
    call get_hex_byte_echo
    mov bl, al
    mov ax, bx
    pop bx
    ret

; 16進数2桁入力　エコーバック有り
get_hex_byte_echo:
    push bx
    call getc_echo
    call hex_char_to_bin
    shl al, 4
    mov bl, al
    call getc_echo
    call hex_char_to_bin
    or al, bl
    pop bx
    ret

; -----------------------------------------------------------------
; Helper: 2文字のHEXを受信して1バイトの数値にする
; Input:  Serial (例: "3", "F")
; Output: AL = 0x3F
; -----------------------------------------------------------------
get_hex_byte:
    push bx             ; BH/BLを使うので退避（メインでアドレス用に使ってるため重要）

    ; 上位4bit
    call getc
    call hex_char_to_bin
    shl al, 4
    mov bl, al          ; 一時保存
    
    ; 下位4bit
    call getc
    call hex_char_to_bin
    or al, bl           ; 上位を合成して結果はALへ
    pop bx
    ret

; -----------------------------------------------------------------
; Helper: ASCII文字を数値へ (0-9, A-F -> 0-15)
; Input: AL (ASCII)
; Output: AL (Binary)
; -----------------------------------------------------------------
hex_char_to_bin:
    sub al, '0'
    cmp al, 9
    jbe .done
    sub al, 7           ; 'A'-'F'対応
    and al, 0x0F        ; 小文字対応も含めてざっくりマスク
.done:
    ret

; -----------------------------------------------------------------
; Helper: スペースなどを読み飛ばす
; -----------------------------------------------------------------
skip_space:
    call getc_echo
    ret

; -----------------------------------------------------------------
; Helper: エラーメッセージ出力後モニタに戻る
; -----------------------------------------------------------------
error:
    mov si, msg_error
    call puts
    jmp monitor_loop

;==========================================================
; Interrupt Handler
;==========================================================

; --- 各ベクタ用スタブ (Entry Points) ---
; ベクタ番号をスタックに積んで共通処理へジャンプします

_isr_stub_0:  push 0x0          ; 0: Division by zero
              jmp _default_int_handler
_isr_stub_1:  push 0x1          ; 1: Break flag
              jmp _default_int_handler
_isr_stub_2:  push 0x2          ; 2: NMI
              jmp _default_int_handler
_isr_stub_3:  push 0x3          ; 3: BRK3
              jmp _default_int_handler
_isr_stub_4:  push 0x4          ; 4: BRKV
              jmp _default_int_handler
_isr_stub_5:  push 0x5          ; 5: CHKIND
              jmp _default_int_handler

_isr_stub_20: push 0x0020       ; 32: ICU INTP0
              jmp _default_int_handler
_isr_stub_21: push 0x0021       ; 33: ICU INTP1
              jmp _default_int_handler
_isr_stub_22: push 0x0022       ; 34: ICU INTP2
              jmp _default_int_handler
_isr_stub_23: push 0x0023       ; 35: ICU INTP3
              jmp _default_int_handler
_isr_stub_24: push 0x0024       ; 36: ICU INTP4
              jmp _default_int_handler
_isr_stub_25: push 0x0025       ; 37: ICU INTP5
              jmp _default_int_handler
_isr_stub_26: push 0x0026       ; 38: ICU INTP6
              jmp _default_int_handler

; Note: Vector 27h (INTP7) は _pic_dispatch_handler で使用中なのでここには含めません

; ==========================================================
; Default Interrupt Handler (Trap for unused interrupts)
; ==========================================================

; --- 共通処理部 (Common Handler) ---
_default_int_handler:
    ; 1. 全レジスタを退避 (V53は80186互換なのでPUSHAが使えます)
    pusha               ; DI, SI, BP, SP, BX, DX, CX, AX (16 bytes)
    push ds
    push es

    ; 2. セグメントをモニタ用に設定 (表示ルーチンを使うため)
    mov  ax, cs
    mov  ds, ax
    mov  es, ax
    mov  bp, sp

    ; --- メッセージ表示 ---
    mov  si, msg_int_trap
    call puts           ; "** INT "

    ; --- ベクタ番号の表示 ---
    mov  ax, [bp+20]    ; ベクタ番号を取得
    call print_hex_byte ; 表示 (例: 25)

    mov  si, msg_detected
    call puts           ; " detected **" (改行含む)

    ; 4. レジスタ表示 (スタックから読み出して表示)
    ; Stack Layout after pushes:
    ; BP+0: ES　最後にpushしたもの
    ; BP+2: DS
    ; BP+4: DI　pushaの開始
    ; BP+6: SI
    ; BP+8: BP (Old)
    ; BP+10: SP (Original)
    ; BP+12: BX
    ; BP+14: DX
    ; BP+16: CX
    ; BP+18: AX pushaの終了
    ; BP+20: Vector Number スタブでpushした値
    ; BP+22: IP 割り込み発生時の戻り先
    ; BP+24: CS (Return Addr)
    ; BP+26: Flags
    
    ; AX
    mov  si, msg_ax
    call puts
    mov  ax, [bp+18]        ; PUSHAで保存されたAX
    call print_hex_word     ; 4桁HEX表示ルーチン

    ; BX
    mov  si, msg_bx
    call puts
    mov  ax, [bp+12]
    call print_hex_word

    ; CX
    mov  si, msg_cx
    call puts
    mov  ax, [bp+16]
    call print_hex_word

    ; DX
    mov  si, msg_dx
    call puts
    mov  ax, [bp+14]
    call print_hex_word

    call putc_crlf

    ; --- 中断地点 (CS:IP) の表示 ---
    mov  si, msg_addr
    call puts           ; " Stop at "
    mov  ax, [bp+24]    ; Stack上の CS
    call print_hex_word
    mov  al, ':'
    call putc
    mov  ax, [bp+22]    ; Stack上の IP
    call print_hex_word

    call putc_crlf

    mov  ax, [bp+20]    ; Stack上の ベクタ番号
    cmp  ax, 0x20
    jb   .no_eoi         ; ベクタ番号 < 20h (PIC/ICU以外) ならEOI不要

    ; --- EOI (End of Interrupt) to PIC, ICU ---
    mov al, 20h         ; Non-specific EOI
    out PIC_REG0, al    ; 外部PIC (Slave) の割り込み完了
    mov dx, ICU_REG0    ; V53内蔵ICU (Master) の割り込み完了
    out dx, al
.no_eoi:

    pop  es
    pop  ds
    popa
    add  sp, 2          ; スタブでPUSHしたベクタ番号分(2byte)をスタックから捨てる
    iret

; ==========================================================
; PIC Dispatch Handler (Vector 27h)
; Handles: Timer, Serial, SCSI, PPI via PIC uPD71059
; ==========================================================
_pic_dispatch_handler:
    pusha
    push ds
    push es

    ; DS設定 (Tiny Model)
    mov ax, cs
    mov ds, ax

    ; --- 1. PICのISR (In-Service Register) を読む ---
    ; OCW3: 0000_1011 (0x0B) -> RR=1, RIS=1 (Read ISR)
    mov al, 0x0B
    out PIC_REG0, al
    in  al, PIC_REG0    ; AL = 現在処理中の割り込みビット (ISR)

    ; --- 2. 要因判定と分岐 ---
    
    test al, 01h        ; Bit 0: Timer 0 (System Tick)
    jnz .handle_timer0

    test al, 02h        ; Bit 1: SCSI
    jnz .handle_scsi

    test al, 04h        ; Bit 2: Timer 1
    jnz .handle_timer1

    test al, 08h        ; Bit 3: USART Rx
    jnz .handle_usart_rx

    test al, 10h        ; Bit 4: USART Tx
    jnz .handle_usart_tx

    test al, 20h        ; Bit 5: SCU Rx
    jnz .handle_scu_rx

    test al, 40h        ; Bit 6: SCU Tx
    jnz .handle_scu_tx

    test al, 80h        ; Bit 7: PPI
    jnz .handle_ppi

    ; 該当なしの場合は無視
    jmp .eoi_exit

; --- 各ハンドラ処理 ---

.handle_timer0:
    ; INTP0: Timer 0 (Tick)
    ; --- 32bit カウンタのインクリメント ---
    inc word [tick_counter_lo]
    jnz .skip_carry
    inc word [tick_counter_hi]
.skip_carry:
    jmp .eoi_exit

.handle_scsi:
    ; INTP1: SCSIC
    mov si, msg_int_scsi
    call puts
    jmp .eoi_exit

.handle_timer1:
    ; INTP2: ユーザ用タイマー
    mov si, msg_int_timer1
    call puts
    jmp .eoi_exit

.handle_usart_rx:
    ; INTP3: USART受信準備完了割り込み
    mov si, msg_int_usart_rx
    call puts
    jmp .eoi_exit

.handle_usart_tx:
    ; INTP4: USART送信完了割り込み
    mov si, msg_int_usart_tx
    call puts
    jmp .eoi_exit

.handle_scu_rx:
    ; INTP5: SCU受信準備完了割り込み
    mov si, msg_int_scu_rx
    call puts
    jmp .eoi_exit

.handle_scu_tx:
    ; INTP6: SCU送信完了割り込み
    mov si, msg_int_scu_tx
    call puts
    jmp .eoi_exit

.handle_ppi:
    ; INTP7: PPI割り込み
    mov si, msg_int_ppi
    call puts
    jmp .eoi_exit

; --- 終了処理 ---
.eoi_exit:
    ; --- EOI (End of Interrupt) to PIC ---
    mov al, 20h     ; Non-specific EOI

    ; 外部PIC (Slave) の割り込み完了
    out PIC_REG0, al

    ; V53内蔵ICU (Master) の割り込み完了
    mov dx, ICU_REG0 
    out dx, al

    pop es
    pop ds
    popa
    iret

;--------------------------------------
; 未定義割り込みベクタ用の簡易トラップ
;--------------------------------------
_default_int_unknown_handler:
    ; 想定外の割り込みが発生したため、
    ; 画面に "UNKNOWN INT" と出して停止する
    cli                 ; 多重割り込み禁止

    ; 1. 全レジスタを退避 (V53は80186互換なのでPUSHAが使えます)
    pusha               ; DI, SI, BP, SP, BX, DX, CX, AX の順でPush
    push ds
    push es

    ; 2. セグメントをモニタ用に設定 (表示ルーチンを使うため)
    mov  ax, cs
    mov  ds, ax
    mov  es, ax

    ; 3. スタックフレームへのポインタ設定
    mov  bp, sp

    mov si, msg_unknown_int
    call puts

    ; 4. レジスタ表示 (スタックから読み出して表示)
    ; Stack Layout after pushes:
    ; BP+0: ES
    ; BP+2: DS
    ; BP+4: DI
    ; BP+6: SI
    ; BP+8: BP (Old)
    ; BP+10: SP (Original)
    ; BP+12: BX
    ; BP+14: DX
    ; BP+16: CX
    ; BP+18: AX
    ; BP+20: IP (Return Addr)
    ; BP+22: CS (Return Addr)
    ; BP+24: Flags
    
    ; AX
    mov  si, msg_ax
    call puts
    mov  ax, [bp+18]        ; PUSHAで保存されたAX
    call print_hex_word     ; 4桁HEX表示ルーチン

    ; BX
    mov  si, msg_bx
    call puts
    mov  ax, [bp+12]
    call print_hex_word

    ; CX
    mov  si, msg_cx
    call puts
    mov  ax, [bp+16]
    call print_hex_word

    ; DX
    mov  si, msg_dx
    call puts
    mov  ax, [bp+14]
    call print_hex_word

    call putc_crlf

    ; --- 中断地点 (CS:IP) の表示 ---
    ; PUSHA(16byte) + DS(2) + ES(2) = 20byte
    ; その上が割り込み発生時の IP, CS, Flags です
    
    mov  si, msg_addr
    call puts           ; " Stop at "
    mov  ax, [bp+22]    ; Stack上の CS
    call print_hex_word
    mov  al, ':'
    call putc
    mov  ax, [bp+20]    ; Stack上の IP
    call print_hex_word

    call putc_crlf

    ; 5. 復帰処理
    ; ここでモニタのコマンド待ちへ強制ジャンプします
    ; (レジスタはスタックに残ったままになりますが、モニタ再起動でリセットされる前提)
    jmp  start  ; モニタの開始ラベルへ

    ; 停止（暴走を防ぐ）
;.halt:
;    hlt
;    jmp .halt

; =================================================================
; Data
; =================================================================
msg_boot: db 0x0D,0x0A,"**  V53 RAM MONITOR v0.13 2026-04-23  **",0x0D,0x0A,0
msg_load: db "Load HEX...",0
msg_ok:   db "OK",0
msg_go:   db "Go!",0

msg_prompt: db "> ", 0
msg_error:  db "Error", 0x0D, 0x0A, 0
msg_unknown:db "Unknown cmd", 0x0D, 0x0A, 0
msg_in_res: db "Val: ", 0
msg_done:   db " Done", 0x0D, 0x0A, 0
msg_bar:    db " | ", 0
msg_help:   db "Cmds: D <Seg> <Off>, L <Seg>, G <Seg> <Off>, W <Seg> <Off> <Val>, I <Port>, O <Port> <Val>, S <Start_port> <End_port>, T <Val> ?", 0x0D, 0x0A, 0
msg_scan_start: db "Scanning I/O (Press any key to abort)...", 0x0D, 0x0A, 0
msg_space:      db "  ", 0
msg_abort:      db "Aborted.", 0x0D, 0x0A, 0
msg_tick:   db "Tick: ", 0

; 割り込みハンドラメッセージ
msg_int_trap: db "** INT ", 0
msg_detected: db " detected **", 0
msg_ax:   db " AX=", 0
msg_bx:   db " BX=", 0
msg_cx:   db " CX=", 0
msg_dx:   db " DX=", 0
msg_addr: db " Stop at CS:IP = ", 0

; PICディスパッチハンドラメッセージ
msg_int_scsi:       db "** PIC INTP1 SCSI **", 0x0D, 0x0A, 0
msg_int_timer1:     db "** PIC INTP2 Timer1 **", 0x0D, 0x0A, 0
msg_int_usart_rx:   db "** PIC INTP3 USART Rx **", 0x0D, 0x0A, 0
msg_int_usart_tx:   db "** PIC INTP4 USART Tx **", 0x0D, 0x0A, 0
msg_int_scu_rx:     db "** PIC INTP5 SCU Rx **", 0x0D, 0x0A, 0
msg_int_scu_tx:     db "** PIC INTP6 SCU Tx **", 0x0D, 0x0A, 0
msg_int_ppi:        db "** PIC INTP7 PPI **", 0x0D, 0x0A, 0

; 未定義割り込みハンドラのメッセージ
msg_unknown_int: db 0x0D, 0x0A, "!!! UNKNOWN INTERRUPT !!!", 0x0D, 0x0A, 0

; 変数
dump_seg:   dw  0x0000  ; Dump: セグメント保存用
dump_off:   dw  0x0000  ; Dump: オフセット保存用
load_seg:   dw  0x0000  ; Load: ターゲットセグメント
tick_counter_lo: dw 0x0000  ; Tick: 下位16bit
tick_counter_hi: dw 0x0000  ; Tick: 上位16bit