import numpy as np, random, subprocess, sys
SR = 32000

def hz(m): return 440.0 * 2 ** ((m - 69) / 12)

def pulse(f, n, duty):
    t = np.arange(n) / SR
    ph = (t * f) % 1.0
    return np.where(ph < duty, 1.0, -1.0)

def tri(f, n):
    t = np.arange(n) / SR
    ph = (t * f) % 1.0
    return 4 * np.abs(ph - 0.5) - 1

def env(n, a=0.004, d=0.08, s=0.6, r=0.05):
    e = np.ones(n)
    na, nd, nr = int(a * SR), int(d * SR), int(r * SR)
    na = max(1, min(na, n)); 
    e[:na] = np.linspace(0, 1, na)
    nd = min(nd, n - na)
    if nd > 0: e[na:na + nd] = np.linspace(1, s, nd)
    if n - na - nd > 0: e[na + nd:] = s
    nr = min(nr, n)
    e[n - nr:] *= np.linspace(1, 0, nr)
    return e

class Track:
    def __init__(self, bpm, bars):
        self.bpm, self.bars = bpm, bars
        self.step = 60.0 / bpm / 4  # 16th note seconds
        self.n_steps = bars * 16
        self.len = int(self.n_steps * self.step * SR)
        self.tail = int(1.0 * SR)
        self.buf = np.zeros(self.len + self.tail)
    def add(self, step, sig, vol):
        i = int(step * self.step * SR)
        sig = sig * vol
        end = min(i + len(sig), len(self.buf))
        self.buf[i:end] += sig[:end - i]
    def note(self, step, midi, dur_steps, wave="p50", vol=0.2, **e):
        n = int(dur_steps * self.step * SR)
        f = hz(midi)
        if wave == "p50": s = pulse(f, n, 0.5)
        elif wave == "p25": s = pulse(f, n, 0.25)
        elif wave == "p12": s = pulse(f, n, 0.125)
        else: s = tri(f, n)
        self.add(step, s * env(n, **e), vol)
    def kick(self, step, vol=0.5):
        n = int(0.18 * SR); t = np.arange(n) / SR
        f = 120 * np.exp(-t * 28) + 42
        s = np.sin(2 * np.pi * np.cumsum(f) / SR) * np.exp(-t * 14)
        self.add(step, s, vol)
    def snare(self, step, vol=0.3):
        n = int(0.16 * SR); t = np.arange(n) / SR
        s = (np.random.RandomState(step).uniform(-1, 1, n) * 0.8 + np.sin(2 * np.pi * 190 * t) * 0.4) * np.exp(-t * 24)
        self.add(step, s, vol)
    def hat(self, step, vol=0.1, open_=False):
        n = int((0.12 if open_ else 0.04) * SR); t = np.arange(n) / SR
        s = np.random.RandomState(step + 7).uniform(-1, 1, n) * np.exp(-t * (18 if open_ else 70))
        self.add(step, s, vol)
    def render(self):
        b = self.buf.copy()
        out = b[:self.len].copy()
        out[:self.tail] += b[self.len:]  # wrap the tail so the loop is seamless
        pk = np.max(np.abs(out)) + 1e-9
        out = np.tanh(out / pk * 1.6) / np.tanh(1.6) * 0.8
        return out

MAJ = [0, 2, 4, 5, 7, 9, 11]
MIN = [0, 2, 3, 5, 7, 8, 10]

def build(name, bpm, root, scale, prog, bars, style, seed):
    rnd = random.Random(seed)
    T = Track(bpm, bars)
    sc = MAJ if scale == "maj" else MIN
    def chord(deg, quality):
        r = root + sc[deg % 7] + (12 if deg >= 7 else 0)
        third = 3 if quality == "m" else 4
        return [r, r + third, r + 7]
    def scale_notes(lo, hi):
        return [root + o * 12 + d for o in range(-2, 5) for d in sc if lo <= root + o * 12 + d <= hi]
    lead_pool = scale_notes(66, 88) if style != "results" else scale_notes(64, 86)
    # two 4-bar phrases (A, B), each built from a 2-bar motif and a variation
    def make_motif(chords2):
        steps = []
        rhy = rnd.choice([[0, 3, 6, 8, 10, 12, 14], [0, 2, 4, 6, 8, 11, 14], [0, 4, 6, 8, 12, 14], [0, 3, 6, 9, 12, 14]])
        notes = []
        cur = rnd.choice([n for n in lead_pool if 70 <= n <= 78])
        for bar in range(2):
            ch = chords2[bar]
            for s in rhy:
                strong = s in (0, 8)
                cands = [n for n in lead_pool if abs(n - cur) <= 4]
                if strong:
                    ct = [n for n in cands if (n - ch[0]) % 12 in [(c - ch[0]) % 12 for c in ch]]
                    cands = ct or cands
                cur = rnd.choice(cands)
                notes.append((bar * 16 + s, cur))
        return notes
    plan = []
    for b in range(bars):
        d, q = prog[b % len(prog)]
        plan.append(chord(d, q))
    motifs = {}
    for p in range(0, bars, 4):
        key = (p // 4) % 2
        for half in range(2):
            b0 = p + half * 2
            mk = (key, half)
            if mk not in motifs:
                motifs[mk] = make_motif([plan[b0], plan[(b0 + 1) % bars]])
            for (s, n) in motifs[mk]:
                dur = 3 if style in ("menu", "results") else 2
                T.note(b0 * 16 + s, n, dur, "p50", 0.13, a=0.003, d=0.1, s=0.55, r=0.04)
    for b in range(bars):
        ch = plan[b]; base = b * 16
        root_n = ch[0] - 24 if ch[0] - 24 >= 28 else ch[0] - 12
        # bass
        if style == "battle":
            for s in range(0, 16, 2):
                T.note(base + s, root_n + (12 if s in (6, 14) else 0), 1.6, "tri", 0.32, a=0.002, d=0.05, s=0.8, r=0.02)
        elif style == "select":
            pat = [0, 3, 6, 8, 11, 14]
            for i, s in enumerate(pat):
                T.note(base + s, root_n + (7 if i % 3 == 2 else 0), 2.5, "tri", 0.33)
        else:
            for s, off in ((0, 0), (6, 7), (8, 0), (14, 7)):
                T.note(base + s, root_n + off, 5, "tri", 0.33)
        # arpeggio
        arp = [ch[0] + 12, ch[1] + 12, ch[2] + 12, ch[1] + 24 - 12]
        for s in range(16):
            if style == "menu" and s % 2: continue
            T.note(base + s, arp[s % 4] + (12 if style == "battle" and s % 8 >= 4 else 0), 1.2, "p25", 0.055, a=0.002, d=0.04, s=0.4, r=0.02)
        # drums
        if style == "battle":
            for s in (0, 4, 8, 10, 12): T.kick(base + s, 0.55)
            for s in (4, 12): T.snare(base + s, 0.32)
            for s in range(0, 16, 2): T.hat(base + s, 0.09, open_=(s == 14))
        elif style == "select":
            for s in (0, 6, 8, 14): T.kick(base + s, 0.45)
            for s in (4, 12): T.snare(base + s, 0.26)
            for s in range(0, 16, 2): T.hat(base + s, 0.07)
        elif style == "menu":
            for s in (0, 8): T.kick(base + s, 0.4)
            T.snare(base + 12, 0.18)
            for s in range(0, 16, 4): T.hat(base + s, 0.06)
        else:  # results
            for s in (0, 8): T.kick(base + s, 0.42)
            for s in (4, 12): T.snare(base + s, 0.24)
            for s in range(0, 16, 2): T.hat(base + s, 0.06)
    out = T.render()
    pcm = (out * 32767).astype(np.int16)
    open(name + ".raw", "wb").write(pcm.tobytes())
    subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-f", "s16le", "-ar", str(SR), "-ac", "1", "-i", name + ".raw",
                    "-c:a", "libvorbis", "-q:a", "3", name + ".ogg"], check=True)
    print(name, round(len(out) / SR, 1), "s")

# progression entries: (scale degree, "M"/"m")
build("menu",    112, 60, "maj", [(0,"M"),(5,"m"),(3,"M"),(4,"M")], 16, "menu", 11)
build("select",  128, 62, "maj", [(0,"M"),(5,"m"),(4,"M"),(3,"M")], 16, "select", 23)
build("battle",  156, 57, "min", [(0,"m"),(5,"M"),(2,"M"),(6,"M"),(0,"m"),(5,"M"),(4,"M"),(4,"M")], 16, "battle", 37)
build("results", 100, 60, "maj", [(0,"M"),(4,"M"),(5,"m"),(3,"M")], 8, "results", 5)
