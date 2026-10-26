//!PARAM scan
//!DESC scanline strength 0..1
//!TYPE float
//!MINIMUM 0
//!MAXIMUM 1
0.35

//!PARAM lines
//!DESC scanline count across the screen
//!TYPE float
//!MINIMUM 60
//!MAXIMUM 720
240

//!PARAM curve
//!DESC screen curvature 0..1
//!TYPE float
//!MINIMUM 0
//!MAXIMUM 1
0.30

//!PARAM mask
//!DESC RGB phosphor mask strength 0..1
//!TYPE float
//!MINIMUM 0
//!MAXIMUM 1
0.12

//!PARAM vig
//!DESC vignette 0..1
//!TYPE float
//!MINIMUM 0
//!MAXIMUM 1
0.30

//!PARAM glow
//!DESC phosphor glow / brightness boost 0..1
//!TYPE float
//!MINIMUM 0
//!MAXIMUM 1
0.25

//!PARAM contrast
//!DESC contrast, 1 = unchanged
//!TYPE float
//!MINIMUM 0.5
//!MAXIMUM 1.5
1.0

//!PARAM saturation
//!DESC colour saturation, 1 = unchanged, 0 = black and white
//!TYPE float
//!MINIMUM 0.0
//!MAXIMUM 2.0
1.0

//!PARAM ntsc
//!DESC analog signal: 0 clean, 1 S-Video, 2 composite, 3 RF
//!TYPE float
//!MINIMUM 0
//!MAXIMUM 3
0.0

//!PARAM PTS
//!DESC current video timestamp in seconds, supplied automatically by mpv
//!TYPE DYNAMIC float
0

//!PARAM noise
//!DESC analog noise: grain, interference band and line jitter 0..1
//!TYPE float
//!MINIMUM 0
//!MAXIMUM 1
0.12

//!PARAM bezel
//!DESC light from the picture glowing on and reflecting in the TV around the screen 0..1
//!TYPE float
//!MINIMUM 0
//!MAXIMUM 1
0.5

//!PARAM shine
//!DESC glass reflection highlight 0..1
//!TYPE float
//!MINIMUM 0
//!MAXIMUM 1
0.30

//!PARAM track
//!DESC VHS tracking error, 0 = perfectly tuned, -1..1
//!TYPE float
//!MINIMUM -1
//!MAXIMUM 1
0.0

//!PARAM warm
//!DESC power-on warm-up progress, 1 = fully on
//!TYPE float
//!MINIMUM 0
//!MAXIMUM 1
1.0

//!PARAM poweroff
//!DESC power-off collapse progress, 0 = on
//!TYPE float
//!MINIMUM 0
//!MAXIMUM 1
0.0

//!PARAM snow
//!DESC channel-change static 0..1
//!TYPE float
//!MINIMUM 0
//!MAXIMUM 1
0.0

//!PARAM degauss
//!DESC degauss wobble and colour swirl 0..1
//!TYPE float
//!MINIMUM 0
//!MAXIMUM 1
0.0

//!PARAM fxt
//!DESC clock for the animations above, in seconds (runs while paused too)
//!TYPE float
//!MINIMUM 0
//!MAXIMUM 100000
0.0

//!PARAM mute
//!DESC show the green MUTE on-screen display (0 or 1)
//!TYPE float
//!MINIMUM 0
//!MAXIMUM 1
0.0

//!PARAM episode
//!DESC transient green episode number after playlist advancement; 0 hides it
//!TYPE float
//!MINIMUM 0
//!MAXIMUM 99999
0.0

//!PARAM rl
//!DESC screen rectangle left (0..1 of frame)
//!TYPE float
//!MINIMUM 0
//!MAXIMUM 1
0.0

//!PARAM rt
//!DESC screen rectangle top
//!TYPE float
//!MINIMUM 0
//!MAXIMUM 1
0.0

//!PARAM rr
//!DESC screen rectangle right
//!TYPE float
//!MINIMUM 0
//!MAXIMUM 1
1.0

//!PARAM rb
//!DESC screen rectangle bottom
//!TYPE float
//!MINIMUM 0
//!MAXIMUM 1
1.0

//!HOOK OUTPUT
//!BIND HOOKED
//!DESC CRT (scanlines, curvature, mask, vignette, on-screen display)

// ---- "MUTE" on-screen display: a tiny pixel font like an old TV/VCR menu ----
const int SPK[9] = int[9](2, 6, 14, 62, 62, 62, 14, 6, 2);      // speaker, 6 wide
const int XXX[9] = int[9](0, 0, 17, 10, 4, 10, 17, 0, 0);       // cross, 5 wide
const int GM[7] = int[7](17, 27, 21, 21, 17, 17, 17);           // M
const int GU[7] = int[7](17, 17, 17, 17, 17, 17, 14);           // U
const int GT[7] = int[7](31, 4, 4, 4, 4, 4, 4);                 // T
const int GE[7] = int[7](31, 16, 16, 30, 16, 16, 31);           // E
// Identical 5x7 phosphor font for the short-lived episode-number display.
const int EPISODE_DIGITS[70] = int[70](14, 17, 19, 21, 25, 17, 14, 4, 12, 4, 4, 4, 4, 14, 14, 17, 1, 2, 4, 8, 31, 30, 1, 1, 14, 1, 1, 30, 2, 6, 10, 18, 31, 2, 2, 31, 16, 30, 1, 1, 17, 14, 6, 8, 16, 30, 17, 17, 14, 31, 1, 2, 4, 8, 8, 8, 14, 17, 17, 14, 17, 17, 14, 14, 17, 17, 15, 1, 2, 12);

bool bitset(int row, int col, int width) { return ((row >> (width - 1 - col)) & 1) == 1; }

// ---- NTSC signal simulation ----
vec3 rgb2yiq(vec3 c) {
    return vec3(dot(c, vec3(0.299, 0.587, 0.114)), dot(c, vec3(0.596, -0.274, -0.322)), dot(c, vec3(0.211, -0.523, 0.312)));
}
vec3 yiq2rgb(vec3 q) {
    return vec3(q.x + 0.956 * q.y + 0.621 * q.z, q.x - 0.272 * q.y - 0.647 * q.z, q.x - 1.106 * q.y + 1.703 * q.z);
}

// cheap per-pixel, per-frame hash in 0..1 (so the noise moves every frame like analog static)
float hash21(vec2 p, float t) {
    vec3 q = fract(vec3(p.xyx) * vec3(0.1031, 0.1030, 0.0973) + t * vec3(0.0371, 0.0139, 0.0227));
    q += dot(q, q.yzx + 33.33);
    return fract((q.x + q.y) * q.z);
}

// smooth 1D value noise along x (one random value per whole step, eased in between); row and t pick the pattern
float vnoise(float x, float row, float t) {
    float i = floor(x), f = fract(x);
    return mix(hash21(vec2(i, row), t), hash21(vec2(i + 1.0, row), t), f * f * (3.0 - 2.0 * f));
}

float cell_on(ivec2 c) {
    if (c.y < 0 || c.y > 8 || c.x < 0) return 0.0;
    if (c.x < 6)  return bitset(SPK[c.y], c.x, 6) ? 1.0 : 0.0;
    if (c.x == 6) return 0.0;
    if (c.x < 12) return bitset(XXX[c.y], c.x - 7, 5) ? 1.0 : 0.0;
    int ty = c.y - 1;
    if (ty < 0 || ty > 6 || c.x < 15 || c.x >= 39) return 0.0;
    int k = (c.x - 15) / 6;
    int col = (c.x - 15) - k * 6;
    if (col > 4) return 0.0;
    int row = (k == 0) ? GM[ty] : (k == 1) ? GU[ty] : (k == 2) ? GT[ty] : GE[ty];
    return bitset(row, col, 5) ? 1.0 : 0.0;
}

// Use the MUTE display's existing phosphor cells, position and bloom.
// Only digits are shown for episodes: no speaker icon, "EP" label or suffix.
float episode_cell_on(ivec2 c) {
    int ty = c.y - 1;
    if (c.x < 0 || ty < 0 || ty > 6) return 0.0;
    int number = int(episode + 0.5);
    int length = number >= 10000 ? 5 : number >= 1000 ? 4
               : number >= 100 ? 3 : number >= 10 ? 2 : 1;
    int index = c.x / 6;
    int col = c.x % 6;
    if (index >= length || col >= 5) return 0.0;
    int divisor = 1;
    for (int i = 0; i < 5; i++)
        if (i < length - index - 1) divisor *= 10;
    int digit = (number / divisor) % 10;
    return bitset(EPISODE_DIGITS[digit * 7 + ty], col, 5) ? 1.0 : 0.0;
}
float active_osd_cell(ivec2 c) {
    return episode > 0.5 ? episode_cell_on(c) : cell_on(c);
}

// each lit cell is a slightly rounded phosphor block
float osd_core(vec2 g) {
    vec2 f = fract(g) - 0.5;
    float d = length(max(abs(f) - 0.40, 0.0));
    return active_osd_cell(ivec2(floor(g))) * (1.0 - smoothstep(0.0, 0.14, d));
}

// soft light bleeding into the neighbouring cells
float osd_halo(vec2 g) {
    ivec2 b = ivec2(floor(g));
    float h = 0.0;
    for (int i = -2; i <= 2; i++)
        for (int j = -2; j <= 2; j++)
            h += exp(-float(i * i + j * j) * 0.35) * active_osd_cell(b + ivec2(i, j));
    return clamp(h / 5.0, 0.0, 1.0);
}

// the screen's barrel distortion: rectangle coordinates (0..1) to picture coordinates (0..1 inside the picture)
vec2 barrel(vec2 uv) {
    vec2 cc = uv * 2.0 - 1.0;
    vec2 off = abs(cc.yx) * curve * 0.22;
    cc = cc * (1.0 + off * off * 2.0);
    cc /= (1.0 + curve * 0.05);
    return cc * 0.5 + 0.5;
}

// Light from the picture falling on the TV around it. The glass is treated as one rounded rectangle and the glow
// follows a smooth distance field around it, so it wraps evenly round the corners. p is the pixel in screen heights
// from the screen centre. The colour is the picture mirrored across the nearest edge point: close to the screen the
// bezel shows a soft reflection of the picture's edge, further out it spreads into a glow in the picture's colours.
vec3 screen_light(vec2 p, vec2 rc, vec2 rs, vec2 asp) {
    float rad = 0.015 + 0.04 * curve;                            // corner radius of the glass
    vec2 q = abs(p) - (0.5 * asp - rad);
    vec2 qo = max(q, 0.0);
    float d = max(length(qo) + min(max(q.x, q.y), 0.0) - rad, 0.0);   // distance outside the glass
    float k = bezel * (0.65 * exp(-d * 50.0) + 0.15 * exp(-d * 14.0));
    float lit = smoothstep(0.3, 1.0, warm) * (1.0 - smoothstep(0.2, 0.6, poweroff));   // follows the power effects
    if (k * lit < 0.004)
        return vec3(0.0);
    vec2 n = length(qo) > 1e-6 ? normalize(qo) : (q.x > q.y ? vec2(1.0, 0.0) : vec2(0.0, 1.0));
    n *= vec2(p.x < 0.0 ? -1.0 : 1.0, p.y < 0.0 ? -1.0 : 1.0);
    vec2 wm = clamp(barrel((p - n * (2.0 * d + rad * 0.5)) / asp + 0.5), 0.0, 1.0);
    float r = 0.010 + d * 0.6;                                   // soft even at the edge, blurrier further out
    vec3 acc = vec3(0.0);
    for (int i = 0; i < 12; i++) {
        float a = float(i) * 2.39996;
        vec2 o = vec2(cos(a), sin(a)) * r * sqrt((float(i) + 0.5) / 12.0) / asp;
        acc += HOOKED_tex(rc + clamp(wm + o, 0.0, 1.0) * rs).rgb;
    }
    vec3 c = acc / 12.0;
    c = mix(vec3(dot(c, vec3(0.299, 0.587, 0.114))), c, saturation);
    c = max((c - 0.5) * contrast + 0.5, 0.0);
    c = mix(c, vec3(0.45), snow);                                 // channel-change static lights it grey
    return c * k * lit;
}

vec4 hook() {
    // switched on but not warmed up yet: the whole window stays dark until the TV picture arrives
    if (warm <= 0.0)
        return vec4(0.0, 0.0, 0.0, 1.0);

    // The effect only touches the TV's screen rectangle; the frame passes through.
    vec2 p0 = HOOKED_pos;
    vec2 rc = vec2(rl, rt);
    vec2 rs = max(vec2(rr - rl, rb - rt), vec2(1e-4));
    vec2 asp = vec2(rs.x * HOOKED_size.x / (rs.y * HOOKED_size.y), 1.0);   // rectangle units to screen heights
    vec2 uv = (p0 - rc) / rs;
    if (p0.x < rl || p0.x > rr || p0.y < rt || p0.y > rb) {
        // the TV around the screen: its own picture plus light from the screen, mirrored across the nearest edge
        vec3 tv = HOOKED_tex(p0).rgb;
        if (bezel <= 0.0 || length((uv - clamp(uv, 0.0, 1.0)) * asp) > 0.25)
            return vec4(tv, 1.0);
        return vec4(tv + screen_light((uv - 0.5) * asp, rc, rs, asp), 1.0);
    }
    vec2 cc = uv * 2.0 - 1.0;

    // barrel distortion
    vec2 off = abs(cc.yx) * curve * 0.22;
    cc = cc * (1.0 + off * off * 2.0);
    cc /= (1.0 + curve * 0.05);
    vec2 w = cc * 0.5 + 0.5;

    // rounded-corner screen mask
    vec2 q = abs(cc) - vec2(1.0 - 0.06 * curve - 0.01);
    float corner = length(max(q, 0.0)) - 0.0;
    float edge = 1.0 - smoothstep(0.0, 0.012 + 0.03 * curve, corner);
    if (w.x < 0.0 || w.x > 1.0 || w.y < 0.0 || w.y > 1.0) {
        // the dark tube surround between the curved picture and the TV: lit faintly by the picture next to it
        if (bezel <= 0.0)
            return vec4(0.0, 0.0, 0.0, 1.0);
        return vec4(screen_light((uv - 0.5) * asp, rc, rs, asp), 1.0);
    }

    // power-on warm-up and power-off: the picture is squeezed toward the centre, into a white-hot line and then a dot
    float flash = 0.0, bright = 1.0, fade = 1.0;
    if (warm < 1.0 || poweroff > 0.0) {
        vec2 sq = vec2(1.0);
        if (warm < 1.0) {
            float a = smoothstep(0.08, 0.35, warm);                       // a moment as a thin line first
            sq = vec2(mix(0.80, 1.0, a), mix(0.004, 1.0, a * a));
            flash = 1.0 - a;
            bright = mix(0.12, 1.0, smoothstep(0.05, 1.0, warm));      // the tube takes a moment to reach full brightness
        }
        if (poweroff > 0.0) {
            // accelerating all the way: the picture is moving from the first frame and keeps speeding up (to about 8x)
            // until it snaps into a line, then the line shrinks into a dot the same way; the white-hot flash builds as
            // the picture gets thin
            float a = clamp(poweroff / 0.62, 0.0, 1.0), b = clamp((poweroff - 0.62) / 0.23, 0.0, 1.0);
            a = a * (0.3 + 0.7 * a * a);
            b = b * (0.3 + 0.7 * b * b);
            sq = min(sq, vec2(mix(1.0, 0.008, b), mix(1.0, 0.0012, a)));   // the final bar is a hair thin
            flash = max(flash, a);
            fade = 1.0 - smoothstep(0.85, 1.0, poweroff);
        }
        vec2 e = max(abs(w - 0.5) - sq * 0.5, 0.0) * vec2(rs.x * HOOKED_size.x / (rs.y * HOOKED_size.y), 1.0);
        if (e.x > 0.0 || e.y > 0.0) {                                 // outside the squeezed picture: only the beam's glow
            float g = exp(-dot(e, e) * (poweroff > 0.0 ? 240000.0 : 80000.0)) * flash * fade;      // a tight glow, a few pixels wide (tighter at power-off)
            return vec4(vec3(0.85, 0.92, 1.0) * g * edge, 1.0);
        }
        w = 0.5 + (w - 0.5) / sq;
    }

    // degauss: the picture wobbles while the coil's field dies away
    if (degauss > 0.0) {
        w += vec2(sin(w.y * 9.0 + fxt * 47.0), sin(w.x * 7.0 + fxt * 39.0)) * 0.010 * degauss;
        w = clamp(w, 0.0, 1.0);
    }

    // VHS tracking error: a band of torn lines rolls up (negative) or down (positive) the picture, the bottom lines
    // are dragged sideways by head-switching and the picture judders. Moves with the video, like the noise.
    // Everything is worked out per physical pixel row, so the streaks stay fine at any display resolution.
    float trk = abs(track), tband = 0.0, hsw = 0.0, tline = 0.0, tx = 0.0, tframe = mod(floor(PTS * 30.0), 4096.0);
    if (trk > 0.001) {
        tline = floor(w.y * HOOKED_size.y * rs.y);              // pixel row on the screen
        tx = w.x * HOOKED_size.x * rs.x;                        // pixel column, before the lines are pulled sideways
        float bpos = fract(0.2 + sign(track) * PTS * (0.03 + 0.08 * trk));
        float dy = abs(w.y - bpos);
        dy = min(dy, 1.0 - dy);
        tband = smoothstep(0.02 + 0.12 * trk, 0.0, dy);
        // lines in the band are pulled sideways by a smooth wave, with only a pixel or two of jitter between rows
        float pull = (vnoise(w.y * 90.0, 13.0, tframe) - 0.5) * 0.030 + (hash21(vec2(tline, 17.0), tframe) - 0.5) * 0.003;
        w.x += pull * tband * trk + sin(w.y * 37.0 + PTS * 9.0) * 0.0015 * trk;
        // head-switching: the last lines bend sideways, more toward the bottom edge
        hsw = smoothstep(0.965 - 0.03 * trk, 1.0, w.y);
        w.x += hsw * hsw * (0.008 + 0.030 * trk) * (0.75 + 0.5 * vnoise(w.y * 400.0, 5.0, tframe));
        w.y += (hash21(vec2(3.0, 9.0), tframe) - 0.5) * 0.004 * trk * trk;
        w = clamp(w, 0.0, 1.0);
    }

    // Use video time, so paused redraws keep the noise still without Lua option updates.
    // The noise seed advances at 24 steps/second; the band takes about 20 seconds to cross.
    float t = mod(PTS, 4096.0) * 24.0;
    float bandpos = fract(PTS * 0.05);
    // analog instability: a faint interference band and tiny per-line horizontal jitter
    if (noise > 0.0) {
        float line = floor(w.y * HOOKED_size.y * 0.5);
        float inband = smoothstep(0.07, 0.0, abs(w.y - bandpos));
        float jit = (hash21(vec2(line, 7.0), t) - 0.5) * (0.0016 + 0.0050 * inband) * noise;
        w.x = clamp(w.x + jit, 0.0, 1.0);
    }
    vec3 c = HOOKED_tex(rc + w * rs).rgb;
    int sig = int(ntsc + 0.5);
    if (sig > 0) {
        // Chroma (I/Q) travels on a narrow, delayed band: it is blurred wider than luma and smeared to the right.
        // S-Video keeps luma clean; composite also leaks luma into colour (rainbow fringes) and colour into luma
        // (dot crawl); RF adds heavy colour bleed and softens luma too.
        float bleed = sig == 1 ? 0.0110 : (sig == 2 ? 0.0180 : 0.0420);
        float ysoft = sig == 3 ? 0.0050 : (sig == 2 ? 0.0012 : 0.0);
        float xtalk = sig == 2 ? 1.10 : (sig == 3 ? 0.70 : 0.0);
        vec3 acc = vec3(0.0);
        float wsum = 0.0, ysum = 0.0, ywsum = 0.0;
        for (int k = 0; k < 9; k++) {
            float f = float(k) / 8.0;
            float cw = exp(-pow((f - 0.8) * 2.2, 2.0));                                   // heavier near the pixel, tail to the left
            vec2 tp = vec2(clamp(w.x + bleed * (f * 1.3 - 1.0), 0.0, 1.0), w.y);
            vec3 q = rgb2yiq(HOOKED_tex(rc + tp * rs).rgb);
            acc += vec3(0.0, q.y, q.z) * cw; wsum += cw;
            if (ysoft > 0.0) {
                vec2 yp = vec2(clamp(w.x + ysoft * (f * 2.0 - 1.0), 0.0, 1.0), w.y);
                ysum += rgb2yiq(HOOKED_tex(rc + yp * rs).rgb).x; ywsum += 1.0;
            }
        }
        vec3 orig = rgb2yiq(c);
        float Y = ysoft > 0.0 ? ysum / ywsum : orig.x;
        vec2 iq = acc.yz / wsum;
        if (xtalk > 0.0) {
            float xp = floor(w.x * HOOKED_size.x * rs.x * 0.5);
            float yl = floor(w.y * HOOKED_size.y * rs.y * 0.5);
            float phi = 1.5708 * xp + 3.14159 * yl + 0.7854 * t;          // subcarrier phase: crawls over time
            float detail = orig.x - Y;                                                // fine luma detail (luma minus its soft version)
            iq += xtalk * detail * vec2(cos(phi), sin(phi)) * 0.9;                    // rainbow fringes on edges
            Y += xtalk * 0.045 * (iq.x * cos(phi) + iq.y * sin(phi));                  // dot crawl on colour edges
        }
        c = yiq2rgb(vec3(Y, iq));
    }

    // colour controls, applied to the picture before the CRT effects (so the glow and scanlines build on them)
    c = mix(vec3(dot(c, vec3(0.299, 0.587, 0.114))), c, saturation);
    c = (c - 0.5) * contrast + 0.5;
    c = max(c, 0.0);

    // tracking noise: thin, soft-edged white streaks of random length (one pixel row each), a fine sparkle and a
    // little colour loss inside the band; a faint grain where head-switching bends the bottom lines
    if (tband > 0.0 || hsw > 0.0) {
        float seed = hash21(vec2(tline, 29.0), tframe);                   // each row gets its own streak pattern
        float n = vnoise(tx / mix(14.0, 70.0, seed) + seed * 97.0, tline, tframe);
        float thr = 0.93 - 0.20 * trk;                                     // more streaks the further off it is
        float streak = smoothstep(thr, thr + 0.05, n) * (0.35 + 0.65 * seed);
        float sparkle = step(0.992 - 0.02 * trk, hash21(vec2(tx, tline), tframe));
        c = mix(c, vec3(dot(c, vec3(0.299, 0.587, 0.114))), tband * 0.35 * trk);
        c = mix(c, vec3(0.92), clamp((streak + sparkle * 0.7) * tband, 0.0, 1.0));
        c = mix(c, vec3(hash21(vec2(tx, tline + 7.0), tframe)), hsw * 0.25 * (0.4 + trk));
    }

    // channel-change static: snow over the picture, clearing as the set locks on
    if (snow > 0.0) {
        float n = hash21(floor(w * rs * HOOKED_size * 0.5), floor(fxt * 60.0));
        c = mix(c, vec3(n * (0.75 + 0.25 * sin(w.y * 6.0 + fxt * 12.0))), snow);
    }

    // degauss: colour purity blotches swirl across the screen and fade out
    if (degauss > 0.0) {
        vec2 g = (w - 0.5) * vec2(rs.x * HOOKED_size.x / (rs.y * HOOKED_size.y), 1.0);
        float sw = atan(g.y, g.x) * 2.0 + length(g) * 9.0 - fxt * 6.0;
        vec3 tint = 0.5 + 0.5 * cos(sw + vec3(0.0, 2.094, 4.189));
        c = mix(c, c * (0.45 + 1.2 * tint), degauss * 0.65);
        c *= 1.0 + 0.2 * degauss;
    }

    // glow: lift mids slightly, soft bloom from neighbours
    vec2 px = HOOKED_pt * 1.5 / rs;
    vec3 b = (HOOKED_tex(rc + (w + vec2(px.x, 0.0)) * rs).rgb + HOOKED_tex(rc + (w - vec2(px.x, 0.0)) * rs).rgb
            + HOOKED_tex(rc + (w + vec2(0.0, px.y)) * rs).rgb + HOOKED_tex(rc + (w - vec2(0.0, px.y)) * rs).rgb) * 0.25;
    c = mix(c, max(c, b), glow * 0.5);

    // on-screen display, drawn into the picture so it inherits curvature, scanlines and mask.
    // Like a real TV menu the lit cells replace the video underneath, with a soft green bloom around them.
    if (mute > 0.5 || episode > 0.5) {
        vec2 g = vec2(w.x * asp.x, w.y) * 140.0 - vec2(12.0, 9.5);
        if (g.x > -6.0 && g.x < 48.0 && g.y > -6.0 && g.y < 15.0) {
            float core = osd_core(g);
            float halo = osd_halo(g);
            c += vec3(0.02, 0.95, 0.18) * halo * 0.70;                // green bloom
            c = mix(c, vec3(0.40, 1.00, 0.52), core);                 // lit phosphor
            c += vec3(0.15, 0.55, 0.20) * core * 0.30;                // slight overdrive
        }
    }

    // scanlines: one dark gap per source line, brighter pixels bloom wider
    float lum = dot(c, vec3(0.299, 0.587, 0.114));
    float ph = w.y * lines;
    float s = 0.5 + 0.5 * cos(6.2831853 * ph);          // 1 centre of line, 0 gap
    float width = mix(1.6, 0.8, lum);
    float prof = pow(s, width);
    c *= mix(1.0, prof, scan);
    c *= 1.0 + scan * 0.55 + glow * 0.35;               // compensate average darkening

    // RGB phosphor mask on physical pixels
    float xp = floor((rc.x + w.x * rs.x) * HOOKED_size.x);
    vec3 m = vec3(1.0);
    float k = mod(xp, 3.0);
    m = (k < 1.0) ? vec3(1.0, 1.0 - mask, 1.0 - mask)
      : (k < 2.0) ? vec3(1.0 - mask, 1.0, 1.0 - mask)
      :             vec3(1.0 - mask, 1.0 - mask, 1.0);
    c *= m * (1.0 + mask * 0.5);

    // vignette
    vec2 v = cc * 0.5;
    c *= 1.0 - vig * dot(v, v) * 1.6;

    // analog noise: luma grain (finer than a scanline), a little chroma noise, and a brighter rolling band
    if (noise > 0.0) {
        vec2 px = floor(rc * HOOKED_size + w * rs * HOOKED_size * 0.5) ;
        float gl = hash21(px, t) - 0.5;
        vec3 gc = vec3(hash21(px + 11.0, t), hash21(px + 23.0, t), hash21(px + 37.0, t)) - 0.5;
        float lumc = dot(c, vec3(0.299, 0.587, 0.114));
        float amp = noise * (0.30 + 0.70 * (1.0 - lumc * 0.6));                 // grain shows more in darker parts
        c += vec3(gl) * amp * 0.55 + gc * amp * 0.16;
        float band = smoothstep(0.07, 0.0, abs(w.y - bandpos));
        c += vec3(0.5, 0.52, 0.55) * band * noise * 0.16 * (0.6 + hash21(vec2(floor(w.y * 90.0), 3.0), t));
    }

    // glass reflection: a room light mirrored in the curved tube, laid over the picture (screen blend)
    if (shine > 0.0) {
        vec2 g = cc;
        float soft  = exp(-dot((g - vec2(-0.50, -0.58)) * vec2(1.05, 1.45), (g - vec2(-0.50, -0.58)) * vec2(1.05, 1.45)) * 3.2);
        float band  = smoothstep(0.17, 0.0, abs((g.x + g.y) * 0.7071 + 0.62));                   // diagonal streak
        band       *= smoothstep(1.15, 0.15, length(g - vec2(-0.55, -0.55)));                   // fades away from the corner
        float rim   = smoothstep(0.045, 0.0, 1.0 - abs(g.y)) * smoothstep(0.9, 0.2, abs(g.x)) * step(g.y, 0.0);   // glint along the top edge
        float curv  = smoothstep(0.0, 1.0, 0.35 + curve);                                         // curvier glass, stronger reflection
        float h = (soft * 0.85 + band * 0.55 + rim * 0.40) * shine * curv;
        vec3 tint = vec3(0.92, 0.96, 1.0);
        c = 1.0 - (1.0 - c) * (1.0 - tint * clamp(h, 0.0, 0.85));
    }

    // warm-up / power-off: the squeezed beam burns white-hot, the tube warms up, the last dot fades out
    c = mix(c * bright, vec3(0.92, 0.96, 1.0) * 1.15, flash * 0.85) * fade;

    c *= edge;
    if (edge < 1.0 && bezel > 0.0)                                 // the rounded corners: lit like the bezel next to them
        c += screen_light((uv - 0.5) * asp, rc, rs, asp) * (1.0 - edge);
    return vec4(clamp(c, 0.0, 1.0), 1.0);
}
