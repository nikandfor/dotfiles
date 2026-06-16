import json, sys, time, os

yellow, red, dim, plain = "33", "31", "2", ""

sep = "   "

def color(s, c):
    if c == plain:
        return s
    return f"\033[{c}m{s}\033[0m"

def by_level(pct):
    if pct < 60:
        return dim
    if pct < 85:
        return yellow
    return red

def tok(n):
    if n >= 1e6:
        return f"{n / 1e6:.1f}M"
    if n >= 1000:
        return f"{round(n / 1000)}k"
    return str(n)

def ctx(d):
    pct = d["context_window"]["used_percentage"]
    return color(f"ctx {pct}%", by_level(pct))

def usage(d):
    u = d["context_window"]["current_usage"]
    io = f"tk {tok(u['input_tokens'])}/{tok(u['output_tokens'])}"
    cache = f"cache {tok(u['cache_read_input_tokens'])}/{tok(u['cache_creation_input_tokens'])}"
    return color(io, dim) + sep + color(cache, dim)

def dur(mins):
    if mins >= 60:
        return f"{mins // 60}h{mins % 60}m"
    return f"{mins}m"

def cost(d, prev):
    total = d["cost"]["total_cost_usd"]
    api_mins = round(d["cost"]["total_api_duration_ms"] / 60000)
    wall_mins = round(d["cost"]["total_duration_ms"] / 60000)
    last = total - prev.get("cost", {}).get("total_cost_usd", 0)
    return sep.join([color(f"${total:.2f}", dim), f"${last:.3f}", color(f"api {dur(api_mins)}", dim), color(f"wall {dur(wall_mins)}", dim)])

def limit(d, key, label, tfmt):
    w = d["rate_limits"][key]
    reset = time.strftime(tfmt, time.localtime(w["resets_at"]))
    return color(f"{label} {w['used_percentage']}%", by_level(w["used_percentage"])) + color(f" ↻{reset}", dim)

def cwd(d):
    path = d.get("workspace", {}).get("current_dir") or d.get("cwd") or os.getcwd()
    home = os.path.expanduser("~")
    if path.startswith(home):
        path = "~" + path[len(home):]
    return color(path, dim)

d = json.load(sys.stdin)

prev_path = f"/tmp/statusline-input-{d.get('session_id', 'none')}.json"

try:
    prev = json.load(open(prev_path))
except (OSError, ValueError):
    prev = {}

with open(prev_path, "w") as f:
    json.dump(d, f)

parts = []

for part in [ctx,
             lambda d: cost(d, prev),
             lambda d: limit(d, "five_hour", "5h", "%H:%M"),
             lambda d: limit(d, "seven_day", "7d", "%a"),
             usage,
             cwd]:
    try:
        parts.append(part(d))
    except KeyError:
        pass

print(sep.join(parts))
