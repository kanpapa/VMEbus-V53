import sys

def split_file(filename):
    with open(filename, 'rb') as f:
        data = f.read()

    # 128KBの入力ファイルを想定
    if len(data) != 131072:
        print(f"Warning: File size is {len(data)} bytes (Expected 128KB)")

    # 偶数バイト (0, 2, 4...) -> Low ROM
    even_data = data[0::2]
    # 奇数バイト (1, 3, 5...) -> High ROM
    odd_data = data[1::2]

    # 出力1: Low側 (64KB)
    # 27C010(128KB)に入れるため、データを2回繰り返して埋める(ミラーリング)
    # これによりA16ピンの状態に関わらずデータが読めるようにする
    with open('rom_low_chip1.bin', 'wb') as f:
        f.write(even_data + even_data)
        
    # 出力2: High側 (64KB)
    # 同様にミラーリング
    with open('rom_high_chip2.bin', 'wb') as f:
        f.write(odd_data + odd_data)

    print("Done! Created 'rom_low_chip1.bin' and 'rom_high_chip2.bin'")

if __name__ == '__main__':
    if len(sys.argv) < 2:
        print("Usage: python3 split_rom.py boot.bin")
    else:
        split_file(sys.argv[1])