#!/usr/bin/env python3
import sys, os, json, subprocess, colorsys, re, hashlib

CACHE_FILE = "/tmp/island_cover_colors.json"

def get_cache():
    if os.path.exists(CACHE_FILE):
        try:
            with open(CACHE_FILE, "r") as f:
                return json.load(f)
        except Exception:
            return {}
    return {}

def save_cache(cache):
    try:
        with open(CACHE_FILE, "w") as f:
            json.dump(cache, f)
    except Exception:
        pass

def extract_color(source):
    if not source:
        return "#7aa2f7"

    cache = get_cache()
    h = hashlib.md5(source.encode("utf-8")).hexdigest()
    if h in cache:
        return cache[h]

    try:
        if source.startswith("http://") or source.startswith("https://"):
            cmd = f'curl -sL --max-time 3 "{source}" | magick - -resize 28x28 -colors 16 -format "%c\n" histogram:info: 2>/dev/null'
        else:
            path = source.replace("file://", "")
            if not os.path.exists(path):
                return "#7aa2f7"
            cmd = f'magick "{path}" -resize 28x28 -colors 16 -format "%c\n" histogram:info: 2>/dev/null'

        out = subprocess.check_output(cmd, shell=True, timeout=3.5).decode("utf-8", errors="ignore")
        best_color = None
        best_score = -1.0

        for line in out.strip().split("\n"):
            m = re.search(r"#([0-9A-Fa-f]{6})", line)
            if not m:
                continue
            hex_val = m.group(1).upper()
            r = int(hex_val[0:2], 16) / 255.0
            g = int(hex_val[2:4], 16) / 255.0
            b = int(hex_val[4:6], 16) / 255.0
            hue, sat, val = colorsys.rgb_to_hsv(r, g, b)

            # Skip near-black and near-white
            if val < 0.15 or val > 0.95 or sat < 0.18:
                continue

            # Score favors rich saturation with good brightness
            score = (sat ** 1.2) * (val ** 0.8)
            if score > best_score:
                best_score = score
                best_color = f"#{hex_val}"

        if not best_color:
            # Fallback to dominant color
            lines = out.strip().split("\n")
            if lines:
                m = re.search(r"#([0-9A-Fa-f]{6})", lines[0])
                if m:
                    best_color = f"#{m.group(1).upper()}"

        result = best_color if best_color else "#7aa2f7"
        cache[h] = result
        save_cache(cache)
        return result
    except Exception:
        return "#7aa2f7"

if __name__ == "__main__":
    src = sys.argv[1] if len(sys.argv) > 1 else ""
    color = extract_color(src)
    print(color)
