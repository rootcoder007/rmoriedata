/* SPDX-License-Identifier: AGPL-3.0-or-later
 *
 * zsgen.c -- inputs for the differential and mutation runs of dev/fuzz/zsfuzz.c,
 * made with the reference library (link with -lzstd; not part of the package).
 *
 *   zsgen rand OUT COUNT SEED   COUNT random inputs of varied structure (random
 *                               bytes, runs, small alphabets, words, copies of
 *                               earlier data, short periods, counters; 0 B to
 *                               2 MiB, block-boundary sizes among them), each
 *                               compressed at a random level from -7 to 22 with
 *                               random checksum, content-size, window-log,
 *                               long-distance and strategy settings; one in ten
 *                               is 2-4 frames, sometimes with skippable frames
 *   zsgen files OUT F...        the frames F..., each with what libzstd
 *                               decompresses it to
 *
 * OUT holds records (u64 n, u64 m, n plain bytes, m frame bytes), little endian.
 */
#define ZSTD_STATIC_LINKING_ONLY
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <zstd.h>

static uint64_t s = 88172645463325252ULL;
static uint64_t rnd(void) { s ^= s << 13; s ^= s >> 7; s ^= s << 17; return s; }
static size_t rndn(size_t n) { return n ? (size_t) (rnd() % n) : 0; }
static double unif(void) { return (double) (rnd() >> 11) / 9007199254740992.0; }

typedef struct { unsigned char *p; size_t n, cap; } buf;
static void put(buf *b, const void *x, size_t n) {
    if (b->n + n > b->cap) {
        b->cap = (b->n + n) * 2 + 64;
        b->p = (unsigned char *) realloc(b->p, b->cap);
        if (!b->p) { fprintf(stderr, "out of memory\n"); exit(2); }
    }
    if (n) memcpy(b->p + b->n, x, n);
    b->n += n;
}
static void putc1(buf *b, int c) { unsigned char x = (unsigned char) c; put(b, &x, 1); }

static const char *words[] = {
    "the", "of", "and", "to", "in", "is", "was", "for", "on", "that", "with", "police",
    "court", "officer", "report", "incident", "2023", "2024", "Toronto", "Ontario",
    "complaint", "arrest", "north", "south", "street", "avenue", "NA", "0", "1", "true"};

static void gen(buf *o) {
    size_t target;
    static const size_t edges[] = {131071, 131072, 131073, 262144, 262145, 1 << 20};
    o->n = 0;
    target = unif() < 0.95 ? 1 + (size_t) (unif() * unif() * 2097151.0) : edges[rndn(6)];
    if (unif() < 0.03) target = 0;
    while (o->n < target) {
        size_t k = rndn(8), n = 1 + (size_t) (unif() * unif() * 131071.0), i;
        if (n > target - o->n) n = target - o->n;
        switch (k) {
        case 0: for (i = 0; i < n; i++) putc1(o, (int) (rnd() & 255)); break;
        case 1: { int c = (int) rndn(256); for (i = 0; i < n; i++) putc1(o, c); break; }
        case 2: { size_t a = 1 + rndn(16); for (i = 0; i < n && i < 20000; i++) putc1(o, (int) rndn(a)); break; }
        case 3: {
            size_t start = o->n;
            while (o->n - start < n) {
                const char *w = words[rndn(sizeof words / sizeof *words)];
                static const char sep[] = " ,\n ";
                put(o, w, strlen(w));
                putc1(o, sep[rndn(4)]);
            }
            o->n = start + n;
            break;
        }
        case 4:
            if (o->n) {
                size_t j = rndn(o->n), len = n < o->n - j ? n : o->n - j;
                for (i = 0; i < len; i++) putc1(o, o->p[j + i]);
                break;
            }
            /* fall through */
        case 5: {
            unsigned char pat[40];
            size_t pl = 1 + rndn(39);
            for (i = 0; i < pl; i++) pat[i] = (unsigned char) rnd();
            for (i = 0; i < n; i++) putc1(o, pat[i % pl]);
            break;
        }
        case 6: {
            uint32_t v = (uint32_t) rnd(), step = 1 + (uint32_t) rndn(8);
            for (i = 0; i < n / 4 + 1 && i < 30000; i++) { uint32_t x = v + (uint32_t) i * step; put(o, &x, 4); }
            break;
        }
        default:
            for (i = 0; i < n && i < 30000; i++) putc1(o, (int) ((i * 7 + (i >> 5)) & 255));
            break;
        }
    }
    if (o->n > target) o->n = target;
}

static void compress(ZSTD_CCtx *c, const buf *in, buf *out) {
    size_t cap = ZSTD_compressBound(in->n), m;
    ZSTD_CCtx_reset(c, ZSTD_reset_session_and_parameters);
    ZSTD_CCtx_setParameter(c, ZSTD_c_compressionLevel, (int) rndn(30) - 7);
    ZSTD_CCtx_setParameter(c, ZSTD_c_checksumFlag, (int) rndn(2));
    ZSTD_CCtx_setParameter(c, ZSTD_c_contentSizeFlag, (int) rndn(2));
    if (unif() < 0.15) ZSTD_CCtx_setParameter(c, ZSTD_c_enableLongDistanceMatching, 1);
    if (unif() < 0.3) ZSTD_CCtx_setParameter(c, ZSTD_c_windowLog, 10 + (int) rndn(14));
    if (unif() < 0.2) ZSTD_CCtx_setParameter(c, ZSTD_c_strategy, 1 + (int) rndn(9));
    if (out->n + cap > out->cap) { out->cap = out->n + cap + 64; out->p = (unsigned char *) realloc(out->p, out->cap); }
    m = ZSTD_compress2(c, out->p + out->n, cap, in->p, in->n);
    if (ZSTD_isError(m)) { fprintf(stderr, "compress: %s\n", ZSTD_getErrorName(m)); exit(2); }
    out->n += m;
}

static void record(FILE *f, const buf *plain, const buf *frame) {
    uint64_t h[2];
    unsigned char le[16];
    int i;
    h[0] = plain->n; h[1] = frame->n;
    for (i = 0; i < 16; i++) le[i] = (unsigned char) (h[i / 8] >> (8 * (i % 8)));
    if (fwrite(le, 1, 16, f) != 16 || fwrite(plain->p, 1, plain->n, f) != plain->n ||
        fwrite(frame->p, 1, frame->n, f) != frame->n) { perror("write"); exit(2); }
}

int main(int argc, char **argv) {
    buf plain = {0, 0, 0}, frame = {0, 0, 0}, part = {0, 0, 0};
    FILE *f;
    if (argc >= 5 && strcmp(argv[1], "rand") == 0) {
        long count = atol(argv[3]), k;
        ZSTD_CCtx *c = ZSTD_createCCtx();
        s ^= strtoull(argv[4], NULL, 10) * 0x9E3779B97F4A7C15ULL;
        f = fopen(argv[2], "wb");
        if (!f) { perror(argv[2]); return 2; }
        for (k = 0; k < count; k++) {
            frame.n = 0;
            if (unif() < 0.1) {
                int parts = 2 + (int) rndn(3), j;
                buf all = {0, 0, 0};
                for (j = 0; j < parts; j++) {
                    gen(&part);
                    if (part.n > 50000) part.n = 50000;
                    put(&all, part.p, part.n);
                    if (unif() < 0.4) {
                        uint32_t hd[2];
                        size_t q, sk = rndn(20);
                        hd[0] = 0x184D2A50u + (uint32_t) rndn(16); hd[1] = (uint32_t) sk;
                        put(&frame, hd, 8);
                        for (q = 0; q < sk; q++) putc1(&frame, (int) rnd());
                    }
                    compress(c, &part, &frame);
                }
                record(f, &all, &frame);
                free(all.p);
            } else {
                gen(&plain);
                compress(c, &plain, &frame);
                record(f, &plain, &frame);
            }
        }
        fclose(f);
        ZSTD_freeCCtx(c);
        printf("libzstd %s, %ld records\n", ZSTD_versionString(), count);
        return 0;
    }
    if (argc >= 4 && strcmp(argv[1], "files") == 0) {
        int i;
        f = fopen(argv[2], "wb");
        if (!f) { perror(argv[2]); return 2; }
        for (i = 3; i < argc; i++) {
            FILE *g = fopen(argv[i], "rb");
            unsigned char tmp[65536];
            size_t got, n;
            if (!g) { perror(argv[i]); return 2; }
            frame.n = 0;
            while ((got = fread(tmp, 1, sizeof tmp, g)) > 0) put(&frame, tmp, got);
            fclose(g);
            {
                ZSTD_DCtx *d = ZSTD_createDCtx();
                ZSTD_inBuffer in = {0, 0, 0};
                plain.n = 0;
                in.src = frame.p; in.size = frame.n;
                for (;;) {
                    ZSTD_outBuffer ob = {tmp, sizeof tmp, 0};
                    n = ZSTD_decompressStream(d, &ob, &in);
                    if (ZSTD_isError(n)) { fprintf(stderr, "%s: %s\n", argv[i], ZSTD_getErrorName(n)); return 2; }
                    put(&plain, tmp, ob.pos);
                    if (in.pos == in.size && ob.pos < ob.size) break;
                }
                ZSTD_freeDCtx(d);
            }
            record(f, &plain, &frame);
        }
        fclose(f);
        return 0;
    }
    fprintf(stderr, "usage: zsgen rand OUT COUNT SEED | zsgen files OUT FRAME...\n");
    return 2;
}
