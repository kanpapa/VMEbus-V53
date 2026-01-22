; =================================================================
; V53 Monitor System v0.4  2026-01-21
; Target: V53 VME Board & DOSBox-X Simulation
; =================================================================

; --- ビルド方法 ---
; DOSBox: nasm -f bin -dSIM v53_ram_mon.asm -o v53_ram_mon.com -l v53_ram_mon.lst
; Real:   nasm -f bin v53_ram_mon.asm -o v53_ram_mon.bin -l v53_ram_mon.lst
; -----------------

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
%define WCY4    0x0FFF6 ; プログラマブル・ウェイト・サイクル数設定レジスタ4
%define WCY3    0x0FFF5 ; プログラマブル・ウェイト・サイクル数設定レジスタ3
%define WCY2    0x0FFF4 ; プログラマブル・ウェイト・サイクル数設定レジスタ2
%define WMB1    0x0FFF3 ; プログラマブル・ウェイト・メモリ領域設定レジスタ1
%define RFC     0x0FFF2 ; リフレッシュ・コントロール・レジスタ
%define SBCR    0x0FFF1 ; 
%define TCKS    0x0FFF0 ; 
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

    ; SCUレジスタ (SCUは1260Hに仮配置）
    %define SCU_DATA    0x01260 ; 送受データ・レジスタ(R:SRB/W:STB)
    %define SCU_SST     0x01261 ; ステータス・レジスタ(R:SST)
    %define SCU_SCM     0x01261 ; コマンドレジスタ(W:SCM)
    %define SCU_SMD     0x01262 ; シリアルモード設定(W:SMD)
    %define SCU_SIMK    0x01263 ; シリアル割り込みマスクレジスタ(R/W:SIMK)
    %define TX_READY    00000001b   ; TBRDY                                 
    %define RX_READY    00000010b   ; RBRDY
%endif

section .text

start:
%ifdef SIM
    xor ax, ax
    mov es, ax
%else
    cli

    ; ---------------------------------------------
    ; 1. セグメントレジスタ初期化
    ; CS=DS=ES を想定
    ; ---------------------------------------------
    push cs
    pop ds
    push cs
    pop es
    ; スタックは簡易モニタのものをそのまま使う    
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

; =================================================================
; Data
; =================================================================
msg_boot: db 0x0D,0x0A,"**  V53 RAM MONITOR v0.4 2026-01-21  **",0x0D,0x0A,0
msg_load: db "Load HEX...",0
msg_ok:   db "OK",0
msg_go:   db "Go!",0

msg_prompt: db "> ", 0
msg_error:  db "Error", 0x0D, 0x0A, 0
msg_unknown:db "Unknown cmd", 0x0D, 0x0A, 0
msg_in_res: db "Val: ", 0
msg_done:   db "Done", 0x0D, 0x0A, 0
msg_bar:    db " | ", 0
msg_help:   db "Cmds: D <Seg> <Off>, L <Seg>, G <Seg> <Off>, W <Seg> <Off> <Val>, I <Port>, O <Port> <Val>, S <Start_port> <End_port>, ?", 0x0D, 0x0A, 0
msg_scan_start: db "Scanning I/O (Press any key to abort)...", 0x0D, 0x0A, 0
msg_space:      db "  ", 0
msg_abort:      db "Aborted.", 0x0D, 0x0A, 0

; 変数
dump_seg:   dw  0x0000  ; Dump: セグメント保存用
dump_off:   dw  0x0000  ; Dump: オフセット保存用
load_seg:   dw  0x0000  ; Load: ターゲットセグメント