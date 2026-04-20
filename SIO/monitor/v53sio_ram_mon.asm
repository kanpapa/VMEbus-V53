; =================================================================
; V53 RAM Monitor for DVE-554 v0.1 2026-04-18
; Target: DVE-554 SIO VME Board
; =================================================================

; --- ビルド方法 ---
; Real:   nasm -f bin v53sio_ram_mon.asm -o v53sio_ram_mon.bin -l v53sio_ram_mon.lst
; objcopy -I binary -O ihex --change-addresses=0x0000 v53sio_ram_mon.bin v53sio_ram_mon.hex
; -----------------

    org 0
    cpu 186

    ; V53 ICU (00C0Hに配置)
    %define ICU_REG0    0x000C0
    %define ICU_REG1    0x000C2

    ; V53 TCU (00D0Hに配置)
    %define TM0_CNT     0x000D0 ; Timer 0 Counter
    %define TM1_CNT     0x000D2 ; Timer 1 Counter
    %define TM2_CNT     0x000D4 ; Timer 2 Counter
    %define TM_CTL      0x000D6 ; Timer Control

    ; V53 DMAU (00E0Hに配置)
    ; DMAUはモニタでは使用しないため、レジスタ定義は省略します。

    ; V53 SCU (00F0Hに配置）
    ; SCUはモニタでは使用しないため、レジスタ定義は省略します。

    ; uPD72001 MPSC #1
    %define MPSC1_A_DATA 0x00A0 ; MPSC #1 Channel A Data Register
    %define MPSC1_A_CTRL 0x00A2 ; MPSC #1 Channel A Control Register
    %define MPSC1_B_DATA 0x00A4 ; MPSC #1 Channel B Data Register
    %define MPSC1_B_CTRL 0x00A6 ; MPSC #1 Channel B Control Register

    ; uPD72001 MPSC #2
    %define MPSC2_A_DATA 0x00A8 ; MPSC #2 Channel A Data Register
    %define MPSC2_A_CTRL 0x00AA ; MPSC #2 Channel A Control Register
    %define MPSC2_B_DATA 0x00AC ; MPSC #2 Channel B Data Register
    %define MPSC2_B_CTRL 0x00AE ; MPSC #2 Channel B Control Register

    %define TX_READY   0x04
    %define RX_READY   0x01

section .text

start:
    cli             ; 初期化中は割り込み禁止

    ; ---------------------------------------------
    ; 1. セグメントレジスタ初期化
    ; ---------------------------------------------
    push cs     ; CS -> DS
    pop ds
    push cs     ; CS -> ES
    pop es
    mov ax, cs  ; CS -> SS
    mov ss, ax
    mov sp, 0x7FFF
    ; ------------------------------

    ; --- 2. V53 システムレジスタ初期化 ---
    call v53_sysreg_init

    ; --- 3. TCU初期化  ---
    call v53_tcu_init

    ; --- 4. 物理IOの初期化（詳細不明） ---
    call dve554_io_init

    ; --- 5. MPSC の初期化 ---
    call mpsc_init
    
    ; --- 6. 割り込みベクタの初期化 ---
    xor ax, ax
    mov es, ax              ; ES = 0000h (Vector Table Segment)

    ; Vector 10h 登録
    mov word [es:0x40], _isr_int10h     ; オフセットを書き込み　0x10 * 4 = 0x40
    mov word [es:0x42], cs              ; 現在のコードセグメントを書き込み

    ; Vector 11h 登録
    mov word [es:0x44], _isr_int11h
    mov word [es:0x46], cs

    ; Vector 12h 登録
    mov word [es:0x48], _isr_int12h
    mov word [es:0x4A], cs

    ; Vector 13h 登録
    mov word [es:0x4C], _isr_int13h
    mov word [es:0x4E], cs
    
    ; Vector 14h 登録
    mov word [es:0x50], _isr_int14h
    mov word [es:0x52], cs

    ; Vector 15h 登録
    mov word [es:0x54], _isr_int15h
    mov word [es:0x56], cs

    ; Vector 16h 登録
    mov word [es:0x58], _isr_int16h
    mov word [es:0x5A], cs

    ; Vector 17h 登録
    mov word [es:0x5C], _isr_int17h
    mov word [es:0x5E], cs 


    ; Vector 20h (INTP0) 登録
    mov word [es:0x80], _isr_intp0      ; オフセットを書き込み　0x20 * 4 = 0x80
    mov word [es:0x82], cs              ; 現在のコードセグメントを書き込み

    ; Vector 21h (INTP1) 登録
    mov word [es:0x84], _isr_intp1
    mov word [es:0x86], cs

    ; Vector 22h (INTP2) 登録
    mov word [es:0x88], _isr_intp2
    mov word [es:0x8A], cs

    ; Vector 22h (INTP3) 登録
    mov word [es:0x8C], _isr_intp3
    mov word [es:0x8E], cs

    ; Vector 23h (INTP4) 登録
    mov word [es:0x90], _isr_intp4 
    mov word [es:0x92], cs

    ; Vector 24h (INTP5) 登録
    mov word [es:0x94], _isr_intp5
    mov word [es:0x96], cs

    ; Vector 25h (INTP6) 登録
    mov word [es:0x98], _isr_intp6
    mov word [es:0x9A], cs

    ; Vector 26h (INTP7) 登録
    mov word [es:0x9C], _isr_intp7
    mov word [es:0x9E], cs

    ; --- 7. ICU初期化 ---
    mov dx, ICU_REG0
    mov al, 12h     ; IIW1: 00010010b (Edge Trigger, Single)
    out dx, al

    mov dx, ICU_REG1
    mov al, 20h     ; IIW2: 00100000b (Vector Offset = 20h (INT 32))
    out dx, al

    mov al, 0ffh    ; IMKW: 11111111b (一旦割り込みをマスクする）
    out dx, al

    ; --- 8. 割り込み許可 ---
    sti

    mov al, 00h    ; IMKW: 00000000b (全マスクを解除）
    out dx, al

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
    mov dx, MPSC1_A_CTRL
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
    mov dx, MPSC1_A_DATA
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
    mov dx, MPSC1_A_CTRL
.wait_tx:
    in al, dx
    test al, TX_READY   ; D2: Tx Buffer Empty?
    jz .wait_tx
    mov dx, MPSC1_A_DATA
    pop ax
    out dx, al
    pop dx
    ret

; 1文字入力
getc:
    push dx
    mov dx, MPSC1_A_CTRL
.wait_rx:
    in al, dx
    test al, RX_READY   ; D0: RX Ready?
    jz .wait_rx
    mov dx, MPSC1_A_DATA
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

; ---------------------------------------------------------
; INTP0 (Vector 20h) ハンドラ　Timer0 (100Hz) 割り込み
; ---------------------------------------------------------
align 2
_isr_intp0:
    pusha               ; 全汎用レジスタ保存 (AX,CX,DX,BX,SP,BP,SI,DI)
    push ds             ; セグメントレジスタ保存
    push es

    ; --- DSの設定 (重要: 変数にアクセスするため) ---
    mov ax, cs
    mov ds, ax

    ; --- 32bit カウンタのインクリメント ---
    inc word [tick_counter_lo]
    jnz .skip_carry
    inc word [tick_counter_hi]
.skip_carry:
    ; --- EOI (End of Interrupt) 発行 ---
    ; これを送らないと次の割り込みが発生しません
    mov al, 20h         ; Non-Specific EOI
    mov dx, ICU_REG0
    out dx, al

    ; --- 復帰処理 ---
    pop es
    pop ds
    popa                ; 保存したレジスタをすべて復帰

    iret                ; 割り込みから復帰 (IP, CS, Flagsをpop)

; ---------------------------------------------------------
; INTP1 (Vector 21h) ハンドラ - 詳細不明
; ---------------------------------------------------------
align 2
_isr_intp1:
    pusha
    push ds
    push es

    ; 1. セグメントをモニタ用に設定 (表示ルーチンを使うため)
    mov  ax, cs
    mov  ds, ax
    mov  es, ax

    ; 2. 発生フラグをセット
    inc  word [intp1_flag]
    
    ; --- 画面表示 ---
    mov  si, msg_intp1
    call puts
    
    ; EOI発行
    mov  al, 20h
    mov  dx, ICU_REG0
    out  dx, al

    pop  es
    pop  ds
    popa
    iret

; ---------------------------------------------------------
; INTP2 (Vector 22h) ハンドラ - 詳細不明
; ---------------------------------------------------------
align 2
_isr_intp2:
    pusha
    push ds
    push es

    ; 1. セグメントをモニタ用に設定 (表示ルーチンを使うため)
    mov  ax, cs
    mov  ds, ax
    mov  es, ax

    ; 2. 発生フラグをセット
    inc  word [intp2_flag]
    
    ; --- 画面表示 ---
    mov  si, msg_intp2
    call puts

    ; EOI発行
    mov  al, 20h
    mov  dx, ICU_REG0
    out  dx, al

    pop  es
    pop  ds
    popa
    iret

; ---------------------------------------------------------
; INTP3 (Vector 23h) ハンドラ - 詳細不明
; ---------------------------------------------------------
align 2
_isr_intp3:
    pusha
    push ds
    push es

    ; 1. セグメントをモニタ用に設定 (表示ルーチンを使うため)
    mov  ax, cs
    mov  ds, ax
    mov  es, ax

    ; 2. 発生フラグをセット
    inc  word [intp3_flag]
    
    ; --- 画面表示 ---
    mov  si, msg_intp3
    call puts

    ; EOI発行
    mov  al, 20h
    mov  dx, ICU_REG0
    out  dx, al

    pop  es
    pop  ds
    popa
    iret

; ---------------------------------------------------------
; INTP4 (Vector 24h) ハンドラ - 詳細不明
; ---------------------------------------------------------
align 2
_isr_intp4:
    pusha
    push ds
    push es

    ; 1. セグメントをモニタ用に設定 (表示ルーチンを使うため)
    mov  ax, cs
    mov  ds, ax
    mov  es, ax

    ; 2. 発生フラグをセット
    inc  word [intp4_flag]
    
    ; --- 画面表示 ---
    ;mov  si, msg_intp4
    ;call puts

    ; EOI発行
    mov  al, 20h
    mov  dx, ICU_REG0
    out  dx, al

    pop  es
    pop  ds
    popa
    iret

; ---------------------------------------------------------
; INTP5 (Vector 25h) ハンドラ - 詳細不明
; ---------------------------------------------------------
align 2
_isr_intp5:
    pusha
    push ds
    push es

    ; 1. セグメントをモニタ用に設定 (表示ルーチンを使うため)
    mov  ax, cs
    mov  ds, ax
    mov  es, ax

    ; 2. 発生フラグをセット
    inc  word [intp5_flag]
    
    ; --- 画面表示 ---
    mov  si, msg_intp5
    call puts

    ; EOI発行
    mov  al, 20h
    mov  dx, ICU_REG0
    out  dx, al

    pop  es
    pop  ds
    popa
    iret

; ---------------------------------------------------------
; INTP6 (Vector 26h) ハンドラ - 詳細不明
; ---------------------------------------------------------
align 2
_isr_intp6:
    pusha
    push ds
    push es

    ; 1. セグメントをモニタ用に設定 (表示ルーチンを使うため)
    mov  ax, cs
    mov  ds, ax
    mov  es, ax

    ; 2. 発生フラグをセット
    inc  word [intp6_flag]
    
    ; --- 画面表示 ---
    mov  si, msg_intp6
    call puts

    ; EOI発行
    mov  al, 20h
    mov  dx, ICU_REG0
    out  dx, al

    pop  es
    pop  ds
    popa
    iret

; ---------------------------------------------------------
; INTP7 (Vector 27h) ハンドラ - 詳細不明
; ---------------------------------------------------------
align 2
_isr_intp7:
    pusha
    push ds
    push es

    ; 1. セグメントをモニタ用に設定 (表示ルーチンを使うため)
    mov  ax, cs
    mov  ds, ax
    mov  es, ax

    ; 2. 発生フラグをセット
    inc  word [intp7_flag]
    
    ; --- 画面表示 --- 大量にでるのでコメントアウト
    ;mov  si, msg_intp7
    ;call puts

    ; EOI発行
    mov  al, 20h
    mov  dx, ICU_REG0
    out  dx, al

    pop  es
    pop  ds
    popa
    iret

; ---------------------------------------------------------
; INT10h (Vector 10h) ハンドラ - 詳細不明
; ---------------------------------------------------------
align 2
_isr_int10h:
    pusha
    push ds
    push es

    ; 1. セグメントをモニタ用に設定 (表示ルーチンを使うため)
    mov  ax, cs
    mov  ds, ax
    mov  es, ax

    ; 2. 発生フラグをセット
    inc  word [int10h_flag]
    
    ; --- 画面表示 ---
    mov  si, msg_int10h
    call puts
    
    ; EOI発行
    mov  al, 20h
    mov  dx, ICU_REG0
    out  dx, al

    pop  es
    pop  ds
    popa
    iret

; ---------------------------------------------------------
; INT11h (Vector 11h) ハンドラ - 詳細不明
; ---------------------------------------------------------
align 2
_isr_int11h:
    pusha
    push ds
    push es

    ; 1. セグメントをモニタ用に設定 (表示ルーチンを使うため)
    mov  ax, cs
    mov  ds, ax
    mov  es, ax

    ; 2. 発生フラグをセット
    inc  word [int11h_flag]
    
    ; --- 画面表示 ---
    mov  si, msg_int11h
    call puts
    
    ; EOI発行
    mov  al, 20h
    mov  dx, ICU_REG0
    out  dx, al

    pop  es
    pop  ds
    popa
    iret
; ---------------------------------------------------------
; INT12h (Vector 12h) ハンドラ - 詳細不明
; ---------------------------------------------------------
align 2
_isr_int12h:
    pusha
    push ds
    push es

    ; 1. セグメントをモニタ用に設定 (表示ルーチンを使うため)
    mov  ax, cs
    mov  ds, ax
    mov  es, ax

    ; 2. 発生フラグをセット
    inc  word [int12h_flag]
    
    ; --- 画面表示 ---
    mov  si, msg_int12h
    call puts
    
    ; EOI発行
    mov  al, 20h
    mov  dx, ICU_REG0
    out  dx, al

    pop  es
    pop  ds
    popa
    iret
; ---------------------------------------------------------
; INT13h (Vector 13h) ハンドラ - 詳細不明
; ---------------------------------------------------------
align 2
_isr_int13h:
    pusha
    push ds
    push es

    ; 1. セグメントをモニタ用に設定 (表示ルーチンを使うため)
    mov  ax, cs
    mov  ds, ax
    mov  es, ax

    ; 2. 発生フラグをセット
    inc  word [int13h_flag]
    
    ; --- 画面表示 ---
    mov  si, msg_int13h
    call puts
    
    ; EOI発行
    mov  al, 20h
    mov  dx, ICU_REG0
    out  dx, al

    pop  es
    pop  ds
    popa
    iret
; ---------------------------------------------------------
; INT14h (Vector 14h) ハンドラ - 詳細不明
; ---------------------------------------------------------
align 2
_isr_int14h:
    pusha
    push ds
    push es

    ; 1. セグメントをモニタ用に設定 (表示ルーチンを使うため)
    mov  ax, cs
    mov  ds, ax
    mov  es, ax
    
    ; 2. 発生フラグをセット
    inc  word [int14h_flag]
    
    ; --- 画面表示 ---
    mov  si, msg_int14h
    call puts
    
    ; EOI発行
    mov  al, 20h
    mov  dx, ICU_REG0
    out  dx, al

    pop  es
    pop  ds
    popa
    iret
; ---------------------------------------------------------
; INT15h (Vector 15h) ハンドラ - 詳細不明
; ---------------------------------------------------------
align 2
_isr_int15h:
    pusha
    push ds
    push es

    ; 1. セグメントをモニタ用に設定 (表示ルーチンを使うため)
    mov  ax, cs
    mov  ds, ax
    mov  es, ax

    ; 2. 発生フラグをセット
    inc  word [int15h_flag]
    
    ; --- 画面表示 ---
    mov  si, msg_int15h
    call puts
    
    ; EOI発行
    mov  al, 20h
    mov  dx, ICU_REG0
    out  dx, al

    pop  es
    pop  ds
    popa
    iret
; ---------------------------------------------------------
; INT16h (Vector 16h) ハンドラ - 詳細不明
; ---------------------------------------------------------
align 2
_isr_int16h:
    pusha
    push ds
    push es

    ; 1. セグメントをモニタ用に設定 (表示ルーチンを使うため)
    mov  ax, cs
    mov  ds, ax
    mov  es, ax

    ; 2. 発生フラグをセット
    inc  word [int16h_flag]
    
    ; --- 画面表示 ---
    mov  si, msg_int16h
    call puts
    
    ; EOI発行
    mov  al, 20h
    mov  dx, ICU_REG0
    out  dx, al

    pop  es
    pop  ds
    popa
    iret
; ---------------------------------------------------------
; INT17h (Vector 17h) ハンドラ - 詳細不明
; ---------------------------------------------------------
align 2
_isr_int17h:
    pusha
    push ds
    push es

    ; 1. セグメントをモニタ用に設定 (表示ルーチンを使うため)
    mov  ax, cs
    mov  ds, ax
    mov  es, ax

    ; 2. 発生フラグをセット
    inc  word [int17h_flag]
    
    ; --- 画面表示 ---
    mov  si, msg_int17h
    call puts
    
    ; EOI発行
    mov  al, 20h
    mov  dx, ICU_REG0
    out  dx, al

    pop  es
    pop  ds
    popa
    iret

; --------------------------------------------------
;  V53 システムレジスタ初期化
; --------------------------------------------------
v53_sysreg_init:
    mov si, TABLE_V53_REG
.next:
    mov dx, [cs:si]      ; Port Number (16bit)
    cmp dx, 0xFFFF       ; Terminator
    je .done
    mov al, [cs:si+2]    ; Value (8bit)
    out dx, al
    add si, 3
    jmp .next
.done:
    ret

; --------------------------------------------------
; TCU (タイマーユニット) 初期化
; --------------------------------------------------
v53_tcu_init:
    mov si, TABLE_TCU_REG
.next:
    mov dx, [cs:si]      ; Port1 (16bit)
    cmp dx, 0xFFFF       ; Terminator
    je .done
    mov al, [cs:si+2]    ; Val1 (8bit)
    out dx, al
    mov dx, [cs:si+3]    ; Port2 (16bit)
    mov ax, [cs:si+5]    ; Val2 (16bit)
    out dx, al           ; Port2 Low
    mov al, ah
    out dx, al           ; Port2 High
    add si, 7
    jmp .next
.done:
    ret

; ---------------------------------------------------
; 物理IOの初期化
; ---------------------------------------------------
dve554_io_init:
    mov al, 0x00
    mov dx, 0x0086
    out dx, al
    mov dx, 0x0082
    out dx, al
    mov dx, 0x0080
    out dx, al
    ret

; ---------------------------------------------------
; MPSC1/2 初期化シーケンス
; ---------------------------------------------------
mpsc_init:
; --- [Phase 1: Hardware Reset] ---
;   MPSC #1のチャネルA/Bに対して、リセットシーケンスを実行
    mov dx, MPSC1_A_CTRL
    mov al, 0
    out dx, al          ; Pointer Reset 1
    out dx, al          ; Pointer Reset 2 

    mov dx, MPSC1_B_CTRL
    mov al, 0
    out dx, al          ; Pointer Reset 1 
    out dx, al          ; Pointer Reset 2 

    ; Channel Reset (CR0: 0x18)
    mov dx, MPSC1_A_CTRL
    mov al, 0x18        ; Channel Reset command 
    out dx, al          ; Direct Write to WR0

    mov dx, MPSC1_B_CTRL
    mov al, 0x18
    out dx, al
    
    ; MPSC #2のチャネルA/Bに対しても同様のリセットシーケンスを実行
    mov dx, MPSC2_A_CTRL
    mov al, 0
    out dx, al          ; Pointer Reset 1
    out dx, al          ; Pointer Reset 2 

    mov dx, MPSC2_B_CTRL
    mov al, 0
    out dx, al          ; Pointer Reset 1 
    out dx, al          ; Pointer Reset 2 

    ; Channel Reset (CR0: 0x18)
    mov dx, MPSC2_A_CTRL
    mov al, 0x18        ; Channel Reset command 
    out dx, al          ; Direct Write to WR0

    mov dx, MPSC2_B_CTRL
    mov al, 0x18
    out dx, al

    ; リセット後の安定待ち
    mov cx, 100
.wait_res:
    nop
    nop
    nop
    loop .wait_res

    ; CR4: 送受信共通の動作設定
    mov al, 4
    mov bl, 0x44        ; x16, Async, ストップビット 1bit，パリティなし
    call mpsc_write_both

    ; CR2: システム全体の構成（割り込み/DMAモードや優先順位）を設定
    ; CR2B
    mov dx, MPSC1_B_CTRL       ; MPSC #1 Ch.B Control Port
    mov al, 02h                ; CR2Bを選択
    out dx, al
    mov al, 10h         ; ベクタベースを 10h に設定
    out dx, al

    ; CR1: バスインターフェース、割り込みおよびDMAの設定
    mov al, 1
    ;mov bl, 0x00       ; すべての割り込みとDMAを無効化
    mov bl, 12h         ; D4-D3=10: 全受信文字で割り込み
                        ; D1=1: 送信割り込み有効
                        ; D0=0: 外部要因(E/S)割り込み無効
    call mpsc_write_both
    
    ; CR12: ボーレートジェネレータ（BRG）の割り込みとレジスタ書き込み設定 
    ; MPSC #1のチャネルA/Bに対して、BRGレジスタセットモードを有効化し、ボーレートの値を設定
    mov dx, MPSC1_A_CTRL
    mov al, 12          ; Select CR12
    out dx, al
    mov al, 1           ; 受信BRGレジスタセットモード有効 (D0=1)
    out dx, al
    mov al, 0x1e        ; 下位バイトの値
    out dx, al
    mov al, 0x00        ; 上位バイトの値
    out dx, al
    
    mov dx, MPSC1_B_CTRL
    mov al, 12          ; Select CR12
    out dx, al
    mov al, 2           ; 送信BRGレジスタセットモード有効
    out dx, al
    mov al, 0x1e        ; 下位バイトの値
    out dx, al
    mov al, 0x00        ; 上位バイトの値
    out dx, al
    
    mov dx, MPSC1_A_CTRL
    mov al, 12          ; Select CR12
    out dx, al
    mov al, 1           ; 受信BRGレジスタセットモード有効 (D0=1)
    out dx, al
    mov al, 0x1e        ; 下位バイトの値
    out dx, al
    mov al, 0x00        ; 上位バイトの値
    out dx, al
    
    mov dx, MPSC1_B_CTRL
    mov al, 12          ; Select CR12
    out dx, al
    mov al, 2           ; 送信BRGレジスタセットモード有効
    out dx, al
    mov al, 0x1e        ; 下位バイトの値
    out dx, al
    mov al, 0x00        ; 上位バイトの値
    out dx, al

    ; MPSC #2のチャネルA/Bに対して、BRGレジスタセットモードを有効化し、ボーレートの値を設定
    mov dx, MPSC2_A_CTRL
    mov al, 12          ; Select CR12
    out dx, al
    mov al, 1           ; 受信BRGレジスタセットモード有効 (D0=1)
    out dx, al
    mov al, 0x1e        ; 下位バイトの値
    out dx, al
    mov al, 0x00        ; 上位バイトの値
    out dx, al
    
    mov dx, MPSC2_B_CTRL
    mov al, 12          ; Select CR12
    out dx, al
    mov al, 2           ; 送信BRGレジスタセットモード有効
    out dx, al
    mov al, 0x1e        ; 下位バイトの値
    out dx, al
    mov al, 0x00        ; 上位バイトの値
    out dx, al
    
    mov dx, MPSC2_A_CTRL
    mov al, 12          ; Select CR12
    out dx, al
    mov al, 1           ; 受信BRGレジスタセットモード有効 (D0=1)
    out dx, al
    mov al, 0x1e        ; 下位バイトの値
    out dx, al
    mov al, 0x00        ; 上位バイトの値
    out dx, al
    
    mov dx, MPSC2_B_CTRL
    mov al, 12          ; Select CR12
    out dx, al
    mov al, 2           ; 送信BRGレジスタセットモード有効
    out dx, al
    mov al, 0x1e        ; 下位バイトの値
    out dx, al
    mov al, 0x00        ; 上位バイトの値
    out dx, al

    ; CR15: クロックソースとピン機能の選択
    mov al, 15
    mov bl, 0x56        ; ボーレートジェネレータ使用
    call mpsc_write_both

    ; CR14: BRGの動作許可とソース設定
    mov al, 14
    mov bl, 0x07        ; BRGを動作させるソースクロックとして、システムクロック（CLK）を選択,送受信BRGカウント有効
    call mpsc_write_both

    ; CR10: データエンコーディングなどの設定
    mov al, 10
    mov bl, 0x00        ; データフォーマットとしてNRZ方式を選択
    call mpsc_write_both

    ; CR3: 受信動作の有効化
    mov al, 3
    mov bl, 0xC1        ; データ 8bit，受信イネーブル
    call mpsc_write_both
    
    ; CR5: 送信動作の有効化とモデム制御ピンのアサート
    mov al, 5
    mov bl, 0xEA        ; データ 8bit，送信イネーブル
    call mpsc_write_both
    
    ret

; --- Helper: Write to both MPSC #1, MPSC #2 ---
; Input: AL = Register Index, BL = Value
mpsc_write_both:
    ; MPSC #1 A-CHANNEL
    mov dx, MPSC1_A_CTRL
    out dx, al          ; Write Index
    xchg al, bl
    out dx, al          ; Write Data
    xchg al, bl
    
    ; MPSC #1 B-CHANNEL
    mov dx, MPSC1_B_CTRL
    out dx, al          ; Write Index
    xchg al, bl
    out dx, al          ; Write Data
    xchg al, bl

    ; MPSC #2 A-CHANNEL
    mov dx, MPSC2_A_CTRL
    out dx, al          ; Write Index
    xchg al, bl
    out dx, al          ; Write Data
    xchg al, bl
    
    ; MPSC #2 B-CHANNEL
    mov dx, MPSC2_B_CTRL
    out dx, al          ; Write Index
    xchg al, bl
    out dx, al          ; Write Data
    xchg al, bl

    ret

; --------------------------------------------------
; V53システムレジスタ設定テーブル
; --------------------------------------------------
ALIGN 2
TABLE_V53_REG:
    db 0xFE, 0xFF, 0x00     ; FFFE (SCTL) = 00h 16bit I/O boundary
    db 0xFD, 0xFF, 0x06     ; FFFD (OPSEL)= 06h Enable ICU,TCU  Disable DMAU,SCU
    db 0xFC, 0xFF, 0x00     ; FFFC (OPHA) = 00h
    db 0xFB, 0xFF, 0xE0     ; FFFB (DULA) = E0h DCU:00E0h
    db 0xFA, 0xFF, 0xC0     ; FFFA (IULA) = C0h ICU:00C0h
    db 0xF9, 0xFF, 0xD0     ; FFF9 (TULA) = D0h TCU:00D0h
    db 0xF8, 0xFF, 0xF0     ; FFF8 (SULA) = F0h SCU:00F0h
    db 0xEA, 0xFF, 0x00     ; FFEA (WMB0) = 00h
    db 0xEB, 0xFF, 0x00     ; FFEB (WCY1) = 00h
    db 0xEC, 0xFF, 0x00     ; FFEC (WCY0) = 00h
    db 0xF3, 0xFF, 0x73     ; FFF3 (WMB1) = 73h
    db 0xED, 0xFF, 0x00     ; FFED (WAC)  = 00h
    db 0xF4, 0xFF, 0x10     ; FFF4 (WCY2) = 10h
    db 0xF5, 0xFF, 0x22     ; FFF5 (WCY3) = 22h
    db 0xF6, 0xFF, 0x10     ; FFF6 (WCY4) = 10h
    db 0xF2, 0xFF, 0x00     ; FFF2 (RFC)  = 00h
    db 0xE9, 0xFF, 0x00     ; FFE9 (BRC)  = 00h
    db 0xF0, 0xFF, 0x02     ; FFF0 (TCKS) = 02h
    db 0xF1, 0xFF, 0x00     ; FFF1 (SBCR) = 00h
    db 0xFF, 0xFF, 0xFF     ; 終端マーカー

; --------------------------------------------------
; TCU タイマー設定テーブル
; --------------------------------------------------
ALIGN 2
TABLE_TCU_REG:
    ; Port1, Val1, Port2, Val2(16)
    db 0xD6, 0x00, 0x36, 0xD0, 0x00, 0x20, 0x4E ; T0設定
    db 0xD6, 0x00, 0x70, 0xD2, 0x00, 0x05, 0x0D ; T0最大値A
    db 0xD6, 0x00, 0xB0, 0xD4, 0x00, 0x05, 0x0D ; T0最大値B
    db 0xFF, 0xFF           ; 終端マーカー

; =================================================================
; Data
; =================================================================
msg_boot: db 0x0D,0x0A,"**  V53 RAM MONITOR for DVE-554 v0.1 2026-04-18  **",0x0D,0x0A,0
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
msg_intp0: db "** INTP0 **", 0
msg_intp1: db "** INTP1 **", 0
msg_intp2: db "** INTP2 **", 0
msg_intp3: db "** INTP3 **", 0
msg_intp4: db "** INTP4 **", 0
msg_intp5: db "** INTP5 **", 0
msg_intp6: db "** INTP6 **", 0
msg_intp7: db "** INTP7 **", 0

msg_int10h: db "** INT10h **", 0
msg_int11h: db "** INT11h **", 0
msg_int12h: db "** INT12h **", 0
msg_int13h: db "** INT13h **", 0
msg_int14h: db "** INT14h **", 0
msg_int15h: db "** INT15h **", 0
msg_int16h: db "** INT16h **", 0
msg_int17h: db "** INT17h **", 0

; 変数
dump_seg:   dw  0x0000  ; Dump: セグメント保存用
dump_off:   dw  0x0000  ; Dump: オフセット保存用
load_seg:   dw  0x0000  ; Load: ターゲットセグメント
tick_counter_lo: dw 0x0000  ; Tick: 下位16bit
tick_counter_hi: dw 0x0000  ; Tick: 上位16bit

; 割り込みフラグ
intp1_flag: dw 0
intp2_flag: dw 0
intp3_flag: dw 0
intp4_flag: dw 0
intp5_flag: dw 0
intp6_flag: dw 0
intp7_flag: dw 0

int10h_flag: dw 0
int11h_flag: dw 0
int12h_flag: dw 0
int13h_flag: dw 0
int14h_flag: dw 0
int15h_flag: dw 0
int16h_flag: dw 0
int17h_flag: dw 0