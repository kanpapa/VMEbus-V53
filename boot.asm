; =================================================================
; V53 Monitor System (v1.4 Baud Rate Cmd)
; Target: NEC V53 (VME Board) & DOSBox-X Simulation
; =================================================================
%include "v53.inc"

; --- ビルド方法 ---
; DOSBox: nasm -f bin -dSIM boot.asm -o boot.com
; Real:   nasm -f bin boot.asm -o boot.bin
; -----------------

; --- RAM上の変数マップ (ES=0x0000 を前提に使用) ---
; 0x0000-0x03FF は割り込みベクタ(IVT)なので避ける
%define VAR_DUMP_SEG    0x0400  ; Dump: セグメント保存用
%define VAR_DUMP_OFF    0x0402  ; Dump: オフセット保存用
%define VAR_LOAD_SEG    0x0404  ; Load: ターゲットセグメント

%ifdef SIM
    ; --- Simulation Mode ---
    org 0x100
    cpu 186
    %define UART_DATA   0x3F8
    %define UART_LSR    0x3FD
    %define TX_READY    0x20
    %define RX_READY    0x01
%else
    ; --- Real Hardware Mode ---
    org 0
    cpu 186
    %define UART_DATA   V53_SCU_DATA
    %define UART_LSR    V53_SCU_STS
    %define TX_READY    SCU_STS_TXRDY
    %define RX_READY    SCU_STS_RXRDY
    %define ROM_SIZE    0x20000
%endif

section .text

start:
%ifdef SIM
    xor ax, ax
    mov es, ax
%else
    cli

    ; セグメント設定
    ; CS = ROM (F800 or E000)
    ; DS = ROM (定数データ読み出し用)
    ; ES = RAM (変数書き込み用, 0x0000)
    ; SS = RAM

    mov ax, cs
    mov ds, ax          ; DSはCSと一緒(ROM)に向ける
    
    xor ax, ax
    mov es, ax          ; ESはRAM(0x0000)に向ける
    
    mov ss, ax
    mov sp, 0x8000      ; Stack at 32KB
    
    ; SCU初期化 (9600bps)
    mov dx, V53_SCU_BRG
    mov al, BRG_9600
    out dx, al
    mov dx, V53_SCU_MODE
    mov al, 0x4E
    out dx, al
    mov dx, V53_SCU_CMD
    mov al, 0x15
    out dx, al
%endif

    ; 変数初期化 (RAMエリアをクリア)
    mov word [es:VAR_DUMP_SEG], 0x0000
    mov word [es:VAR_DUMP_OFF], 0x0000
    mov word [es:VAR_LOAD_SEG], 0x2000

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

    cmp bl, 'b'     ; baud command
    je do_baud
    cmp bl, 'B'
    je do_baud

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
    mov [es:VAR_DUMP_SEG], ax
    call skip_space
    call get_hex_word
    mov [es:VAR_DUMP_OFF], ax
    ; ここでEnter待ちをするか、そのまま実行するか
    ; 今回はパラメータ入力後にEnterを押したと仮定して改行
    
.dump_run:
    call putc_crlf      ; ★実行直前に改行

.dump_run_start:
    mov cx, 4                   ; 4行表示する
    
.line_loop:
    push cx
    
    mov ax, [es:VAR_DUMP_SEG]   ; セグメントの表示
    call print_hex_word
    mov al, ':'                 ; 区切り文字の:を表示
    call putc
    mov ax, [es:VAR_DUMP_OFF]   ; オフセットの表示
    call print_hex_word
    mov al, ' '                 ; 区切り文字のスペースを表示
    call putc
    
    push ds
    mov ds, [es:VAR_DUMP_SEG]
    mov si, [es:VAR_DUMP_OFF]
    
    mov cx, 16                  ; 16回繰り返すカウンタ
.hex_loop:
    mov al, [si]
    call print_hex_byte         ; メモリ内容の表示
    mov al, ' '                 ; 区切り文字のスペースを表示
    call putc
    inc si                      ; 次のアドレスにする
    loop .hex_loop              ; 16回繰り返し
    
    mov [es:VAR_DUMP_OFF], si   ; オフセットを更新
    
    pop ds
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
    mov ax, [es:VAR_LOAD_SEG]
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
; Command: Go (Execute)
; Format: G <Segment> <Offset>
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


; =================================================================
; Command: Baud Rate (B)
; =================================================================
do_baud:
    call putc_crlf
    mov si, msg_spd_menu
    call puts
    
    call getc_echo
    mov bl, al          ; 選択肢を保存
    call putc_crlf

    ; --- ボーレート値の決定 ---
    cmp bl, '1'
    je .set_9600
    cmp bl, '2'
    je .set_19200
    jmp .apply
    cmp bl, '3'
    je .set_38400
    jmp .apply

    ; 無効な入力
    jmp monitor_loop

.set_9600:
    mov bh, BRG_9600    ; V53用設定値
    jmp .apply
.set_19200:
    mov bh, BRG_19200
    jmp .apply
.set_38400:
    mov bh, BRG_38400
    jmp .apply

.apply:
    ; ユーザーへの案内
    mov si, msg_spd_wait
    call puts

    ; 送信完了待ち (文字化け防止)
    ; V53の実機ではTX_READYを確認してから少し待つのが安全
    call wait_tx_flush

%ifdef SIM
    ; Simulation
    ; DOSBox (TCP) では速度概念がないので何もしないが、
    ; 気分を出すために少しウェイトを入れる
    mov cx, 0xFFFF
.sim_wait:
    loop .sim_wait
%else
    ; 実機: ボーレートレジスタ書き換え
    mov dx, V53_SCU_BRG
    mov al, bh
    out dx, al
%endif

    ; --- 新しい速度での同期待ち ---
    ; ここでユーザーがTerminalの設定を変えるのを待つ
.sync_wait:
    call getc       ; Wait for Space key
    cmp al, ' '
    jne .sync_wait

    call putc_crlf
    mov si, msg_ok
    call puts
    jmp monitor_loop

    ; --- Helper: 送信バッファが空になるのを待つ ---
wait_tx_flush:
    push dx
    push ax
    mov dx, UART_LSR
.w: in al, dx
    test al, TX_READY
    jz .w
    
    ; 念のため空ループで少し待機 (V53の処理速度対策)
    mov cx, 1000
.delay:
    nop
    loop .delay
    
    pop ax
    pop dx
    ret

; =================================================================
; Utilities
; =================================================================

; 文字列出力
puts:
    mov al, [si]
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
    mov dx, UART_LSR
.w: in al, dx
    test al, TX_READY
    jz .w
    mov dx, UART_DATA
    pop ax
    push ax
    out dx, al
    pop ax
    pop dx
    ret

; 1文字入力
getc:
    push dx
    mov dx, UART_LSR
.w: in al, dx
    test al, RX_READY
    jz .w
    mov dx, UART_DATA
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

; =================================================================
; Data
; =================================================================
msg_boot: db 0x0D,0x0A,"V53 Monitor Ready (v1.4)",0x0D,0x0A,0
msg_load: db "Load HEX...",0
msg_ok:   db "OK",0
msg_go:   db "Go!",0
msg_spd_menu: db "1:9600 2:19200 3:38400",0x0D,0x0A,"Select: ",0
msg_spd_wait: db 0x0D,0x0A,"Change Terminal speed, then press SPACE...",0

%ifndef SIM
    times ROM_SIZE - 16 - ($ - $$) db 0xFF
reset_vector:
    jmp 0xE000:0000
    times 16 - ($ - reset_vector) db 0xFF
%endif