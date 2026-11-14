#!/bin/sh
# SPDX-License-Identifier: AGPL-3.0-or-later
# zscover.sh: build zsfuzz with the decoder's coverage counters (-DZS_TRACE) and
# decode every vector in tests/testthat/fixtures/zstd; print how many vectors
# reach each case and fail if any block type, literals type, Huffman weight form,
# sequence mode (literal lengths, offsets, match lengths), repeat-offset case or
# sequence-count form is reached by none.
set -eu
here=$(cd "$(dirname "$0")/../.." && pwd)
d=$here/tests/testthat/fixtures/zstd
t=$(mktemp -d)
trap 'rm -rf "$t"' EXIT
${CC:-cc} -std=c99 -O1 -DZS_TRACE "$here/dev/fuzz/zsfuzz.c" -o "$t/zsfuzz"
tail -n +2 "$d/index.csv" | while IFS=, read -r f n sha; do
  "$t/zsfuzz" dec "$d/$f" "$n" | head -1 | tr ' ' '\n' | sed -n 's/=.*//p'
done | sort | uniq -c > "$t/cov"
cat "$t/cov"
miss=0
for c in blk_raw blk_rle blk_cmp lit_raw lit_rle lit_cmp1 lit_cmp4 lit_tl1 lit_tl4 \
  huf_direct huf_fse seq_none ll_pre ll_rle ll_fse ll_rep of_pre of_rle of_fse of_rep \
  ml_pre ml_rle ml_fse ml_rep rep1 rep2 rep3 rep1m1 newoff overlap skip checksum \
  nseq2 nseq3; do
  grep -q " $c\$" "$t/cov" || { echo "not covered: $c"; miss=1; }
done
exit $miss
