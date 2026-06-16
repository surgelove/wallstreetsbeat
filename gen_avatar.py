import struct, zlib, os

# 28x28 pixel art of a blonde woman
W, H = 28, 28

# Color palette (R,G,B,A)
BG  = (0, 0, 0, 0)       # transparent
H   = (0xE8, 0xC8, 0x40, 255) # blonde hair
HD  = (0xC4, 0xA0, 0x20, 255) # darker blonde (eyebrows, hair shadow)
S   = (0xF5, 0xD6, 0xB8, 255) # skin
SD  = (0xE0, 0xB8, 0x98, 255) # darker skin (nose shadow, neck)
E   = (0x3D, 0x2B, 0x1F, 255) # eye dark
EW  = (0xF0, 0xF0, 0xF0, 255) # eye white
M   = (0xC4, 0x67, 0x6B, 255) # mouth/lips
C   = (0xD0, 0xA0, 0x80, 255) # collar/neck shadow
T   = (0xE0, 0xE0, 0xE0, 255) # top/shirt
TD  = (0xC0, 0xC0, 0xC0, 255) # shirt shadow

rows = [
    "....HHHHHHHHHHHHHHHHHH....",
    "...HHHHHHHHHHHHHHHHHHHH...",
    "..HHHDHHHHHHHHHHHHHDHHH..",
    "..HHHDDDHHHHHHHHHDDDHHH..",
    "..HHHHHHHHHHHHHHHHHHHHH..",
    "...DDDDHHHHHHHHHDDDDDH...",
    ".....HHSSSSSSSSSSSHH.....",
    "....HSSSSSSSSSSSSSSSH....",
    "...HSSSSSSSSSSSSSSSSSH...",
    "...HSSSWWESSSSEWWSSSH...",
    "...HSSSWWESSSSEWWSSSH...",
    "...HSSSSttSSSSttSSSSH...",
    "...HSSSSSSSSSSSSSSSSH...",
    "...HSSSSSSSdSdSSSSSSH...",
    "...HSSSSSSSSSSSSSSSSH...",
    "...HSSSSSSMMSSSSSSSSH...",
    "...HHSSSSSMMSSSSSSSHH...",
    "....HSSSSMMMMMSSSSH....",
    "....HSSSSSMSMSSSSSH....",
    "....HHSSSSSSSSSSSHH....",
    ".....HSSSSSSSSSSSH.....",
    ".....HSdSSSSSSSdSH.....",
    ".....HCCdSSSSSdCCH.....",
    ".....HTCCdSSSdCCTH.....",
    ".....HTTTCCCCCCTTH.....",
    ".....HTTTTTTTTTTTH.....",
    ".....HTTTTTTTTTTTH.....",
    "....HHTTTTTTTTTTTHH....",
]

cmap = {
    '.': BG, 'H': H, 'D': HD,
    'S': S, 'd': SD,
    'E': E, 'W': EW,
    'M': M, 'C': C,
    'T': T, 't': TD,
}

# Build raw RGBA pixel data (top-to-bottom rows)
raw = b""
for y, row in enumerate(rows):
    raw += b"\x00"  # filter byte (none)
    for x, ch in enumerate(row):
        r, g, b, a = cmap[ch]
        raw += struct.pack("BBBB", r, g, b, a)

def make_chunk(ctype, data):
    c = ctype + data
    crc = struct.pack(">I", zlib.crc32(c) & 0xFFFFFFFF)
    return struct.pack(">I", len(data)) + c + crc

# PNG signature
png = b"\x89PNG\r\n\x1a\n"

# IHDR
ihdr = struct.pack(">IIBBBBB", W, H, 8, 6, 0, 0, 0)  # 8-bit RGBA
png += make_chunk(b"IHDR", ihdr)

# IDAT
compressed = zlib.compress(raw)
png += make_chunk(b"IDAT", compressed)

# IEND
png += make_chunk(b"IEND", b"")

path = "/Users/code/Developer/love_stonks/avatar.png"
with open(path, "wb") as f:
    f.write(png)
print(f"✅ avatar.png created ({os.path.getsize(path)} bytes)")
