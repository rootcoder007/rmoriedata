#!/bin/sh
# SPDX-License-Identifier: AGPL-3.0-or-later
# zsfix.sh DIR: make the zstd test vectors in DIR (tests/testthat/fixtures/zstd)
# with the zstd command-line tool, and DIR/index.csv with each one's decompressed
# size and SHA-256, so the tests need no zstd. The inputs are generated here
# (text from seq, fixed patterns, and random bytes from /dev/urandom, whose hash
# is recorded); rerunning gives new random vectors, which is fine. Each
# SHA-256 is of what `zstd -dc` gives, so the two hand-built frames are checked
# by the reference tool too.
set -eu
d=$1
mkdir -p "$d"
t=$(mktemp -d)
trap 'rm -rf "$t"' EXIT
z() { zstd -q -f "$@"; }

: > "$t/empty"
printf a > "$t/one"
printf 'hello hello hello world\n' > "$t/short"
# lines drawn from 16 fixed six-word phrases: compressible text, one block
words() {
  awk -v n=$1 -v k=$2 'BEGIN { srand(7)
    split("police court report street north south arrest complaint open closed", w, " ")
    for (i = 1; i <= k; i++) { s = ""; for (j = 0; j < 6; j++) s = s w[1 + int(rand() * 10)] " "; L[i] = s }
    c = 0
    while (c < n) { x = L[1 + int(rand() * k)] (rand() < 0.5 ? int(rand() * 10) : "") "\n"; printf "%s", x; c += length(x) }
  }' | head -c $1
}
words 50000 16 > "$t/mid"
# multi-block inputs whose level-19 frames use RLE, repeat and treeless modes
words 140000 16 > "$t/phrases"
seq 1 40000 | head -c 100000 > "$t/digits"
head -c 4096 /dev/urandom > "$t/rand"
for n in 131071 131072 131073 262145; do
  yes 'zstd block boundary' | head -c $n > "$t/edge$n"
done
yes 'abcdefgh' | head -c 1000000 > "$t/rep"
head -c 300000 /dev/zero > "$t/zeros"
# an 8 KiB random block, 4 MiB of zeros, the same block again: one match 4 MiB back
head -c 8192 /dev/urandom > "$t/blk"
{ cat "$t/blk"; head -c 4194304 /dev/zero; cat "$t/blk"; } > "$t/far"
# bytes 0 to 3: four Huffman weights, written directly rather than FSE-coded
head -c 400000 /dev/urandom | tr -dc '\000-\003' | head -c 6000 > "$t/sym4"
# 500 random letters a to d: zstd finds no match worth coding, so the block is
# literals with no sequences
head -c 40000 /dev/urandom | tr -dc abcd | head -c 500 > "$t/letters"

z "$t/empty" -o "$d/empty.zst"
z "$t/one" -o "$d/one.zst"
z "$t/short" -o "$d/short.zst"
z --no-check "$t/short" -o "$d/short-nocheck.zst"
for l in 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16 17 18 19; do
  z -$l "$t/mid" -o "$d/mid-l$l.zst"
done
z --ultra -22 "$t/mid" -o "$d/mid-l22.zst"
z --no-check -3 "$t/mid" -o "$d/mid-nocheck.zst"
z "$t/rand" -o "$d/rand.zst"
for n in 131071 131072 131073 262145; do z -19 "$t/edge$n" -o "$d/edge$n.zst"; done
z -19 "$t/rep" -o "$d/rep.zst"
z "$t/zeros" -o "$d/zeros.zst"
z --long=23 -19 "$t/far" -o "$d/far.zst"
z -19 "$t/sym4" -o "$d/sym4.zst"
z -19 "$t/letters" -o "$d/letters.zst"
z -19 "$t/phrases" -o "$d/phrases.zst"
z -19 "$t/digits" -o "$d/digits.zst"
# hand-built: "abc" as literals, then one sequence with RLE literal-length,
# offset and match-length codes (offset 3, length 3): "abcabc", in a frame
# with a 1 KiB window and no content size
printf '\050\265\057\375\000\000\125\000\000\030abc\001\124\003\002\000\006' > "$d/rlemodes.zst"
# hand-built: a raw block "abcd", then 32512 sequences (the 3-byte count form),
# each a 3-byte match with no literals and offset code 0 (repeat offsets)
printf '\050\265\057\375\240\004\175\001\000\040\000\000abcd\115\000\000\000\377\000\000\124\000\000\000\001' > "$d/nseq3.zst"
# two frames back to back
cat "$d/short.zst" "$d/one.zst" > "$d/concat.zst"
cat "$t/short" "$t/one" > "$t/concat"
# a skippable frame (magic 0x184D2A53, 5 bytes) and then a frame
{ printf '\123\052\115\030\005\000\000\000skip!'; cat "$d/short.zst"; } > "$d/skip.zst"
cp "$t/short" "$t/skip"
cp "$t/short" "$t/short-nocheck"
cp "$t/mid" "$t/mid-nocheck"
cp "$t/mid" "$t/mid-l22"

echo "file,size,sha256" > "$d/index.csv"
for f in "$d"/*.zst; do
  b=$(basename "$f" .zst)
  zstd -q -d -c "$f" > "$t/out"
  case $b in mid-l*) src=$t/mid ;; rlemodes|nseq3) src=$t/out ;; *) src=$t/$b ;; esac
  cmp -s "$src" "$t/out" || { echo "zstd -d does not give the input of $b" >&2; exit 1; }
  echo "$b.zst,$(wc -c < "$t/out" | tr -d ' '),$(sha256sum "$t/out" | cut -c1-64)" >> "$d/index.csv"
done
