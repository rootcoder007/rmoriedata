/* SPDX-License-Identifier: AGPL-3.0-or-later
 *
 * zsfuzz.c -- standalone driver for src/zstd.c, not part of the package
 * build. It includes the decoder directly (ZS_NO_R drops the R wrapper).
 *
 *   zsfuzz dec FILE SIZE [OUT]   decode FILE to SIZE bytes, optionally write OUT
 *   zsfuzz batch FILE            records (u64 n, u64 m, n plain bytes, m frame
 *                                bytes): decode each, byte-compare, count
 *   zsfuzz mut ITER SEED FILE    mutate the frames of a batch file ITER times
 *                                (bit flips, byte sets, truncation, splices,
 *                                insertions, deletions), decode each mutant with
 *                                a 2 s alarm, report outcomes and the slowest call
 *
 * Build with -DZS_TRACE to print the coverage counters after `dec` (zscover.sh
 * does this over the test vectors), and with -DZS_LIBFUZZER for a libFuzzer
 * target whose input is a 3-byte little-endian output size, then the frame.
 * Every buffer is allocated at its exact size so AddressSanitizer sees any
 * overrun. The runs reported for the decoder were:
 *
 *   cc -std=c99 -g -O1 -fsanitize=address,undefined -fno-sanitize-recover=all \
 *     zsfuzz.c -o zsfuzz
 *   cc -O2 zsgen.c -lzstd -o zsgen
 *   ./zsgen rand d.bin 1000 SEED && ./zsfuzz batch d.bin      (21 seeds)
 *   ./zsgen files c.bin ../../tests/testthat/fixtures/zstd/\*.zst
 *   ./zsfuzz mut 150000 1 c.bin
 *   clang -g -O1 -fsanitize=fuzzer,address,undefined -DZS_LIBFUZZER zsfuzz.c \
 *     -o zsfuzz_lf && ./zsfuzz_lf -max_total_time=900 -timeout=2 CORPUS
 */
#define _POSIX_C_SOURCE 200809L
#define ZS_NO_R
#include "../../src/zstd.c"

#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <time.h>
#include <unistd.h>

static int run(const uint8_t *src, size_t n, size_t cap, uint8_t **outp) {
    void *w = malloc(sizeof(zs_work));
    uint8_t *out = (uint8_t *) malloc(cap ? cap : 1);
    int rc;
    if (!w || !out) { fprintf(stderr, "out of memory\n"); exit(2); }
    rc = zs_decompress(src, n, out, cap, w);
    free(w);
    if (outp) *outp = out; else free(out);
    return rc;
}

#ifdef ZS_LIBFUZZER
int LLVMFuzzerTestOneInput(const uint8_t *d, size_t n) {
    uint8_t *src;
    size_t cap;
    if (n < 3) return 0;
    cap = (size_t) zs_le(d, 3) & ((1u << 22) - 1);
    src = (uint8_t *) malloc(n - 3 ? n - 3 : 1);
    if (n > 3) memcpy(src, d + 3, n - 3);
    run(src, n - 3, cap, NULL);
    free(src);
    return 0;
}
#else

static uint8_t *slurp(const char *path, size_t *n) {
    FILE *f = fopen(path, "rb");
    uint8_t *buf;
    long len;
    if (!f) { perror(path); exit(2); }
    fseek(f, 0, SEEK_END);
    len = ftell(f);
    fseek(f, 0, SEEK_SET);
    buf = (uint8_t *) malloc(len ? (size_t) len : 1);
    if (!buf || fread(buf, 1, (size_t) len, f) != (size_t) len) { perror(path); exit(2); }
    fclose(f);
    *n = (size_t) len;
    return buf;
}

typedef struct { size_t n, m; const uint8_t *plain, *frame; } rec;

static rec *records(const uint8_t *buf, size_t len, size_t *count) {
    size_t p = 0, k = 0, cap = 1024;
    rec *r = (rec *) malloc(cap * sizeof *r);
    while (p + 16 <= len) {
        uint64_t n = zs_le(buf + p, 8), m = zs_le(buf + p + 8, 8);
        p += 16;
        if (n > len - p || m > len - p - n) { fprintf(stderr, "bad batch file\n"); exit(2); }
        if (k == cap) { cap *= 2; r = (rec *) realloc(r, cap * sizeof *r); }
        r[k].n = (size_t) n; r[k].m = (size_t) m;
        r[k].plain = buf + p; r[k].frame = buf + p + n;
        p += (size_t) (n + m);
        k++;
    }
    *count = k;
    return r;
}

static uint64_t rng_s = 88172645463325252ULL;
static uint64_t rnd(void) {
    rng_s ^= rng_s << 13; rng_s ^= rng_s >> 7; rng_s ^= rng_s << 17;
    return rng_s;
}
static size_t rndn(size_t n) { return n ? (size_t) (rnd() % n) : 0; }

static void on_alarm(int sig) {
    static const char msg[] = "HANG: a call took longer than 2 s\n";
    (void) sig;
    if (write(2, msg, sizeof msg - 1) < 0) _exit(3);
    _exit(3);
}

static double now(void) {
    struct timespec t;
    clock_gettime(CLOCK_MONOTONIC, &t);
    return (double) t.tv_sec + 1e-9 * (double) t.tv_nsec;
}

/* One mutant of record a (sometimes spliced with b) into a fresh buffer. */
static uint8_t *mutate(const rec *a, const rec *b, size_t *outn) {
    size_t n = a->m, room = a->m + b->m + 64, ops = 1 + rndn(4), i;
    uint8_t *x = (uint8_t *) malloc(room);
    memcpy(x, a->frame, n);
    for (i = 0; i < ops; i++) {
        size_t j, k, len;
        switch (rndn(8)) {
        case 0: case 1: /* bit flips */
            for (k = 1 + rndn(8); k > 0 && n; k--) x[rndn(n)] ^= (uint8_t) (1u << rndn(8));
            break;
        case 2: { /* interesting byte */
            static const uint8_t v[] = {0, 1, 0x7f, 0x80, 0xff, 0xfe, 3, 0x20};
            if (n) x[rndn(n)] = rndn(2) ? v[rndn(sizeof v)] : (uint8_t) rnd();
            break;
        }
        case 3: /* truncate */
            n = rndn(n + 1);
            break;
        case 4: /* splice: prefix of a, suffix of b */
            j = rndn(n + 1); k = rndn(b->m + 1);
            len = b->m - k;
            if (j + len > room) len = room - j;
            memcpy(x + j, b->frame + k, len);
            n = j + len;
            break;
        case 5: /* insert random bytes */
            len = 1 + rndn(8);
            if (n + len <= room) {
                j = rndn(n + 1);
                memmove(x + j + len, x + j, n - j);
                for (k = 0; k < len; k++) x[j + k] = (uint8_t) rnd();
                n += len;
            }
            break;
        case 6: /* delete a range */
            if (n) {
                j = rndn(n); len = 1 + rndn(n - j < 16 ? n - j : 16);
                memmove(x + j, x + j + len, n - j - len);
                n -= len;
            }
            break;
        default: /* copy a chunk over another place */
            if (n > 2) {
                j = rndn(n); k = rndn(n); len = 1 + rndn(32);
                if (j + len > n) len = n - j;
                if (k + len > n) len = n - k;
                memmove(x + k, x + j, len);
            }
            break;
        }
    }
    *outn = n;
    return x;
}

int main(int argc, char **argv) {
    if (argc >= 4 && strcmp(argv[1], "dec") == 0) {
        size_t n, cap = (size_t) strtoull(argv[3], NULL, 10);
        uint8_t *src = slurp(argv[2], &n), *out = NULL;
        int rc = run(src, n, cap, &out);
#ifdef ZS_TRACE
        {
            static const char *const names[ZT_N] = {
                "blk_raw", "blk_rle", "blk_cmp", "lit_raw", "lit_rle", "lit_cmp1",
                "lit_cmp4", "lit_tl1", "lit_tl4", "huf_direct", "huf_fse", "seq_none",
                "ll_pre", "ll_rle", "ll_fse", "ll_rep", "of_pre", "of_rle", "of_fse",
                "of_rep", "ml_pre", "ml_rle", "ml_fse", "ml_rep", "rep1", "rep2",
                "rep3", "rep1m1", "newoff", "overlap", "skip", "checksum", "nseq2",
                "nseq3"};
            int i;
            for (i = 0; i < ZT_N; i++) if (zs_trace[i]) printf("%s=%lu ", names[i], zs_trace[i]);
            printf("\n");
        }
#endif
        if (rc == ZS_OK && argc >= 5) {
            FILE *f = fopen(argv[4], "wb");
            if (!f || fwrite(out, 1, cap, f) != cap) { perror(argv[4]); return 2; }
            fclose(f);
        }
        free(src); free(out);
        printf("%s\n", rc == ZS_OK ? "ok" : zs_errmsg(rc));
        return rc == ZS_OK ? 0 : 1;
    }
    if (argc >= 3 && strcmp(argv[1], "batch") == 0) {
        size_t len, cnt, i, ok = 0, bad = 0;
        uint8_t *buf = slurp(argv[2], &len);
        rec *r = records(buf, len, &cnt);
        for (i = 0; i < cnt; i++) {
            uint8_t *src = (uint8_t *) malloc(r[i].m ? r[i].m : 1), *out = NULL;
            int rc;
            memcpy(src, r[i].frame, r[i].m);
            rc = run(src, r[i].m, r[i].n, &out);
            if (rc == ZS_OK && memcmp(out, r[i].plain, r[i].n) == 0) ok++;
            else { bad++; printf("record %lu (n=%lu): %s\n", (unsigned long) i, (unsigned long) r[i].n, rc == ZS_OK ? "bytes differ" : zs_errmsg(rc)); }
            free(src); free(out);
        }
        printf("batch: %lu records, %lu identical, %lu failed\n", (unsigned long) cnt, (unsigned long) ok, (unsigned long) bad);
        free(r); free(buf);
        return bad ? 1 : 0;
    }
    if (argc >= 5 && strcmp(argv[1], "mut") == 0) {
        size_t iter = (size_t) strtoull(argv[2], NULL, 10), len, cnt, i;
        unsigned long by[ZS_E_N];
        double worst = 0, t0 = now();
        uint8_t *buf;
        rec *r;
        int e;
        rng_s ^= strtoull(argv[3], NULL, 10) * 0x9E3779B97F4A7C15ULL;
        buf = slurp(argv[4], &len);
        r = records(buf, len, &cnt);
        if (!cnt) return 2;
        memset(by, 0, sizeof by);
        signal(SIGALRM, on_alarm);
        for (i = 0; i < iter; i++) {
            const rec *a = &r[rndn(cnt)], *b = &r[rndn(cnt)];
            size_t n, cap = a->n;
            uint8_t *x = mutate(a, b, &n), *src = (uint8_t *) malloc(n ? n : 1), *out = NULL;
            double t;
            int rc;
            memcpy(src, x, n);
            free(x);
            if (rndn(16) == 0) cap = rndn(2 * a->n + 2);
            t = now();
            alarm(2);
            rc = run(src, n, cap, &out);
            alarm(0);
            t = now() - t;
            if (t > worst) worst = t;
            by[rc]++;
            free(src); free(out);
        }
        printf("mut: %lu mutants from %lu frames in %.1f s, slowest call %.4f s\n", (unsigned long) iter, (unsigned long) cnt, now() - t0, worst);
        for (e = 0; e < ZS_E_N; e++) if (by[e]) printf("  %8lu  %s\n", by[e], e ? zs_errmsg(e) : "decoded");
        free(r); free(buf);
        return 0;
    }
    fprintf(stderr, "usage: zsfuzz dec FILE SIZE [OUT] | batch FILE | mut ITER SEED FILE\n");
    return 2;
}
#endif
