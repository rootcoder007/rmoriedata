# Native Apache Parquet reader and writer for R.
#
# VENDORED COPY. The same code as R/aaa_parquet.R in rmorie, which the
# R-arm sync copies into morie/r-package/morie/R, with the same C codecs
# (src/snappy.c, src/gzip.c, src/zstd.c). What differs, on purpose: here
# the two entry points are internal (rmorie Imports rmoriedata, so
# rmoriedata cannot Import rmorie without a dependency cycle, and
# exporting the same names from both would mask on the search path);
# there every function carries roxygen and the entry points are exported,
# and that reader also reads three-level LIST columns of a primitive type,
# which this one refuses. Fix bugs in all three copies.
#
# The R side of the family read and wrote Parquet through nanoparquet::
# (11 read calls and 5 write calls in rmoriedata alone). This file
# removes that dependency and is the R arm of the Python
# morie/fn/_parquet_core.py; the two decode the same bytes to the same
# values, which is what the parity harness checks.
#
# Scope was measured from the footers of the actual store, not assumed:
# format v1.0, encodings PLAIN / RLE_DICTIONARY / RLE, SNAPPY
# compression, physical types BYTE_ARRAY / INT32 / INT64 / BOOLEAN /
# DOUBLE. FLOAT, INT96, FIXED_LEN_BYTE_ARRAY and uncompressed pages are
# also handled. GZIP pages are read through zlib, and ZSTD pages
# (read only) through src/zstd.c, a decoder written from RFC 8878.
# Nested and repeated columns are refused rather than
# guessed at, because decoding a repeated column as flat would return a
# wrong row count instead of an error.
#
# References: parquet-format/parquet.thrift (field ids), the Thrift
# compact protocol spec, google/snappy/format_description.txt and RFC 8878.
#
# The codecs are in src/ (snappy.c, gzip.c, zstd.c), and so are the per-value
# loops over PLAIN string values (pqplain.c); everything else works on whole
# vectors. ponytail: the RLE reader still loops in R once per run, which is
# cheap for the store's files (one bit-packed run per page); move it to src/
# if files with millions of short runs ever matter.

# ---------------------------------------------------------------- thrift

.pqTStop <- 0x00L
.pqTTrue <- 0x01L
.pqTFalse <- 0x02L
.pqTByte <- 0x03L
.pqTI16 <- 0x04L
.pqTI32 <- 0x05L
.pqTI64 <- 0x06L
.pqTDouble <- 0x07L
.pqTBinary <- 0x08L
.pqTList <- 0x09L
.pqTSet <- 0x0AL
.pqTMap <- 0x0BL
.pqTStruct <- 0x0CL

# A decoder is a plain environment so the position advances by reference
# the way the Python reader's self.pos does; passing it around by value
# would need every helper to return (value, pos) pairs.
.pq_reader <- function(buf, pos = 1L) {
  e <- new.env(parent = emptyenv())
  e$buf <- buf
  e$pos <- pos
  e$depth <- 0L
  e
}

# Every read is bounds-checked: subsetting a raw vector past its end yields 00 bytes, not
# an error, and a reader built on that silently turns a truncated or lying file into wrong
# data. These are the only ways the decoder touches bytes.
.pq_need <- function(e, n) {
  if (!is.finite(n) || n < 0 || e$pos + n - 1 > length(e$buf)) {
    stop("parquet: truncated or corrupt metadata (", n, " bytes needed at byte ",
         e$pos, " of ", length(e$buf), ")", call. = FALSE)
  }
  invisible()
}

.pq_slice <- function(buf, pos, n, what = "data") {
  .pq_fits(length(buf), pos, n, what)
  if (n == 0) raw(0) else buf[seq.int(pos, length.out = n)]
}

# Refuses `n` bytes at `pos` (counted from 1) of something `len` bytes long that do not
# fit in it.
.pq_fits <- function(len, pos, n, what) {
  if (!all(is.finite(c(n, pos))) || min(n, pos - 1) < 0 || pos + n - 1 > len) {
    stop("parquet: ", what, " runs past the end of its page or chunk (", n,
         " bytes at ", pos, " of ", len, ")", call. = FALSE)
  }
  invisible(TRUE)
}

.pq_byte <- function(e) {
  .pq_need(e, 1)
  b <- as.integer(e$buf[e$pos])
  e$pos <- e$pos + 1L
  b
}

.pq_varint <- function(e) {
  result <- 0
  shift <- 0
  repeat {
    b <- .pq_byte(e)
    result <- result + bitwAnd(b, 127L) * 2^shift
    if (bitwAnd(b, 128L) == 0L) {
      return(result)
    }
    shift <- shift + 7
    # a 64-bit value takes at most 10 bytes; anything longer is not a varint
    if (shift > 63) {
      stop("parquet: varint longer than 10 bytes at byte ", e$pos, call. = FALSE)
    }
  }
}

.pq_zigzag <- function(e) {
  n <- .pq_varint(e)
  # (n >> 1) xor -(n & 1), written in doubles so values past 2^31 stay
  # exact up to 2^53 -- file offsets and row counts both live there.
  if (n %% 2 == 1) -(n + 1) / 2 else n / 2
}

.pq_binary <- function(e) {
  n <- .pq_varint(e)
  .pq_need(e, n)
  out <- if (n == 0) raw(0) else e$buf[seq.int(e$pos, length.out = n)]
  e$pos <- e$pos + n
  out
}

.pq_double <- function(e) {
  .pq_need(e, 8)
  v <- readBin(e$buf[seq.int(e$pos, length.out = 8L)], "double",
    n = 1L, size = 8L, endian = "little"
  )
  e$pos <- e$pos + 8L
  v
}

.pq_scalar <- function(e, ttype) {
  if (ttype == .pqTTrue) {
    return(TRUE)
  }
  if (ttype == .pqTFalse) {
    return(FALSE)
  }
  if (ttype == .pqTByte) {
    b <- .pq_byte(e)
    return(if (b > 127L) b - 256L else b)
  }
  if (ttype == .pqTI16 || ttype == .pqTI32 || ttype == .pqTI64) {
    return(.pq_zigzag(e))
  }
  if (ttype == .pqTDouble) {
    return(.pq_double(e))
  }
  if (ttype == .pqTBinary) {
    return(.pq_binary(e))
  }
  if (ttype == .pqTList || ttype == .pqTSet) {
    return(.pq_list(e))
  }
  if (ttype == .pqTMap) {
    return(.pq_map(e))
  }
  if (ttype == .pqTStruct) {
    return(.pq_struct(e))
  }
  stop("unknown thrift compact type ", ttype, " at byte ", e$pos,
    call. = FALSE
  )
}

# A list or map holds values that may be lists, maps or structs again: the same
# depth cap as .pq_struct, or 5000 nested list headers overflow R's stack.
.pq_deeper <- function(e) {
  e$depth <- e$depth + 1L
  if (e$depth > 64L) stop("parquet: metadata nested deeper than 64 levels", call. = FALSE)
}

.pq_list <- function(e) {
  .pq_deeper(e)
  on.exit(e$depth <- e$depth - 1L)
  h <- .pq_byte(e)
  size <- bitwShiftR(h, 4L)
  etype <- bitwAnd(h, 15L)
  if (size == 15L) size <- .pq_varint(e)
  if (size == 0) {
    return(list())
  }
  # every element takes at least one byte, booleans included
  if (size > length(e$buf) - e$pos + 1) {
    stop("parquet: list of ", size, " elements in ", length(e$buf) - e$pos + 1,
         " remaining bytes", call. = FALSE)
  }
  lapply(seq_len(size), function(i) .pq_scalar(e, etype))
}

.pq_map <- function(e) {
  .pq_deeper(e)
  on.exit(e$depth <- e$depth - 1L)
  size <- .pq_varint(e)
  if (size == 0) {
    return(list())
  }
  # a map entry is at least a key byte and a value byte; a 21-byte file claiming 2^56
  # entries used to loop until killed
  if (size > (length(e$buf) - e$pos) / 2) {
    stop("parquet: map of ", size, " entries in ", length(e$buf) - e$pos + 1,
         " remaining bytes", call. = FALSE)
  }
  kv <- .pq_byte(e)
  ktype <- bitwShiftR(kv, 4L)
  vtype <- bitwAnd(kv, 15L)
  out <- list()
  for (i in seq_len(size)) {
    k <- .pq_scalar(e, ktype)
    out[[rawToChar(k)]] <- .pq_scalar(e, vtype)
  }
  out
}

.pq_struct <- function(e) {
  .pq_deeper(e)
  on.exit(e$depth <- e$depth - 1L)
  out <- list()
  fid <- 0L
  repeat {
    h <- .pq_byte(e)
    if (h == .pqTStop) {
      return(out)
    }
    delta <- bitwShiftR(h, 4L)
    ttype <- bitwAnd(h, 15L)
    fid <- if (delta != 0L) fid + delta else as.integer(.pq_zigzag(e))
    out[[as.character(fid)]] <- .pq_scalar(e, ttype)
  }
}

# A field by its id. The key is the id's digits (sprintf("%d")): as.character() of a
# double follows options(scipen = ), and at -5 it wrote 3 as "3e+00", so no field was
# found and every file was "damaged".
.pq_f <- function(st, id, default = NULL) {
  v <- st[[sprintf("%d", id)]]
  if (is.null(v)) default else v
}

# Writer. Accumulates into a list of raw vectors and concatenates once,
# because growing a raw vector element by element is quadratic.
.pq_writer <- function() {
  e <- new.env(parent = emptyenv())
  e$parts <- list()
  e$n <- 0L
  e
}

.pq_emit <- function(e, r) {
  e$n <- e$n + 1L
  e$parts[[e$n]] <- r
  invisible(NULL)
}

.pq_wvarint <- function(e, n) {
  out <- raw(0)
  repeat {
    if (n < 128) {
      out <- c(out, as.raw(n))
      break
    }
    out <- c(out, as.raw(bitwOr(as.integer(n %% 128), 128L)))
    n <- n %/% 128
  }
  .pq_emit(e, out)
}

.pq_wzigzag <- function(e, n) {
  .pq_wvarint(e, if (n < 0) -2 * n - 1 else 2 * n)
}

# The bytes of a string as UTF-8, which is what a Parquet string is by
# definition. A string marked latin1 (or UTF-8) is transcoded by
# enc2utf8(); an unmarked string is written byte for byte when it already
# is valid UTF-8 (what read.csv() and the store give), because enc2utf8()
# would translate it from the native encoding, and in a C locale that
# turns every non-ASCII byte into its "<c3><a9>" display form. Unmarked
# bytes that are not UTF-8 are refused: written through they make a file
# no conforming reader opens, escaped they lose the data.
.pq_utf8 <- function(s, what = "a column") {
  s <- as.character(s)
  marked <- !is.na(s) & Encoding(s) != "unknown"
  if (any(marked)) s[marked] <- enc2utf8(s[marked])
  bad <- !is.na(s) & !validUTF8(s)
  if (any(bad)) {
    stop(what, " holds a string that is not valid UTF-8 (Parquet strings ",
         "are UTF-8): set its encoding with Encoding()<- or convert it ",
         "with iconv() before writing.", call. = FALSE)
  }
  s
}

.pq_wbinary <- function(e, b) {
  if (is.character(b)) b <- charToRaw(.pq_utf8(b))
  .pq_wvarint(e, length(b))
  .pq_emit(e, b)
}

.pq_wfield <- function(e, fid, ttype, last) {
  delta <- fid - last
  if (delta > 0 && delta <= 15) {
    .pq_emit(e, as.raw(bitwOr(bitwShiftL(delta, 4L), ttype)))
  } else {
    .pq_emit(e, as.raw(ttype))
    .pq_wzigzag(e, fid)
  }
  fid
}

.pq_wi32 <- function(e, fid, v, last) {
  last <- .pq_wfield(e, fid, .pqTI32, last)
  .pq_wzigzag(e, v)
  last
}

.pq_wi64 <- function(e, fid, v, last) {
  last <- .pq_wfield(e, fid, .pqTI64, last)
  .pq_wzigzag(e, v)
  last
}

.pq_wbytes <- function(e, fid, v, last) {
  last <- .pq_wfield(e, fid, .pqTBinary, last)
  .pq_wbinary(e, v)
  last
}

.pq_wlisthdr <- function(e, size, etype) {
  if (size < 15) {
    .pq_emit(e, as.raw(bitwOr(bitwShiftL(size, 4L), etype)))
  } else {
    .pq_emit(e, as.raw(bitwOr(240L, etype)))
    .pq_wvarint(e, size)
  }
}

.pq_wlisti32 <- function(e, fid, vals, last) {
  last <- .pq_wfield(e, fid, .pqTList, last)
  .pq_wlisthdr(e, length(vals), .pqTI32)
  for (v in vals) .pq_wzigzag(e, v)
  last
}

.pq_wlistbin <- function(e, fid, vals, last) {
  last <- .pq_wfield(e, fid, .pqTList, last)
  .pq_wlisthdr(e, length(vals), .pqTBinary)
  for (v in vals) .pq_wbinary(e, v)
  last
}

.pq_wliststruct <- function(e, fid, bodies, last) {
  last <- .pq_wfield(e, fid, .pqTList, last)
  .pq_wlisthdr(e, length(bodies), .pqTStruct)
  for (b in bodies) .pq_emit(e, b)
  last
}

.pq_wstruct <- function(e, fid, body, last) {
  last <- .pq_wfield(e, fid, .pqTStruct, last)
  .pq_emit(e, body)
  last
}

.pq_wstop <- function(e) {
  .pq_emit(e, as.raw(0L))
  do.call(base::c, e$parts)
}

# ---------------------------------------------------------------- snappy

.pq_snappy_decompress <- function(data) {
  # src/snappy.c: every snappy tag (literals, 1-, 2- and 4-byte-offset copies)
  .Call(C_rmd_snappy_decompress, data)
}

.pq_snappy_compress <- function(data) {
  # src/snappy.c: the reference greedy compressor (4-byte hash per 64 KiB block,
  # 2-byte-offset copies)
  .Call(C_rmd_snappy_compress, data)
}

# ------------------------------------------------------------- constants

.pqBoolean <- 0L
.pqInt32 <- 1L
.pqInt64 <- 2L
.pqInt96 <- 3L
.pqFloat <- 4L
.pqDouble <- 5L
.pqByteArray <- 6L
.pqFlba <- 7L
.pqEPlain <- 0L
.pqEPlainDict <- 2L
.pqERle <- 3L
.pqEBitPacked <- 4L
.pqERleDict <- 8L
.pqCUncompressed <- 0L
.pqCSnappy <- 1L
.pqCGzip <- 2L
.pqCZstd <- 6L
.pqRequired <- 0L
.pqOptional <- 1L
.pqRepeated <- 2L
.pqPData <- 0L
.pqPIndex <- 1L
.pqPDict <- 2L
.pqPDataV2 <- 3L
.pqCtUtf8 <- 0L
.pqCtDate <- 6L
.pqCtTsMillis <- 9L
.pqCtTsMicros <- 10L

# --------------------------------------------------------------- decoding

# Little-endian whole numbers of 4 or 8 bytes (src/pqplain.c), never through
# readBin(size = 4): it gives NA for the word 0x80000000 without a word, and that
# word is a value of every 32-bit half (2^31 as an INT64's low half, -2^63 as its
# high half, 2^31 as a UINT_32). Signed 4-byte values are integers, or doubles when
# one in the block is -2^31 (.pq_read() decides the column's type from its rows);
# unsigned ones and 8-byte ones are doubles, each rounded once.
.pq_ints <- function(r, width, unsigned = FALSE, pos = 1L,
                     count = length(r) %/% width) {
  .Call(C_rmd_pq_ints, r, pos, count, width, unsigned)
}

# unsigned 32-bit values: the footer length, a level length
.pq_u32 <- function(r) .pq_ints(r, 4L, TRUE)

.pq_bit_width <- function(n) {
  w <- 0L
  while (n > 0) {
    w <- w + 1L
    n <- bitwShiftR(n, 1L)
  }
  w
}

.pq_read_rle <- function(buf, pos, width, count, end) {
  if (width == 0L) {
    return(list(values = rep(0L, count), pos = pos))
  }
  if (width > 32L) stop("parquet: RLE bit width ", width, " above 32", call. = FALSE)
  # src/pqplain.c: one pass over the runs (a page of runs of one value each took
  # the R loop minutes)
  .Call(C_rmd_pq_rle, buf, pos, as.integer(width), count, min(end, length(buf)))
}

# The values of a PLAIN block as one vector of their type, and the position after
# them. FIXED_LEN_BYTE_ARRAY values are read as what `kind` says they are
# (.pq_flba_kind()): a DECIMAL's unscaled value, a UUID's text or a FLOAT16;
# INT32 and INT64 values as unsigned when `kind` is "unsigned"; INT64 values as
# seconds when `kind` is a number, the counts per second of a time (.pq_per()), and
# INT96 values always as seconds.
# `cname` names the column in the reader's messages.
.pq_decode_plain <- function(buf, pos, ptype, count, type_length = NULL,
                             cname = "?", kind = "decimal") {
  if (count == 0L) {
    empty <- if (ptype == .pqBoolean) logical() else if (ptype == .pqInt32) integer()
      else if (ptype == .pqByteArray || identical(kind, "uuid")) character()
      else numeric()
    return(list(values = empty, pos = pos))
  }
  take <- function(n) .pq_slice(buf, pos, n, "a PLAIN value block")
  if (ptype == .pqBoolean) {
    nb <- (count + 7L) %/% 8L
    bits <- as.integer(rawToBits(take(nb)))
    return(list(
      values = as.logical(bits[seq_len(count)]),
      pos = pos + nb
    ))
  }
  if (ptype == .pqInt32 || ptype == .pqInt64) {
    w <- if (ptype == .pqInt32) 4L else 8L
    if (pos + count * w - 1 > length(buf)) take(count * w)
    # an INT64 time (`kind` its counts per second) as seconds, rounded once
    v <- if (ptype == .pqInt64 && is.numeric(kind)) {
      .Call(C_rmd_pq_secs, buf, pos, count, 8L, kind)
    } else {
      .pq_ints(buf, w, identical(kind, "unsigned"), pos, count)
    }
    return(list(values = v, pos = pos + count * w))
  }
  if (ptype == .pqFloat) {
    v <- readBin(take(count * 4L), "double", n = count, size = 4L, endian = "little")
    return(list(values = v, pos = pos + count * 4L))
  }
  if (ptype == .pqDouble) {
    v <- readBin(take(count * 8L), "double", n = count, size = 8L, endian = "little")
    return(list(values = v, pos = pos + count * 8L))
  }
  if (ptype == .pqByteArray) {
    # src/pqplain.c: lengths and bytes in one pass; text that is not UTF-8 is refused
    return(.Call(C_rmd_pq_strings, buf, pos, count, cname))
  }
  if (ptype == .pqFlba) {
    if (is.null(type_length) || type_length < 1) {
      stop("FIXED_LEN_BYTE_ARRAY without a positive type_length", call. = FALSE)
    }
    if (pos + count * type_length - 1 > length(buf)) take(count * type_length)
    # src/pqplain.c, in place: no copy of the block, no raw vector a value
    vals <- .Call(C_rmd_pq_flba, buf, pos, count, type_length,
                  match(kind, c("decimal", "uuid", "float16")))
    return(list(values = vals, pos = pos + count * type_length))
  }
  if (ptype == .pqInt96) {
    # the legacy timestamp, as seconds since the epoch rounded once (src/pqplain.c)
    if (pos + count * 12 - 1 > length(buf)) take(count * 12L)
    vals <- .Call(C_rmd_pq_secs, buf, pos, count, 12L, 1e9)
    return(list(values = vals, pos = pos + count * 12L))
  }
  stop("unsupported physical type ", ptype, call. = FALSE)
}

# Logical types: the schema's converted_type (field 6, with the scale in field
# 7) and its newer LogicalType (field 10). What a writer marks is honoured or
# the column is refused: a DECIMAL returned as its unscaled whole number, an
# unsigned column as negative numbers, or a time as a bare count is a silent
# wrong value.
.pqCtDecimal <- 5L
.pqCtTimeMillis <- 7L
.pqCtTimeMicros <- 8L
.pqCtUint32 <- 13L
.pqCtUint64 <- 14L

# The counts per second of a TIME or TIMESTAMP logical type, or NULL.
.pq_unit <- function(lt) {
  u <- .pq_f(lt, 2)
  if (is.null(u)) {
    return(NULL)
  }
  if (!is.null(.pq_f(u, 1))) {
    1e3
  } else if (!is.null(.pq_f(u, 2))) {
    1e6
  } else if (!is.null(.pq_f(u, 3))) {
    1e9
  }
}

# The counts per second of a TIMESTAMP (named "ts") or a TIME (named "time") column,
# from its LogicalType first or its converted type; NULL for any other column (a
# timestamp of a unit the file does not name included).
.pq_per <- function(converted, logical) {
  lt <- function(id) if (is.null(logical)) NULL else .pq_f(logical, id)
  ct <- if (is.null(converted)) -1L else as.integer(converted)
  ts <- if (!is.null(lt(8))) .pq_unit(lt(8)) else if (ct == .pqCtTsMillis) 1e3
    else if (ct == .pqCtTsMicros) 1e6
  if (!is.null(ts)) return(c(ts = ts))
  tm <- if (!is.null(lt(7))) .pq_unit(lt(7)) else if (ct == .pqCtTimeMillis) 1e3
    else if (ct == .pqCtTimeMicros) 1e6
  if (!is.null(tm)) c(time = tm)
}

# TRUE when the schema element marks its column a DECIMAL.
.pq_is_decimal <- function(converted, logical) {
  identical(as.integer(converted), .pqCtDecimal) ||
    (!is.null(logical) && !is.null(.pq_f(logical, 5)))
}

# The converted type to read, or NULL when the LogicalType names the column's type:
# the format gives the LogicalType precedence, and arrow follows it. It won for a
# DECIMAL, a time and a timestamp, but an unsigned converted type was taken with a
# signed LogicalType, so UINT_32 with INT(32, signed) read the word 0xFFFFFFFF as
# 4294967295 where arrow reads -1. Dropped here, once, for every check that reads both.
.pq_converted <- function(converted, logical) {
  if (is.list(logical) && length(logical)) NULL else converted
}

# The width and signedness an INT32 or INT64 column is marked with,
# c(bits = , signed = ), from its IntType (LogicalType INTEGER) or its converted type
# (UINT_8 ... INT_64); NULL when it carries neither. An IntType without its (required)
# bit width is as wide as its type, and one without its signedness is signed. A width
# the format does not give its type (INT(8), INT(16) and INT(32) mark an INT32,
# INT(64) an INT64; arrow refuses the others) is refused by name.
.pq_int_mark <- function(ptype, converted, logical, name = "?") {
  m <- if (ptype %in% c(.pqInt32, .pqInt64)) .pq_int_given(ptype, converted, logical)
  if (is.null(m)) return(NULL)
  bw <- m$bits
  ok <- if (ptype == .pqInt64) c(64) else c(8, 16, 32)
  if (!(is.numeric(bw) && length(bw) == 1L && bw %in% ok)) {
    stop("parquet: column ", sQuote(name, FALSE), " is marked as a whole number of ",
         if (length(bw) == 1L) bw else "(no)", " bits stored as ",
         if (ptype == .pqInt64) "INT64" else "INT32", ", which Parquet does not allow",
         call. = FALSE)
  }
  c(bits = bw, signed = m$signed)
}

# The width and signedness as the column gives them (list(bits, signed)), unchecked,
# or NULL: from the IntType, else from the converted type.
.pq_int_given <- function(ptype, converted, logical) {
  it <- if (is.list(logical)) .pq_f(logical, 10)
  if (!is.null(it)) {
    return(list(bits = .pq_f(it, 1) %||% if (ptype == .pqInt64) 64 else 32,
                signed = !identical(.pq_f(it, 2), FALSE)))
  }
  ct <- if (is.null(converted)) -1L else as.integer(converted)
  # UINT_8, UINT_16, UINT_32, UINT_64, INT_8, INT_16, INT_32, INT_64
  if (ct %in% 11:18) {
    list(bits = c(8, 16, 32, 64)[(ct - 11L) %% 4L + 1L], signed = ct >= 15L)
  }
}

# TRUE when an INT32 or INT64 column holds unsigned whole numbers of 32 or 64 bits
# (UINT_32, UINT_64, or an unsigned IntType of 32 or 64 bits). The values are decoded
# unsigned (.pq_decode_plain()), so a UINT_64 is rounded once. A DECIMAL, a date, a
# time or a timestamp carries no int mark (.pq_converted()).
.pq_is_unsigned <- function(ptype, converted, logical) {
  m <- .pq_int_mark(ptype, converted, logical)
  !is.null(m) && !m[["signed"]] && m[["bits"]] >= 32
}

# An INT32 column marked 8 or 16 bits wide holds only what that width holds (0 to
# 255 for UINT_8, -128 to 127 for INT_8, ...): any other word is a damaged file, as a
# definition level past the column's maximum is, and is refused naming the column and
# the value. It came back negative (UINT_8 0xFFFFFFFF as -1), or turned the column
# into doubles (0x80000000).
.pq_int_range <- function(v, mark, name) {
  if (is.null(mark) || mark[["bits"]] >= 32) return(invisible(TRUE))
  b <- mark[["bits"]]
  lim <- if (mark[["signed"]]) c(-2^(b - 1), 2^(b - 1) - 1) else c(0, 2^b - 1)
  bad <- which(v < lim[1L] | v > lim[2L])
  if (!length(bad)) return(invisible(TRUE))
  x <- v[[bad[[1L]]]]
  w <- if (x < 0) x + 2^32 else x
  stop(sprintf(paste0("parquet: column '%s' is marked as %s %d-bit whole numbers ",
                      "(%.0f to %.0f) but holds the 32-bit word %.0f (0x%04X%04X); ",
                      "the file is damaged"),
               name, if (mark[["signed"]]) "signed" else "unsigned", as.integer(b),
               lim[1L], lim[2L], x, as.integer(w %/% 65536), as.integer(w %% 65536)),
       call. = FALSE)
}

# R holds whole numbers exactly up to 2^53: past that a 64-bit value is rounded,
# which is said once per column.
.pq_inexact <- function(v, name) {
  if (any(abs(v) >= 2^53, na.rm = TRUE)) {
    warning("parquet: column ", sQuote(name, FALSE), " holds whole numbers of 2^53 or ",
            "more, which R keeps as doubles: they are rounded", call. = FALSE)
  }
  invisible(NULL)
}

# What a FIXED_LEN_BYTE_ARRAY column holds, from its logical type: "decimal",
# "uuid" or "float16". Its length is the file's word, so it is held to what that
# kind is: a whole number of bytes from 1 to 2^31 - 1, 16 for a UUID and 2 for a
# FLOAT16. Bytes of no such kind (an INTERVAL, or bytes with no logical type)
# have no R value and are refused by name.
.pq_flba_kind <- function(leaf) {
  tl <- leaf$typelen
  nm <- sQuote(leaf$name, FALSE)
  if (!(is.numeric(tl) && length(tl) == 1L && tl >= 1 && tl <= .Machine$integer.max)) {
    stop("parquet: column ", nm, " holds fixed-length bytes of length ",
         if (is.numeric(tl) && length(tl) == 1L) tl else "(none)",
         "; Parquet needs a length from 1 to 2147483647", call. = FALSE)
  }
  lt <- function(id) !is.null(leaf$logical) && !is.null(.pq_f(leaf$logical, id))
  kind <- if (.pq_is_decimal(leaf$converted, leaf$logical)) "decimal"
    else if (lt(14)) "uuid" else if (lt(15)) "float16"
  if (is.null(kind)) {
    stop("parquet: column ", nm, " holds fixed-length bytes (an interval, or ",
         "bytes of no logical type), which this reader does not read; name the ",
         "columns to read in `columns`", call. = FALSE)
  }
  need <- c(uuid = 16, float16 = 2)[kind]
  if (!is.na(need) && tl != need) {
    # the type's name as the format spells it (toupper() follows the locale)
    stop("parquet: column ", nm, " is a ", c(uuid = "UUID", float16 = "FLOAT16")[[kind]],
         " of ", tl,
         " bytes; Parquet's is ", need, call. = FALSE)
  }
  kind
}

# The precision and scale of a DECIMAL column, checked against the format: a
# precision of 1 or more, a scale from 0 to the precision, and no more digits
# than the physical type holds (INT32 9, INT64 18, and n fixed bytes
# floor(log10(2^(8n - 1) - 1)), which is 38 for 16 and 76 for 32). The newer
# logical type's values are taken first; a precision that is not given (the
# format requires one) is taken to be the most the type holds.
.pq_decimal <- function(leaf) {
  dt <- if (is.null(leaf$logical)) NULL else .pq_f(leaf$logical, 5)
  if (!is.list(dt)) dt <- list()
  most <- switch(as.character(leaf$type), "1" = 9, "2" = 18,
                 "7" = floor((8 * leaf$typelen - 1) * log10(2)),
                 stop("parquet: column ", sQuote(leaf$name, FALSE), " is a DECIMAL ",
                      "stored as physical type ", leaf$type, ", which Parquet ",
                      "does not allow", call. = FALSE))
  s <- .pq_f(dt, 1) %||% leaf$scale %||% 0
  p <- .pq_f(dt, 2) %||% leaf$precision %||% most
  whole <- function(x) {
    is.numeric(x) && length(x) == 1L && is.finite(x) && x == floor(x)
  }
  num <- function(x) if (whole(x)) format(x, scientific = FALSE) else "(none)"
  if (!(whole(p) && whole(s) && p >= 1 && s >= 0 && s <= p)) {
    stop("parquet: column ", sQuote(leaf$name, FALSE), " is a DECIMAL of precision ",
         num(p), " and scale ", num(s), "; Parquet needs a precision of 1 or ",
         "more and a scale from 0 to the precision", call. = FALSE)
  }
  if (p > most) {
    held <- switch(as.character(leaf$type), "1" = "INT32, which holds",
                   "2" = "INT64, which holds",
                   paste(leaf$typelen, "bytes, which hold"))
    stop("parquet: column ", sQuote(leaf$name, FALSE), " is a DECIMAL of precision ",
         num(p), " in ", held, " at most ", most, " digits", call. = FALSE)
  }
  c(precision = p, scale = s)
}

# x / 10^s in steps no larger than 10^300, so that a scale past 308 (10^s is
# infinite) divides rather than giving 0 or NaN.
.pq_unscale <- function(x, s) {
  while (s > 300) {
    x <- x / 1e300
    s <- s - 300
  }
  x / 10^s
}

.pq_apply_logical <- function(v, ptype, converted, scale = NULL, logical = NULL,
                              name = "?") {
  lt <- function(id) if (is.null(logical)) NULL else .pq_f(logical, id)
  ct <- if (is.null(converted)) -1L else as.integer(converted)
  posix <- function(x) as.POSIXct(x, origin = "1970-01-01", tz = "UTC")
  if (.pq_is_decimal(converted, logical)) {
    s <- as.numeric(.pq_f(lt(5) %||% list(), 1) %||% scale %||% 0)
    # fixed bytes of more than 128 can hold a whole number past 2^1024
    if (any(is.infinite(v))) {
      stop("parquet: column ", sQuote(name, FALSE), " holds a DECIMAL whose unscaled ",
           "value is past the range of a double (2^1024)", call. = FALSE)
    }
    .pq_inexact(v, name)
    return(.pq_unscale(as.numeric(v), s))
  }
  # INT96 is the legacy timestamp, decoded as seconds (.pq_decode_plain())
  if (ptype == .pqInt96) {
    return(posix(v))
  }
  if ((ct == .pqCtDate || !is.null(lt(6))) && ptype == .pqInt32) {
    return(structure(as.numeric(v), class = "Date"))
  }
  # a time of INT64 is decoded as seconds; one of INT32 is a count, exact, divided once
  per <- .pq_per(converted, logical)
  if (!is.null(per)) {
    s <- if (ptype == .pqInt64) v else as.numeric(v) / per[[1L]]
    return(if (names(per) == "ts") posix(s) else as.difftime(s, units = "secs"))
  }
  # read unsigned already; signed INT32 values given here are moved up by 2^32,
  # which is exact (2^64 would round a second time, so INT64 is never moved)
  if (.pq_is_unsigned(ptype, converted, logical)) {
    v <- as.numeric(v)
    neg <- !is.na(v) & v < 0
    if (ptype == .pqInt32) v[neg] <- v[neg] + 2^32
  }
  if (ptype == .pqInt64) {
    .pq_inexact(v, name)
  }
  v
}

# ------------------------------------------------------------------ read

# The file the reader reads, `src`: its bytes (a raw vector), or a file opened once
# (.rmd_vopen()), read a range at a time and never held whole: held whole, a large
# file took its size again on top of what the parse needs.
.pq_size <- function(src) if (is.raw(src)) length(src) else src$size

# The bytes [start, start + n) of `src` (start counted from 0), fewer when it ends sooner.
.pq_at <- function(src, start, n) {
  if (!is.raw(src)) return(.Call(C_rmd_vread, src$handle, start, n))
  n <- min(n, max(0, length(src) - start))
  if (n == 0) raw(0) else src[seq.int(start + 1, length.out = n)]
}

.pq_read_footer <- function(src) {
  size <- .pq_size(src)
  if (size < 12) stop("not a parquet file: ", size, " bytes", call. = FALSE)
  if (!identical(.pq_at(src, 0, 4), charToRaw("PAR1"))) {
    stop("not a parquet file: missing leading PAR1", call. = FALSE)
  }
  tail <- .pq_at(src, size - 8, 8)
  if (!identical(tail[5:8], charToRaw("PAR1"))) {
    stop("not a parquet file: missing trailing PAR1", call. = FALSE)
  }
  n <- .pq_u32(tail[1:4])
  if (n < 2 || n > size - 12) {
    stop("parquet: footer length ", n, " does not fit a ", size, "-byte file",
         call. = FALSE)
  }
  .pq_struct(.pq_reader(.pq_at(src, size - 8 - n, n)))
}

# The largest page this reader will inflate, and the most rows it will build. A
# page header or a footer that claims more is refused before anything is allocated.
# Options are checked where they are read: a cap that is NA or text compared
# as NA ("the file is damaged") or as a string.
.pq_cap <- function(name, default) {
  v <- getOption(name, default)
  if (!(is.numeric(v) && length(v) == 1L && !is.na(v) && v > 0)) {
    stop("parquet: option ", name, " must be one positive number",
         call. = FALSE)
  }
  v
}
.pq_max_page <- function() .pq_cap("rmoriedata.parquet_max_page_bytes", 2^30)
.pq_max_rows <- function() .pq_cap("rmoriedata.parquet_max_rows", 5e7)

# The most bytes a v1 page can hold uncompressed for the values its header
# counts, worked out from the encodings this reader takes (Parquet's
# Encodings.md). A page that says it inflates to more cannot be right and is
# refused before anything is allocated: a 33 KB zstd frame inflates to 1 GiB,
# so the page cap alone let a small file cost gigabytes.
# - PLAIN: BOOLEAN one bit per value; INT32 and FLOAT 4 bytes, INT64 and
#   DOUBLE 8, INT96 12, FIXED_LEN_BYTE_ARRAY its type_length. A BYTE_ARRAY
#   value carries its own length, so a count gives no bound for it (Inf: only
#   the page cap applies).
# - RLE/bit-packed hybrid of n values at bit width w: every run holds at least
#   one value, and its header varint has no more bytes than the run has
#   values. An RLE run of L values is that header and ceiling(w / 8) value
#   bytes; a bit-packed run of g groups is that header and w bytes per 8
#   values. The most per value is therefore 1 + ceiling(w / 8). A writer may
#   pad its last bit-packed run: to a group of 8 values, or, as DuckDB writes
#   the levels of a short page, to a whole block of 32 groups (256 values),
#   which is 32 * w bytes and a header. That allowance does not grow with
#   the page, so it leaves the bound what it is for.
# - definition levels of an optional column: a 4-byte length, then the hybrid
#   at width 1; dictionary indices: a bit-width byte, then the hybrid at a
#   width of at most 32.
.pq_hybrid_most <- function(n, w) n * (1 + ceiling(w / 8)) + 32 * w + 2

# The most bytes a page of text (BYTE_ARRAY, PLAIN or a dictionary) is taken
# to inflate to, from its compressed size: 64 MiB, which no other writer's
# page comes near (their pages are about 1 MiB), or more for a larger page.
# How much more is the codec's own limit where it has one: deflate cannot
# exceed 1032 to 1 and snappy 64 bytes from a 3-byte copy, so a page that
# says more is not one. This package's writer puts a column in one page, and
# 8 million repeated category labels (5.9 MB of gzip, 115 MB of text) were
# refused at 16 times. A codec without such a limit keeps 16 times.
.pq_text_most <- function(csize, codec) {
  ratio <- if (codec == .pqCGzip) 1032 else if (codec == .pqCSnappy) 22 else 16
  max(64 * 2^20, ratio * csize)
}

.pq_plain_most <- function(ptype, n, typelen) {
  if (ptype == .pqByteArray) return(Inf)
  if (ptype == .pqBoolean) return(ceiling(n / 8))
  if (ptype == .pqFlba &&
        !(is.numeric(typelen) && length(typelen) == 1L && typelen >= 1)) {
    stop("FIXED_LEN_BYTE_ARRAY without a positive type_length", call. = FALSE)
  }
  w <- switch(as.character(ptype), "1" = 4, "4" = 4, "2" = 8, "5" = 8,
              "3" = 12, "7" = typelen,
              stop("unsupported physical type ", ptype, call. = FALSE))
  n * w
}

# The most bytes a data page of n values (levels and values) can inflate to.
.pq_data_most <- function(ptype, n, typelen, maxdef, encoding) {
  lv <- if (maxdef > 0L) 4 + .pq_hybrid_most(n, 1) else 0
  if (encoding == .pqEPlain) return(lv + .pq_plain_most(ptype, n, typelen))
  if (encoding == .pqEPlainDict || encoding == .pqERleDict) {
    return(lv + 1 + .pq_hybrid_most(n, 32))
  }
  stop("encoding ", encoding, " not implemented; the store uses ",
       "PLAIN and RLE_DICTIONARY", call. = FALSE)
}

# A column chunk's pages, found from their headers before any is inflated: for
# each page its header, where its stored bytes start, and its sizes. Everything
# a header alone can show to be wrong is refused here, so the whole file's text
# can be weighed (.pq_text_budget()) before any of it is inflated.
.pq_chunk_pages <- function(src, cm, num_rows, stype, fsize, cname) {
  ptype <- as.integer(.pq_f(cm, 1))
  if (!identical(ptype, as.integer(stype))) {
    stop("parquet: column ", cname, " is declared type ", stype,
         " in the schema but its chunk says ", ptype, call. = FALSE)
  }
  codec <- as.integer(.pq_f(cm, 4))
  total_values <- .pq_f(cm, 5)
  clen <- .pq_f(cm, 7)
  data_off <- .pq_f(cm, 9)
  dict_off <- .pq_f(cm, 11)
  if (is.null(total_values) || is.null(clen) || is.null(data_off) ||
      total_values != num_rows) {
    stop("parquet: column ", cname, " chunk holds ", total_values %||% "?",
         " values; its row group has ", num_rows, call. = FALSE)
  }

  start <- if (!is.null(dict_off) && dict_off > 0 &&
    dict_off < data_off) {
    dict_off
  } else {
    data_off
  }
  if (start < 4 || clen < 0 || start + clen > fsize - 8) {
    stop("parquet: column ", cname, " chunk (", clen, " bytes at ", start,
         ") lies outside the ", fsize, "-byte file", call. = FALSE)
  }
  # the chunk is not read whole here: each page's header, and its bytes only when it
  # has a CRC to check
  pos <- 1L
  heads <- list()
  got <- 0
  while (got < total_values && pos <= clen) {
    r <- .pq_page_head(src, start, clen, pos, cname)
    head <- r$head
    pos <- r$pos
    usize <- .pq_f(head, 2)
    csize <- .pq_f(head, 3)
    if (is.null(usize) || is.null(csize) || usize < 0 || usize > .pq_max_page()) {
      stop("parquet: page of ", usize %||% "?", " bytes in column ", cname,
           " (cap ", .pq_max_page(), ")", call. = FALSE)
    }
    .pq_fits(clen, pos, csize, paste("a page of column", cname))
    at <- pos
    pos <- pos + csize
    crc <- .pq_f(head, 4)
    if (!is.null(crc)) {
      have <- .Call(C_rmd_crc32, .pq_at(src, start + at - 1, csize))
      if (have != crc %% 2^32) {
        stop("parquet: page CRC mismatch in column ", cname, call. = FALSE)
      }
    }
    ptype_page <- as.integer(.pq_f(head, 1))
    if (ptype_page == .pqPDataV2) {
      # v2 keeps its levels uncompressed ahead of the values, so
      # decompressing the whole page would fail with a snappy error
      # before this message could fire
      stop("data page v2 not implemented (store is v1)", call. = FALSE)
    }
    # a page the reader does not use (an index page, a type it does not know) is
    # stepped over as it is, never inflated
    if (ptype_page != .pqPDict && ptype_page != .pqPData) next
    if (ptype_page == .pqPData) {
      n <- as.integer(.pq_f(.pq_f(head, 5), 1))
      if (length(n) != 1L || is.na(n) || n < 0 || got + n > total_values) {
        stop("parquet: page of column ", cname, " claims ", n, " values with ",
             total_values - got, " left in the chunk", call. = FALSE)
      }
      got <- got + n
    }
    heads[[length(heads) + 1L]] <- list(head = head, at = at, usize = usize,
                                        csize = csize)
  }
  list(ptype = ptype, codec = codec, total_values = total_values, start = start,
       clen = clen, pages = heads)
}

# The header of the page at `pos` (counted from 1) of the column chunk of `clen` bytes
# at `start`, and the position after it: list(head, pos). It is parsed from the first
# KiB there, which holds the headers most writers write, and from eight times as far
# each time it does not, so a chunk is not read whole for each of its pages. A header
# that parses from none of that is parsed from the whole chunk, as it always was, so
# a damaged one is refused in the same words.
.pq_page_head <- function(src, start, clen, pos, cname) {
  left <- clen - pos + 1
  w <- 1024
  repeat {
    n <- min(w, left)
    r <- .pq_reader(.pq_at(src, start + pos - 1, n))
    head <- tryCatch(.pq_struct(r), error = function(e) NULL)
    if (!is.null(head)) return(list(head = head, pos = pos + r$pos - 1L))
    # eight times as far each time, so a chunk of long headers is read about once
    if (n >= left) break
    w <- w * 8
  }
  r <- .pq_reader(.pq_chunk_blob(src, start, clen, cname), pos)
  list(head = .pq_struct(r), pos = r$pos)
}

.pq_chunk_blob <- function(src, start, clen, cname) {
  blob <- .pq_at(src, start, clen)
  if (length(blob) != clen) {
    stop("parquet: column ", cname, " chunk is truncated", call. = FALSE)
  }
  blob
}

# The most bytes of text the reader inflates from one file: the dictionary and
# data pages of its BYTE_ARRAY columns, summed from their headers before any
# page is inflated. A page of text has no bound from its count, so a file of
# under 1 MB whose 160 zstd pages each said 64 MiB (10.7 GB of one string,
# repeated) was inflated in full, which took about a minute. Pages stored
# uncompressed are not counted: the file holds them as they are. The default,
# 4 GiB, is 2.7 times the text of the 8-million-row cache of
# chiload("complaints", full = TRUE) (1.6 GB) and 29 times the most in any of
# 335 Parquet files of public data (146 MB, in 5.3 million rows); a crafted
# file just under it took 27 to 31 seconds to read. Text per row runs from
# 27 bytes to 74 KB in those files, so the budget is not scaled by the row
# count.
# Fixed-length bytes count toward the same budget: a page of them is bounded by
# its count times the column's length, but the length is the file's word, and a
# 65 KB gzip file of 1024 values of 65536 bytes each inflated to 64 MiB (and its
# old decoding took 1.1 GB). One budget, not a second option: both are the
# bytes a file's own sizes make the reader inflate, and one knob to raise is
# what a user who meets the refusal needs. Real fixed-length columns are small
# by comparison (16 bytes a DECIMAL(38) or UUID: 5e7 rows are 800 MB).
.pq_max_text <- function() .pq_cap("rmoriedata.parquet_max_text_bytes", 2^32)

# Refuse a file whose compressed text and fixed-length bytes say they inflate
# to more than .pq_max_text(). `inflated` and `stored` are byte totals per
# column (doubles: a file's total can pass 2^31).
.pq_text_budget <- function(inflated, stored) {
  most <- .pq_max_text()
  total <- sum(inflated)
  if (total <= most) return(invisible(TRUE))
  k <- which.max(inflated)
  stop("parquet: the compressed pages of text and fixed-length bytes in this ",
       "file say they inflate to ",
       format(total, scientific = FALSE), " bytes in all, ",
       format(inflated[[k]], scientific = FALSE), " of them in column ",
       names(inflated)[k], " from ", format(stored[[k]], scientific = FALSE),
       " stored bytes; such pages are inflated up to ",
       format(most, scientific = FALSE), " bytes a file (option ",
       "rmoriedata.parquet_max_text_bytes)", call. = FALSE)
}

.pq_column_values <- function(src, ch, maxdef, typelen, cname, kind = NULL) {
  ptype <- ch$ptype
  codec <- ch$codec
  total_values <- ch$total_values
  dictionary <- NULL
  out <- NULL
  got <- 0

  for (pg in ch$pages) {
    head <- pg$head
    usize <- pg$usize
    csize <- pg$csize
    # one page at a time, never the chunk whole: .pq_chunk_pages() found it inside it
    .pq_fits(ch$clen, pg$at, csize, paste("a page of column", cname))
    raw_page <- .pq_at(src, ch$start + pg$at - 1, csize)
    ptype_page <- as.integer(.pq_f(head, 1))
    if (ptype_page == .pqPDict) {
      # a chunk has one dictionary page (the format's rule); a second one would
      # be inflated only to replace the first
      if (!is.null(dictionary)) {
        stop("parquet: column ", cname, " has a second dictionary page",
             call. = FALSE)
      }
      n <- as.integer(.pq_f(.pq_f(head, 7), 1))
      if (length(n) != 1L || is.na(n) || n < 0L) {
        stop("parquet: dictionary page of column ", cname,
             " gives no valid value count", call. = FALSE)
      }
      most <- .pq_plain_most(ptype, n, typelen)
    } else {
      dph <- .pq_f(head, 5)
      n <- as.integer(.pq_f(dph, 1))
      encoding <- as.integer(.pq_f(dph, 2))
      most <- .pq_data_most(ptype, n, typelen, maxdef, encoding)
    }
    if (usize > most) {
      stop("parquet: page of column ", cname, " says it inflates to ", usize,
           " bytes; its ", n, " values take at most ", most, call. = FALSE)
    }
    # text gives no bound by its count (a value carries its own length), so a
    # page of it is held to .pq_text_most(): a 33 KB zstd frame said it
    # inflated to 1 GiB, and was inflated before its one value was looked at
    if (is.infinite(most) && usize > .pq_text_most(csize, codec)) {
      stop("parquet: page of column ", cname, " says its ", csize,
           " bytes inflate to ", usize, " bytes of text; a page of text is ",
           "read up to ", .pq_text_most(csize, codec), " (64 MiB, or what ",
           "its codec can inflate its compressed size to)", call. = FALSE)
    }
    if (codec == .pqCSnappy) {
      page <- .pq_snappy_decompress(raw_page)
    } else if (codec == .pqCGzip) {
      page <- .Call(C_rmd_gzip_decompress, raw_page, usize)
    } else if (codec == .pqCZstd) {
      # src/zstd.c: never writes past usize and fails unless the frames give
      # exactly usize bytes
      page <- .Call(C_rmd_zstd_decompress, raw_page, usize)
    } else if (codec == .pqCUncompressed) {
      page <- raw_page
    } else {
      stop("compression codec ", codec, " not implemented; the reader ",
        "takes ZSTD, GZIP, SNAPPY or none",
        call. = FALSE
      )
    }
    if (length(page) != usize) {
      stop("parquet: page of column ", cname, " inflates to ", length(page),
           " bytes; its header says ", usize, call. = FALSE)
    }

    if (ptype_page == .pqPDict) {
      dec <- .pq_decode_plain(page, 1L, ptype, n, typelen, cname, kind)
      if (dec$pos != length(page) + 1L) {
        stop("parquet: dictionary page of column ", cname, " holds ",
             length(page) - dec$pos + 1L, " bytes beyond its ", n, " values",
             call. = FALSE)
      }
      dictionary <- dec$values
      next
    }

    # the definition levels (width 1: 0 missing, 1 present) lie in bytes
    # dpos to dend of the page; dpos 0 is a column without them
    p <- 1L
    dpos <- dend <- 0
    if (maxdef > 0L) {
      if (as.integer(.pq_f(dph, 3)) != .pqERle) {
        stop("BIT_PACKED definition levels not implemented",
          call. = FALSE
        )
      }
      ln <- .pq_u32(.pq_slice(page, p, 4L, "a definition-level length"))
      p <- p + 4L
      .pq_slice(page, p, ln, "definition levels")
      dpos <- p
      dend <- p + ln - 1
      p <- p + ln
    }

    # src/pqplain.c builds the rows at their final length in one pass, with NA
    # (NULL in a list) for a missing value: expanding the levels and the
    # dictionary indices into vectors first, and copying the column at each
    # step, cost four times the result
    if (encoding == .pqEPlainDict || encoding == .pqERleDict) {
      if (is.null(dictionary)) {
        stop("dictionary-encoded page with no dictionary page",
          call. = FALSE
        )
      }
      width <- as.integer(.pq_slice(page, p, 1L, "a dictionary bit width"))
      if (width > 32L) {
        stop("parquet: RLE bit width ", width, " above 32", call. = FALSE)
      }
      col <- .Call(C_rmd_pq_rows, page, dpos, dend, p + 1, width, dictionary,
                   n, cname)
    } else {
      # PLAIN: .pq_data_most() refused every other encoding before inflating
      present <- n
      if (maxdef > 0L) {
        lv <- .pq_read_rle(page, dpos, 1L, n, dend)$values
        # as src/pqplain.c says it for a dictionary-encoded page
        if (any(lv > 1L)) {
          stop("parquet: column ", cname, " has a definition level of ",
               lv[lv > 1L][1L], ", above its maximum of 1", call. = FALSE)
        }
        present <- sum(lv)
      }
      dec <- .pq_decode_plain(page, p, ptype, present, typelen, cname, kind)
      # PLAIN values fill the page exactly: bytes left over (or a shortfall, caught above)
      # mean the declared type is not the type the page was written with
      if (dec$pos != length(page) + 1L) {
        stop("parquet: page of column ", cname, " holds ", length(page) - dec$pos + 1L,
             " bytes beyond its ", present, " values of the declared type", call. = FALSE)
      }
      col <- if (maxdef > 0L) {
        .Call(C_rmd_pq_rows, page, dpos, dend, 0, 0L, dec$values, n, cname)
      } else {
        dec$values
      }
    }

    # one page holds the chunk (this package's writer), or each page goes into
    # a vector made once at the chunk's length: joining a list of pages at the
    # end held every value twice
    if (n == total_values) {
      out <- col
    } else {
      if (is.null(out)) out <- vector(typeof(col), total_values)
      out[got + seq_len(n)] <- col
    }
    got <- got + n
  }

  # exact, never padded or truncated: a count the data does not bear out is an error
  if (got != total_values) {
    stop("parquet: column ", cname, " decoded ", got, " values; its row group has ",
         total_values, call. = FALSE)
  }
  out
}

#' Read a Parquet file
#'
#' Native Parquet reader: no nanoparquet, no arrow. Handles the v1
#' format with PLAIN, RLE and dictionary encodings, GZIP (one or more gzip
#' members a page), Snappy, Zstandard (ZSTD) or no compression. ZSTD pages
#' are read by a decoder in the package (RFC 8878, without dictionaries), so
#' no other package is needed for them;
#' the writer does not write ZSTD. Nested and repeated columns are refused.
#'
#' @param path Path to a `.parquet` file (opened once, only when it is a
#'   regular file, and read a page at a time, never held whole), or the
#'   file's bytes as a raw vector.
#' @param columns Optional character vector of column names to decode;
#'   the rest are skipped entirely. `character(0)` gives a data frame with
#'   the file's rows and no columns. A name the file gives two columns names
#'   the first of them.
#' @details A string column comes back as text marked UTF-8 (ASCII text stays
#'   unmarked, as R keeps it). A Parquet string is UTF-8 by definition, and
#'   [morie_write_parquet()] refuses to write anything else, so a value that
#'   is not valid UTF-8, or that holds a NUL byte, is refused with a
#'   `parquet:` error naming the column: returned, it would fail later in
#'   `nchar()` or `toupper()`.
#'
#'   Three options bound what a file can make the reader do, each checked
#'   from the file's footer and page headers before anything is allocated or
#'   inflated: `rmoriedata.parquet_max_rows` (default 5e7 rows),
#'   `rmoriedata.parquet_max_page_bytes` (default 2^30 bytes a page) and
#'   `rmoriedata.parquet_max_text_bytes` (default 2^32 bytes, 4 GiB). The
#'   last is the most text and fixed-length bytes the compressed pages of one
#'   file may inflate to, summed over the columns read; pages stored
#'   uncompressed are not counted. A file past a bound is refused with an
#'   error naming the option to raise.
#'
#'   A DECIMAL is a double: its scaled value, exact when the unscaled whole
#'   number is below 2^53 and the scale at most 22, otherwise the nearest
#'   double to the whole number, divided by the power of ten, with a warning
#'   that it is rounded. One whose whole number is past the range of a double,
#'   or whose precision and scale the format does not allow for its type, is
#'   refused. A UUID is text (`"8-4-4-4-12"` lower-case hexadecimal), and a
#'   FLOAT16 a double. Other fixed-length bytes (an INTERVAL, or bytes with no
#'   logical type) are refused by name.
#'
#'   An INT32 column is an integer column unless one of its values cannot be
#'   an R integer, which is -2147483648 (-2^31, R's `NA_integer_`): then the
#'   whole column is a double. This is decided once for the whole column,
#'   across all its pages and row groups, from the values in its rows: an
#'   entry of a dictionary that no row uses does not count. Columns of 8 and
#'   16 bits (stored as INT32) are integer columns, and an unsigned 32-bit
#'   column is a double column, whether the file marks the type by its
#'   converted type (`UINT_8`, `INT_16`, `UINT_32`, ...) or by its logical
#'   type (`INT(8, false)`, as arrow writes `uint8`, ...). A value outside
#'   the marked width (an unsigned 8-bit column holding 256, or the word
#'   0xFFFFFFFF, which is -1 as an INT32) is a damaged file and is refused,
#'   naming the column and the value, as other values the format does not
#'   allow are; so is a width the format does not give the stored type (an
#'   INT32 marked 64 bits wide, an INT64 marked 8, 16 or 32). Every 32- and
#'   64-bit word is a value of its width, signed or unsigned. Every other
#'   64-bit column is a double column: exact below 2^53, otherwise the nearest
#'   double, with a warning that it is rounded.
#'
#'   Where a column's logical type and its converted type disagree (`UINT_32`
#'   with a signed `INT(32)`, or with an unsigned `INT(8)`), the logical type
#'   is read, as the format says and arrow does, for every type: the
#'   converted type is read only when the file gives no logical type.
#'
#'   A TIMESTAMP (in milliseconds, microseconds or nanoseconds, or the legacy
#'   INT96) is a `POSIXct` in UTC, and a TIME a `difftime` in seconds. Each
#'   is the double nearest to its exact number of seconds, rounded once and
#'   without a warning. A `POSIXct` is a double: it holds about 16 significant
#'   digits, so within 2^33 seconds (272 years) of 1970 it resolves a
#'   microsecond and around 2025 steps of about 238 nanoseconds; a time in
#'   nanoseconds is the nearest such value, not the nanosecond itself.
#'
#'   Column names are the file's names exactly: an empty name stays `""`, a
#'   name used twice stays twice, and no name is changed to make it
#'   syntactic or unique (text that is valid UTF-8 is marked UTF-8). A file
#'   with no columns reads as a data frame of its rows and no columns.
#' @return A `data.frame`. Every error the reader raises, a missing or
#'   damaged file included, starts with `parquet:`; no base-R warning escapes
#'   it (a value a damaged file makes R warn about is an error instead).
#' @keywords internal
morie_read_parquet <- function(path, columns = NULL) {
  src <- .pq_src(path)
  if (is.character(path)) on.exit(.rmd_vclose(src), add = TRUE)
  where <- if (is.character(path)) path else "the file"
  op <- .pq_opts()
  on.exit(options(op), add = TRUE)
  # A check the reader makes says what is wrong, after the `parquet: ` every reader
  # error starts with; anything else a damaged footer or page trips over (a NULL
  # field, an index past the end) is said to be damage too. A base-R warning on the
  # way (a count past the integer range, say) is damage as well, not a stray warning.
  tryCatch(
    withCallingHandlers(.pq_read(src, columns, where), warning = function(w) {
      m <- conditionMessage(w)
      # the reader's own warning passes; any other is damage
      if (!grepl("holds whole numbers of 2^53", m, fixed = TRUE)) {
        stop("parquet: the file is damaged (", m, ")", call. = FALSE)
      }
    }),
    error = function(e) {
      m <- conditionMessage(e)
      if (startsWith(m, "parquet: ")) stop(e)
      if (grepl(.pq_own_re, m) || .pq_alloc_failed(m)) {
        stop("parquet: ", m, call. = FALSE)
      }
      stop("parquet: the file is damaged (", m, ")", call. = FALSE)
    }
  )
}

# The file to read: the bytes a caller read and checked, a file a caller opened and
# checked (.rmd_vopen()), or a path, opened here once, a regular file only (a FIFO
# blocked the reader), and read a range at a time.
.pq_src <- function(path) {
  if (is.raw(path) || inherits(path, "rmd_vfile")) return(path)
  one <- .rmd_string(path)
  src <- if (one) .rmd_vopen(path, verify = FALSE, fail = FALSE)
  if (!is.list(src)) {
    stop("parquet: ", if (one && file.exists(path)) paste(path, src) else
      paste("no such file:", paste(path, collapse = " ")), call. = FALSE)
  }
  src
}

# Whether an error is R failing to allocate memory, which is not damage. R gives that
# error no class, so it is told by its text, in the session's language: R's own
# translation of the message, from the "R" domain, whatever LANGUAGE is.
.pq_alloc_failed <- function(m) {
  pre <- vapply(c("cannot allocate vector of size %0.1f Gb",
                  "cannot allocate vector of size %0.1f Mb",
                  "cannot allocate vector of size %0.f Kb"),
                function(f) sub(" *%.*$", "", gettext(f, domain = "R")), "")
  any(startsWith(m, c(pre, "cannot allocate")))
}

# The options the reader and the writer must not follow, at their defaults while
# they run (the old values are returned, to be restored): the numbers in their
# messages are written the same whatever options(scipen = , OutDec = , digits = )
# say, and options(check.bounds = TRUE) made the lists they grow warn, which the
# reader turned into "the file is damaged" for every file.
.pq_opts <- function() {
  options(scipen = 0L, OutDec = ".", digits = 7L, check.bounds = FALSE)
}

# The reader's own error messages, passed on with the `parquet: ` prefix.
.pq_own_re <- paste0("^(not a parquet file|snappy: |gzip: |zstd: |crc32: ",
                     "|unknown thrift ",
                     "|FIXED_LEN_BYTE_ARRAY |unsupported physical |data page v2 ",
                     "|compression codec |BIT_PACKED |dictionary-encoded |encoding ",
                     "|nested schema |repeated column |no such column|footer says )")

# A column name from the footer, marked UTF-8 when it is (a Parquet string is UTF-8)
# and otherwise left as its bytes: never changed.
.pq_name <- function(b) {
  s <- rawToChar(b)
  if (validUTF8(s)) Encoding(s) <- "UTF-8"
  s
}

.pq_read <- function(src, columns, where) {
  size <- .pq_size(src)
  meta <- .pq_read_footer(src)
  schema <- .pq_f(meta, 2)
  num_rows <- .pq_f(meta, 3)
  row_groups <- .pq_f(meta, 4)
  if (is.null(row_groups)) row_groups <- list()
  # a footer read from the wrong offset (a damaged length) parses into fields that
  # are missing or of the wrong kind: that is damage, not a table too large
  if (!is.numeric(num_rows) || length(num_rows) != 1L || is.na(num_rows) ||
      num_rows < 0 || num_rows != floor(num_rows)) {
    stop("parquet: the file is damaged: its footer gives no valid row count",
         call. = FALSE)
  }
  if (num_rows > .pq_max_rows()) {
    stop("parquet: footer claims ", num_rows, " rows (cap ",
         .pq_max_rows(), ", option rmoriedata.parquet_max_rows)", call. = FALSE)
  }
  rg_rows <- vapply(row_groups, function(rg) as.numeric(.pq_f(rg, 3) %||% NA), numeric(1))
  if (anyNA(rg_rows) || any(rg_rows < 0) || sum(rg_rows) != num_rows) {
    stop("parquet: row groups hold ", sum(rg_rows), " rows; the footer says ",
         num_rows, call. = FALSE)
  }
  # the root alone is a table of no columns (arrow writes one for a frame of none)
  if (is.null(schema) || !length(schema)) stop("parquet: empty schema", call. = FALSE)

  leaves <- list()
  for (i in seq_along(schema)[-1L]) {
    el <- schema[[i]]
    if (!is.null(.pq_f(el, 5))) {
      stop("nested schema not implemented: group field ",
        rawToChar(.pq_f(el, 4)), " has ", .pq_f(el, 5), " children",
        call. = FALSE
      )
    }
    rep_type <- .pq_f(el, 3, .pqRequired)
    if (!(is.numeric(rep_type) && length(rep_type) == 1L &&
            rep_type %in% c(.pqRequired, .pqOptional, .pqRepeated))) {
      stop("parquet: the file is damaged: column ", rawToChar(.pq_f(el, 4)),
           " has no valid repetition type", call. = FALSE)
    }
    if (rep_type == .pqRepeated) {
      stop("repeated column ", rawToChar(.pq_f(el, 4)), " not ",
        "implemented; decoding it as flat would silently change ",
        "the row count",
        call. = FALSE
      )
    }
    leaves[[length(leaves) + 1L]] <- list(
      name = .pq_name(.pq_f(el, 4)),
      type = as.integer(.pq_f(el, 1)),
      typelen = .pq_f(el, 2),
      converted = .pq_converted(.pq_f(el, 6), .pq_f(el, 10)),
      scale = .pq_f(el, 7),
      precision = .pq_f(el, 8),
      logical = .pq_f(el, 10),
      maxdef = if (rep_type == .pqOptional) 1L else 0L
    )
  }

  wanted <- seq_along(leaves)
  if (!is.null(columns)) {
    nm <- vapply(leaves, function(l) l$name, character(1))
    missing <- setdiff(columns, nm)
    if (length(missing)) {
      stop("no such column(s) in ", where, ": ",
        paste(missing, collapse = ", "),
        call. = FALSE
      )
    }
    wanted <- match(columns, nm)
  }

  # every chunk's page headers first, so that the file's text is weighed
  # before any page of it is inflated
  chs <- vector("list", length(wanted))
  inflated <- stored <- numeric(length(wanted))
  for (w in seq_along(wanted)) {
    i <- wanted[w]
    leaf <- leaves[[i]]
    isdec <- .pq_is_decimal(leaf$converted, leaf$logical)
    # bytes that are not text: read as what their logical type says (a DECIMAL,
    # a UUID, a FLOAT16), otherwise refused by name rather than as damage
    if (leaf$type == .pqFlba) leaf$kind <- .pq_flba_kind(leaf)
    leaf$mark <- .pq_int_mark(leaf$type, leaf$converted, leaf$logical, leaf$name)
    if (.pq_is_unsigned(leaf$type, leaf$converted, leaf$logical)) leaf$kind <- "unsigned"
    # an INT64 time is decoded straight to seconds: as a double count it was rounded
    # before it was divided
    per <- .pq_per(leaf$converted, leaf$logical)
    if (leaf$type == .pqInt64 && !isdec && !is.null(per)) leaf$kind <- per[[1L]]
    if (leaf$type == .pqByteArray && isdec) {
      stop("parquet: column ", sQuote(leaf$name, FALSE), " is a DECIMAL stored as bytes ",
           "of varying length, which this reader does not read; name the ",
           "columns to read in `columns`", call. = FALSE)
    }
    if (isdec) leaf$scale <- .pq_decimal(leaf)[["scale"]]
    leaves[[i]] <- leaf
    chs[[w]] <- list()
    for (rg in row_groups) {
      chunks <- .pq_f(rg, 1)
      if (length(chunks) != length(leaves)) {
        stop("parquet: a row group has ", length(chunks), " column chunks for ",
             length(leaves), " schema columns", call. = FALSE)
      }
      # a row group of no rows holds no pages (arrow writes one for an empty table)
      if (.pq_f(rg, 3) == 0) next
      ch <- .pq_chunk_pages(src, .pq_f(chunks[[i]], 3), .pq_f(rg, 3),
                            leaf$type, size, leaf$name)
      chs[[w]][[length(chs[[w]]) + 1L]] <- ch
      # the two types whose bytes a value takes the file states: text by each
      # value's length, fixed-length bytes by the column's
      if (leaf$type %in% c(.pqByteArray, .pqFlba) &&
            ch$codec != .pqCUncompressed) {
        sizes <- vapply(ch$pages, function(p) as.numeric(c(p$usize, p$csize)),
                        numeric(2))
        inflated[w] <- inflated[w] + sum(sizes[1L, ])
        stored[w] <- stored[w] + sum(sizes[2L, ])
      }
    }
  }
  names(inflated) <- vapply(leaves[wanted], `[[`, character(1), "name")
  .pq_text_budget(inflated, stored)

  out <- list()
  out_names <- character()
  for (w in seq_along(wanted)) {
    leaf <- leaves[[wanted[w]]]
    col <- NULL
    at <- 0
    for (ch in chs[[w]]) {
      v <- .pq_column_values(src, ch, leaf$maxdef, leaf$typelen, leaf$name,
                             leaf$kind)
      # one row group holds the column, or each goes into a vector made once at
      # the file's row count (c() on each row group copied the column so far)
      if (length(v) == num_rows) {
        col <- v
      } else {
        if (is.null(col)) col <- vector(typeof(v), num_rows)
        col[at + seq_along(v)] <- v
      }
      at <- at + length(v)
    }
    if (leaf$type == .pqByteArray || identical(leaf$kind, "uuid")) {
      v <- if (is.null(col)) character() else col
    } else {
      v <- as.numeric(col)
      if (leaf$type == .pqInt32) .pq_int_range(v, leaf$mark, leaf$name)
      if (leaf$type == .pqBoolean) {
        v <- as.logical(v)
      } else if (leaf$type == .pqInt32 && !identical(leaf$kind, "unsigned") &&
                   !any(v == -2^31, na.rm = TRUE)) {
        # decided once for the whole column, from its values: a page or a
        # dictionary decoded as doubles (it held -2^31, used or not) does not decide
        # it. Doubles when a value is -2^31 (no R integer is) or 32-bit unsigned.
        v <- as.integer(v)
      }
      v <- .pq_apply_logical(v, leaf$type, leaf$converted, leaf$scale,
                             leaf$logical, leaf$name)
    }
    out[[length(out) + 1L]] <- v
    out_names <- c(out_names, leaf$name)
  }
  # exact, never padded or recycled: a column of another length is damage
  short <- lengths(out) != num_rows
  if (any(short)) {
    stop("footer says ", num_rows, " rows, decoded ", lengths(out)[short][1L],
      call. = FALSE
    )
  }
  # the file's names as they are: "" stays "" and a name used twice stays twice.
  # as.data.frame() named an unnamed column after a deparse of its values, and
  # check.names or make.unique() would change names the file gives.
  # columns = character(0) asks for no column: a frame with the file's rows and none
  structure(out, names = out_names, class = "data.frame",
            row.names = .set_row_names(as.integer(num_rows)))
}

# ----------------------------------------------------------------- write

# A POSIXct is refused unless each time's nearest microsecond fits the 64-bit count,
# decided in integers (src/pqplain.c): a bound of 2^63 / 1e6 is itself rounded, to
# the time the reader returns for 2^63 - 1 microseconds, which was refused.
.pq_infer <- function(v, name = "a column") {
  # a matrix column holds several values per row: written flat it had more values
  # than rows, which other readers cut short without a word
  if (!is.null(dim(v))) {
    stop("column ", sQuote(name, FALSE), " is a ",
         if (is.data.frame(v)) "data frame" else "matrix or array",
         " column, with more than one value per row, which Parquet as written here ",
         "cannot hold; split it into one column per value first.", call. = FALSE)
  }
  # Date and POSIXct must keep their logical type on the way out.
  # Without this a column read as TIMESTAMP_MICROS was written back as a
  # bare DOUBLE of seconds: readable, but no longer a timestamp to any
  # other engine, and off by a factor of 1e6 from where it started.
  if (inherits(v, "Date")) {
    if (any(abs(floor(unclass(v))) > .Machine$integer.max, na.rm = TRUE)) {
      stop("column ", sQuote(name, FALSE), " has a Date outside the range a Parquet ",
           "DATE holds (2^31 days either side of 1970-01-01).", call. = FALSE)
    }
    return(list(type = .pqInt32, converted = .pqCtDate))
  }
  if (inherits(v, "POSIXct")) {
    if (!all(.Call(C_rmd_pq_usfit, as.numeric(v)), na.rm = TRUE)) {
      stop("column ", sQuote(name, FALSE), " has a time that is infinite or outside the ",
           "range a Parquet TIMESTAMP holds (2^63 microseconds either side of 1970).",
           call. = FALSE)
    }
    return(list(type = .pqInt64, converted = .pqCtTsMicros))
  }
  # written as text these would read back as a different type: refused, not converted
  # an integer64's bits are not a double's value: written as a DOUBLE it read back wrong
  if (is.list(v) || is.complex(v) || is.raw(v) ||
        inherits(v, c("difftime", "integer64"))) {
    stop("column ", sQuote(name, FALSE), " is of type ",
         if (is.object(v)) class(v)[[1L]] else typeof(v),
         ", which Parquet as written here cannot hold; convert it first (for ",
         "example with as.character() or as.numeric()).", call. = FALSE)
  }
  if (is.logical(v)) {
    return(list(type = .pqBoolean, converted = NULL))
  }
  if (is.integer(v)) {
    return(list(type = .pqInt32, converted = NULL))
  }
  if (is.numeric(v)) {
    return(list(type = .pqDouble, converted = NULL))
  }
  list(type = .pqByteArray, converted = .pqCtUtf8)
}

# Down to whole days, as R prints them: as.integer() cut Date(-0.5), which prints as
# 1969-12-31, to day 0 (1970-01-01). A time stays in seconds: .pq_encode_i64() writes
# its nearest whole microsecond, worked out exactly.
# (.pq_infer() has refused values outside the range of either)
.pq_prep_write <- function(v, inf) {
  if (inherits(v, "Date")) {
    return(as.integer(floor(unclass(v))))
  }
  if (inherits(v, "POSIXct")) {
    return(as.numeric(v))
  }
  v
}

# writeBin() has no 64-bit integer, and its two 32-bit halves went through
# as.integer(), which made a low half of 2^31 NA (one second in every 2^29 of
# POSIXct time): src/pqplain.c writes the 64-bit value's own bytes. With `per` 1e6
# the values are times in seconds, written as their nearest whole microsecond.
.pq_encode_i64 <- function(values, per = 1) {
  .Call(C_rmd_pq_i64, as.numeric(values), per)
}

.pq_encode_plain <- function(values, ptype, name = "a column", per = 1) {
  if (length(values) == 0L) {
    return(raw(0))
  }
  if (ptype == .pqBoolean) {
    n <- length(values)
    pad <- (8L - n %% 8L) %% 8L
    bits <- as.raw(c(as.integer(values), rep(0L, pad)))
    return(packBits(as.logical(bits), "raw"))
  }
  if (ptype == .pqInt32) {
    return(writeBin(as.integer(values), raw(),
      size = 4L,
      endian = "little"
    ))
  }
  if (ptype == .pqInt64) {
    return(.pq_encode_i64(values, per))
  }
  if (ptype == .pqDouble) {
    return(writeBin(as.numeric(values), raw(),
      size = 8L,
      endian = "little"
    ))
  }
  if (ptype == .pqByteArray) {
    # src/pqplain.c: each value's 4-byte length and its UTF-8 bytes, in one pass
    return(.Call(C_rmd_pq_bytes,
                 .pq_utf8(values, paste0("column ", sQuote(name, FALSE)))))
  }
  stop("cannot PLAIN-encode physical type ", ptype, call. = FALSE)
}

.pq_encode_levels <- function(levels, width) {
  if (width == 0L) {
    return(raw(0))
  }
  groups <- (length(levels) + 7L) %/% 8L
  padded <- c(as.integer(levels != 0L), rep(0L, groups * 8L -
    length(levels)))
  body <- packBits(as.logical(padded), "raw")
  h <- groups * 2 + 1
  header <- raw(0)
  repeat {
    if (h < 128) {
      header <- c(header, as.raw(h))
      break
    }
    header <- c(header, as.raw(bitwOr(as.integer(h %% 128), 128L)))
    h <- h %/% 128
  }
  payload <- c(header, body)
  c(
    writeBin(length(payload), raw(), size = 4L, endian = "little"),
    payload
  )
}

#' Write a data frame to Parquet
#'
#' Native Parquet writer: single row group, PLAIN encoding, all columns
#' OPTIONAL. Output is read back unchanged by pyarrow and nanoparquet.
#'
#' @param df A `data.frame` with at least one column. Factor columns are
#'   written as character; list, complex, raw, `difftime`, `integer64`,
#'   matrix and data frame columns are refused with an error naming the
#'   column. `NaN` in a numeric column is
#'   kept as `NaN`. Every string must be valid UTF-8 (marked, or unmarked in
#'   UTF-8 bytes), and column names must be unique.
#' @param path Destination path.
#' @param compression `"gzip"` (default; zlib level 9), `"snappy"`, or `NULL`
#'   for uncompressed pages.
#' @details A `Date` column is written as a Parquet DATE (whole days), taken
#'   down to the whole day as R prints it, before 1970 too: a fractional `Date`
#'   of -0.5 (printed 1969-12-31) is written as 1969-12-31. A `POSIXct` column
#'   is written as a Parquet TIMESTAMP of whole microseconds since 1970-01-01
#'   UTC, each time the nearest microsecond to it (ties to even), up to 2^63
#'   microseconds (about 292,000 years) either side of 1970. A time read from a
#'   file of milliseconds or microseconds within 2^33 seconds (272 years) of
#'   1970, where a double still resolves a microsecond, is written back as the
#'   count it was read from, so it reads back identical; finer parts of a
#'   second are rounded to the microsecond. The format stores the instant
#'   but not a time zone, so it reads back as the same instant in UTC: a column in
#'   `America/Chicago` comes back with `tz = "UTC"`. Set the zone again with
#'   `attr(x, "tzone") <- "America/Chicago"`, or keep an ISO 8601 text column
#'   beside it, as `chiload()`'s `date_iso` does.
#' @return `path`, invisibly.
#' @keywords internal
morie_write_parquet <- function(df, path, compression = "gzip") {
  if (!is.null(compression) &&
        !(identical(compression, "gzip") || identical(compression, "snappy"))) {
    stop("compression must be \"gzip\", \"snappy\" or NULL; got ",
      sQuote(compression, FALSE),
      call. = FALSE
    )
  }
  op <- .pq_opts()
  on.exit(options(op), add = TRUE)
  codec <- if (is.null(compression)) {
    .pqCUncompressed
  } else if (compression == "gzip") {
    .pqCGzip
  } else {
    .pqCSnappy
  }

  nrows <- nrow(df)
  names_ <- names(df)
  # a file with no columns has a schema with no leaves, which no reader opens
  if (!length(names_)) {
    stop("a data frame with no columns cannot be written: a Parquet file needs ",
         "at least one column.", call. = FALSE)
  }
  if (anyDuplicated(names_)) {
    stop("duplicate column names: ",
         paste(sQuote(unique(names_[duplicated(names_)]), FALSE), collapse = ", "),
         "; a Parquet reader cannot address them by name.", call. = FALSE)
  }
  # every column's type is settled (or refused) before the file is opened
  infs <- lapply(seq_along(names_), function(k) .pq_infer(df[[k]], names_[k]))
  con <- file(path, "wb")
  on.exit(close(con), add = TRUE)
  writeBin(charToRaw("PAR1"), con)
  offset <- 4

  chunks <- list()
  for (k in seq_along(names_)) {
    v <- df[[k]]
    inf <- infs[[k]]
    # NaN is a value of a DOUBLE column, not a missing one: written as null it read
    # back as NA
    miss <- is.na(v)
    if (inf$type == .pqDouble) miss <- miss & !is.nan(v)
    defs <- as.integer(!miss)
    present <- .pq_prep_write(v[!miss], inf)

    body <- c(
      .pq_encode_levels(defs, 1L),
      .pq_encode_plain(present, inf$type, names_[k],
                       if (identical(inf$converted, .pqCtTsMicros)) 1e6 else 1)
    )
    # page sizes are 32-bit in the page header (and the codecs take no more)
    if (length(body) > .Machine$integer.max) {
      stop("column ", sQuote(names_[k], FALSE), " needs a page of more than the ",
           "2^31 - 1 bytes a Parquet page header can state; write the table in smaller ",
           "pieces.", call. = FALSE)
    }
    payload <- switch(as.character(codec),
                      "1" = .pq_snappy_compress(body),
                      "2" = .Call(C_rmd_gzip_compress, body),
                      body)

    dph <- .pq_writer()
    last <- .pq_wi32(dph, 1L, nrows, 0L)
    last <- .pq_wi32(dph, 2L, .pqEPlain, last)
    last <- .pq_wi32(dph, 3L, .pqERle, last)
    last <- .pq_wi32(dph, 4L, .pqERle, last)
    dph_body <- .pq_wstop(dph)

    ph <- .pq_writer()
    last <- .pq_wi32(ph, 1L, .pqPData, 0L)
    last <- .pq_wi32(ph, 2L, length(body), last)
    last <- .pq_wi32(ph, 3L, length(payload), last)
    # PageHeader.crc: CRC-32 of the page as stored (after compression), so a reader can
    # tell a damaged page from data; written as the signed 32-bit value the spec uses
    crc <- .Call(C_rmd_crc32, payload)
    last <- .pq_wi32(ph, 4L, if (crc >= 2^31) crc - 2^32 else crc, last)
    last <- .pq_wstruct(ph, 5L, dph_body, last)
    ph_body <- .pq_wstop(ph)

    page_off <- offset
    writeBin(ph_body, con)
    writeBin(payload, con)
    total <- length(ph_body) + length(payload)
    offset <- offset + total

    cmd <- .pq_writer()
    last <- .pq_wi32(cmd, 1L, inf$type, 0L)
    last <- .pq_wlisti32(cmd, 2L, c(.pqERle, .pqEPlain), last)
    last <- .pq_wlistbin(cmd, 3L, names_[k], last)
    last <- .pq_wi32(cmd, 4L, codec, last)
    last <- .pq_wi64(cmd, 5L, nrows, last)
    last <- .pq_wi64(cmd, 6L, length(ph_body) + length(body), last)
    last <- .pq_wi64(cmd, 7L, total, last)
    last <- .pq_wi64(cmd, 9L, page_off, last)
    cmd_body <- .pq_wstop(cmd)

    cc <- .pq_writer()
    last <- .pq_wi64(cc, 2L, page_off, 0L)
    last <- .pq_wstruct(cc, 3L, cmd_body, last)
    chunks[[k]] <- list(body = .pq_wstop(cc), inf = inf, total = total)
  }

  root <- .pq_writer()
  last <- .pq_wbytes(root, 4L, "schema", 0L)
  last <- .pq_wi32(root, 5L, length(names_), last)
  schema_structs <- list(.pq_wstop(root))
  for (k in seq_along(names_)) {
    se <- .pq_writer()
    last <- .pq_wi32(se, 1L, chunks[[k]]$inf$type, 0L)
    last <- .pq_wi32(se, 3L, .pqOptional, last)
    last <- .pq_wbytes(se, 4L, names_[k], last)
    if (!is.null(chunks[[k]]$inf$converted)) {
      last <- .pq_wi32(se, 6L, chunks[[k]]$inf$converted, last)
    }
    schema_structs[[k + 1L]] <- .pq_wstop(se)
  }

  rg <- .pq_writer()
  last <- .pq_wliststruct(rg, 1L, lapply(chunks, `[[`, "body"), 0L)
  last <- .pq_wi64(rg, 2L, sum(vapply(
    chunks, `[[`, numeric(1),
    "total"
  )), last)
  last <- .pq_wi64(rg, 3L, nrows, last)
  rg_body <- .pq_wstop(rg)

  fm <- .pq_writer()
  last <- .pq_wi32(fm, 1L, 1L, 0L)
  last <- .pq_wliststruct(fm, 2L, schema_structs, last)
  last <- .pq_wi64(fm, 3L, nrows, last)
  last <- .pq_wliststruct(fm, 4L, list(rg_body), last)
  last <- .pq_wbytes(fm, 6L, "morie native parquet writer", last)
  footer <- .pq_wstop(fm)

  writeBin(footer, con)
  writeBin(writeBin(length(footer), raw(),
    size = 4L,
    endian = "little"
  ), con)
  writeBin(charToRaw("PAR1"), con)
  invisible(path)
}
