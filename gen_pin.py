"""
Generate shiny 3D pin badge: front (meme in golden rounded frame)
and back (gold with "PIN STOP" and clasp detail).
"""
from PIL import Image, ImageDraw, ImageFilter, ImageFont
import math, os

SRC = "memes/are_ya_winning_son.png"
OUT_DIR = "memes"
R = 32          # corner radius
PAD = 18        # padding inside frame
FRAME_W = 14    # frame thickness
SHADOW_W = 10   # drop shadow extent

# ── helpers ──
def rounded_rect_mask(size, r):
    """Return an 'L' mask image with anti-aliased rounded rectangle."""
    w, h = size
    mask = Image.new("L", (w, h), 0)
    d = ImageDraw.Draw(mask)
    # big rounded rect – white
    d.rounded_rectangle([0, 0, w - 1, h - 1], r, fill=255)
    return mask

def inner_rounded_mask(size, outer_r, thickness):
    """Mask for the inner cutout (transparent hole) – returns white where the frame IS."""
    w, h = size
    mask = Image.new("L", (w, h), 0)
    d = ImageDraw.Draw(mask)
    # outer
    d.rounded_rectangle([0, 0, w - 1, h - 1], outer_r, fill=255)
    # inner cutout (black)
    inset = thickness
    d.rounded_rectangle(
        [inset, inset, w - 1 - inset, h - 1 - inset],
        max(outer_r - inset, 1),
        fill=0,
    )
    return mask

def metallic_gradient(w, h, base=(0xD4, 0xAF, 0x37), highlight=(0xFF, 0xE5, 0x5C), shadow=(0x8B, 0x75, 0x1A)):
    """Vertical metallic gradient for the frame."""
    grad = Image.new("RGBA", (w, h))
    px = grad.load()
    for y in range(h):
        t = y / h
        # two highlight bands
        if t < 0.25:
            f = t / 0.25
            r = int(base[0] + (highlight[0] - base[0]) * f)
            g = int(base[1] + (highlight[1] - base[1]) * f)
            b = int(base[2] + (highlight[2] - base[2]) * f)
        elif t < 0.35:
            f = (t - 0.25) / 0.10
            r = int(highlight[0] + (base[0] - highlight[0]) * f)
            g = int(highlight[1] + (base[1] - highlight[1]) * f)
            b = int(highlight[2] + (base[2] - highlight[2]) * f)
        elif t < 0.65:
            r, g, b = base
        elif t < 0.80:
            f = (t - 0.65) / 0.15
            r = int(base[0] + (shadow[0] - base[0]) * f)
            g = int(base[1] + (shadow[1] - base[1]) * f)
            b = int(base[2] + (shadow[2] - base[2]) * f)
        else:
            f = (t - 0.80) / 0.20
            r = int(shadow[0] + (highlight[0] - shadow[0]) * f * 0.5)
            g = int(shadow[1] + (highlight[1] - shadow[1]) * f * 0.5)
            b = int(shadow[2] + (highlight[2] - shadow[2]) * f * 0.5)
        for x in range(w):
            px[x, y] = (r, g, b, 255)
    return grad

def bevel_highlight(w, h, r, thickness):
    """Create a subtle inner bevel highlight overlay."""
    overlay = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    d = ImageDraw.Draw(overlay)
    # inner edge highlight (thin white line just inside the frame)
    inset = thickness
    inner_r = max(r - inset, 1)
    d.rounded_rectangle(
        [inset, inset, w - 1 - inset, h - 1 - inset],
        inner_r,
        outline=(255, 255, 255, 60),
        width=2,
    )
    # outer edge highlight
    d.rounded_rectangle(
        [0, 0, w - 1, h - 1],
        r,
        outline=(255, 255, 255, 80),
        width=2,
    )
    return overlay

def specular_shine(w, h, r):
    """Diagonal shine across the top-left for a glossy enamel look."""
    shine = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    d = ImageDraw.Draw(shine)
    # a soft white gradient arc in the top-left
    for i in range(60):
        alpha = int(40 * (1 - i / 60))
        d.rounded_rectangle(
            [i, i, w - 1 - i, h - 1 - i],
            max(r - i, 0),
            outline=(255, 255, 255, alpha),
            width=1,
        )
    return shine

def add_drop_shadow(base_img, shadow_size):
    """Composite a soft drop shadow beneath the pin."""
    w, h = base_img.size
    shadow = Image.new("RGBA", (w + shadow_size * 2, h + shadow_size * 2), (0, 0, 0, 0))
    # draw black rounded rect, blurred
    sd = ImageDraw.Draw(shadow)
    sd.rounded_rectangle(
        [shadow_size, shadow_size, w + shadow_size - 1, h + shadow_size - 1],
        R + shadow_size // 2,
        fill=(0, 0, 0, 180),
    )
    shadow = shadow.filter(ImageFilter.GaussianBlur(shadow_size))
    # paste base on top
    result = Image.new("RGBA", shadow.size, (0, 0, 0, 0))
    result.paste(shadow, (0, 0))
    result.paste(base_img, (shadow_size, shadow_size), base_img)
    return result

# ──────────────────────────────────────
# FRONT PIN
# ──────────────────────────────────────
def make_front():
    meme = Image.open(SRC).convert("RGBA")
    mw, mh = meme.size

    # canvas size = meme + padding + frame + shadow
    inner_w = mw + PAD * 2
    inner_h = mh + PAD * 2
    total_w = inner_w + FRAME_W * 2
    total_h = inner_h + FRAME_W * 2

    # 1. metallic frame
    frame_grad = metallic_gradient(total_w, total_h)
    frame_mask = inner_rounded_mask((total_w, total_h), R, FRAME_W)
    frame = Image.new("RGBA", (total_w, total_h), (0, 0, 0, 0))
    frame.paste(frame_grad, (0, 0), frame_mask)

    # 2. inner dark backing
    inner = Image.new("RGBA", (total_w, total_h), (0, 0, 0, 0))
    d = ImageDraw.Draw(inner)
    d.rounded_rectangle(
        [FRAME_W, FRAME_W, total_w - 1 - FRAME_W, total_h - 1 - FRAME_W],
        max(R - FRAME_W, 1),
        fill=(20, 18, 22, 255),
    )

    # 3. meme centered inside
    meme_x = FRAME_W + PAD
    meme_y = FRAME_W + PAD

    # 4. composite
    result = Image.new("RGBA", (total_w, total_h), (0, 0, 0, 0))
    result.paste(inner, (0, 0), inner)
    result.paste(meme, (meme_x, meme_y), meme)
    result.paste(frame, (0, 0), frame)

    # 5. bevel highlights
    bevel = bevel_highlight(total_w, total_h, R, FRAME_W)
    result = Image.alpha_composite(result, bevel)

    # 6. specular shine
    shine = specular_shine(total_w, total_h, R)
    result = Image.alpha_composite(result, shine)

    # 7. drop shadow
    result = add_drop_shadow(result, SHADOW_W)

    out_path = os.path.join(OUT_DIR, "pin_front.png")
    result.save(out_path)
    print(f"Front pin → {out_path}  ({result.size[0]}x{result.size[1]})")
    return result.size

# ──────────────────────────────────────
# BACK PIN
# ──────────────────────────────────────
def make_back(front_size):
    tw, th = front_size
    # same inner canvas (without shadow)
    inner_w = tw - SHADOW_W * 2
    inner_h = th - SHADOW_W * 2

    # 1. gold metallic background
    bg = metallic_gradient(inner_w, inner_h)

    # 2. rounded-rect mask for the whole pin
    mask = rounded_rect_mask((inner_w, inner_h), R)
    bg.putalpha(mask)

    # 3. inner beveled detail ring
    d = ImageDraw.Draw(bg)
    # outer ring
    d.rounded_rectangle(
        [3, 3, inner_w - 4, inner_h - 4],
        R - 3,
        outline=(255, 255, 255, 50),
        width=2,
    )
    # inner ring
    inset2 = FRAME_W + 4
    d.rounded_rectangle(
        [inset2, inset2, inner_w - 1 - inset2, inner_h - 1 - inset2],
        max(R - inset2, 1),
        outline=(0, 0, 0, 40),
        width=2,
    )

    # 4. "PIN STOP" text
    try:
        font = ImageFont.truetype("fonts/RobotoMono-VariableFont_wght.ttf", 36)
    except Exception:
        try:
            font = ImageFont.truetype("fonts/default.ttf", 36)
        except Exception:
            font = ImageFont.load_default()

    text = "PIN STOP"
    # measure text
    bbox = d.textbbox((0, 0), text, font=font)
    tw_text = bbox[2] - bbox[0]
    th_text = bbox[3] - bbox[1]
    tx = (inner_w - tw_text) // 2
    ty = (inner_h - th_text) // 2 - 10

    # dark text shadow
    d.text((tx + 2, ty + 2), text, font=font, fill=(0, 0, 0, 180))
    # gold text
    d.text((tx, ty), text, font=font, fill=(255, 229, 92, 255))

    # 5. pin clasp detail at bottom center
    clasp_cx = inner_w // 2
    clasp_cy = inner_h - 50
    # clasp needle (vertical line)
    d.line([(clasp_cx, clasp_cy - 30), (clasp_cx, clasp_cy + 20)], fill=(80, 70, 50, 200), width=6)
    # clasp head (circle)
    d.ellipse(
        [clasp_cx - 12, clasp_cy + 18, clasp_cx + 12, clasp_cy + 42],
        fill=(100, 88, 60, 220),
        outline=(60, 50, 30, 200),
        width=2,
    )
    # safety pin-style clasp
    d.ellipse(
        [clasp_cx - 6, clasp_cy - 26, clasp_cx + 6, clasp_cy - 10],
        fill=(140, 120, 80, 200),
        outline=(80, 70, 50, 200),
        width=1,
    )

    # 6. specular shine
    shine = specular_shine(inner_w, inner_h, R)
    bg = Image.alpha_composite(bg, shine)

    # 7. bevel
    bevel = bevel_highlight(inner_w, inner_h, R, 0)
    bg = Image.alpha_composite(bg, bevel)

    # 8. drop shadow
    result = add_drop_shadow(bg, SHADOW_W)

    out_path = os.path.join(OUT_DIR, "pin_back.png")
    result.save(out_path)
    print(f"Back pin  → {out_path}  ({result.size[0]}x{result.size[1]})")

# ── GO ──
fs = make_front()
make_back(fs)
print("Done – shiny pin badge ready.")
