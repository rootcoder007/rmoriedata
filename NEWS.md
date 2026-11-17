# rmoriedata 0.4.3

* The copy of a hosted table that an earlier version cached beside the manifest is removed once the table is held under its new name: it was left on disk, never read again. Ctrl-C stops the inflating of a large gzip table between blocks. On Windows a cache that one session is reading cannot be replaced by another until the read ends (Windows does not rename over an open file): the other session returns the data it fetched and the cache keeps its earlier copy.

* `chiload(full = TRUE)` reads its cache, and `morie_read_parquet()` a file by its path, through one open of the file, a page at a time, never holding the file whole: the cache was read whole into memory and each column chunk copied out of it, so an 865 MB cache needed 2.5 GB where it had needed 1.5 GB, and a 1.3 GB cache that loaded under a 4 GB limit no longer did. The digest is taken as the file is read through once, and every range read after it is checked against the digests of the blocks it covers, so the bytes parsed are still the bytes hashed.

* A cached or downloaded copy is deleted only when its bytes are proven bad: they do not match their digest, or the file itself is damaged (no Parquet frame, a damaged gzip member, a record with the wrong number of fields). A cache that could not be read for want of memory was deleted as damaged and fetched again; now running out of memory, a read that fails, a file replaced while it is read, a session option or a parse error leave the copy in place, and the call says what happened. A hosted table the manifest no longer lists and one that cannot be read are kept too, a cached manifest too large for the memory left is no longer fetched again over itself, and a copy is deleted only while it still holds the bytes found bad.

* `hostload()` works under `options(check.bounds = TRUE, warn = 2)`: a valid, digest-checked table was called damaged and its cached copy deleted, because inflating it grew a list.

* The text of a `.gz` file (a hosted table, the data store's gzip files, a sidecar, the manifest) is exactly its gzip members, every one inflated by the package's own routine: NUL bytes after the last member are ignored, as `gzip -d` ignores them, and any other bytes after it are refused, naming them. Bytes after the gzip data were read as text, so zero padding made a valid table "damaged" and deleted it, and text after it became a row.

* `dplaphist()`, `dplapcnt()`, `dpgmean()`, `dpbudget()`, `cellsupp()`, `kanonvrf()` and `ldivvrf()` take plain numbers, or a table of counts, and refuse any other class by name: `dplaphist()` of `bit64::integer64` counts returned the noised counts as doubles still classed `integer64`, which printed as about 4.6e18, silently. Results keep names, dimensions and labels, never the input's class (a table's noised counts are a plain array).
* A number with a label on it (`haven::labelled()`, `Hmisc::label()`, `I()`) is taken as its numbers by those functions: survey data read from SPSS or Stata works as it is.
* A hosted table whose cached copy was damaged and removed is said to have been removed: the message ended by saying the copy was left in place.
* A Parquet file whose page headers are longer than 1 KiB (long text statistics) is read in time proportional to its size; each page had the whole column chunk read again.

* `mdsums()` lists files, and `mdverify()` the files the manifest does not list, in byte order of their paths, the same in every locale: the order followed the collation, so the record differed between `LC_ALL=C` and `en_US.UTF-8`.

* `hostload()` caches each table in a file of its own, the same on a file system that ignores case: `"a__b/c"` and `"a/b__c"` shared one file, so loading one after the other failed its digest and deleted it, and a table listed without a digest would have been returned for the other key. Tables cached by earlier versions are not read, and are fetched again once.

* On Windows, the file reader takes a file's size from the 64-bit `_stat64()`: with the 32-bit size, a file over 2 GiB could not be read.

* `mdload()`, `mddict()`, `siuload()`, `cihitbls()`, `hostload()` and the cache of `chiload(full = TRUE)` read a file once and check and read the same bytes: each hashed the file and then opened it again to read it, so a file replaced between the two (3 of 300 loads under a second process swapping it) was returned, and cached, although its bytes were never checked. The signed manifest, its signature and key, a mirror's file and its `.sha256` are read the same way.

* `mdverify()` reports every listed file whatever is at its path (missing, a directory, a FIFO, a device, a link that loops, a file that cannot be read) as not ok, and drops what the session cached from it: a directory stopped it with an error, and nothing was dropped. A FIFO in the store, the cache or a mirror no longer makes `mdverify()`, `mdsums()` or a loader wait for ever: only regular files are opened.

* `hostload()` takes a key only in the form the manifest writes keys: segments of ASCII letters, digits, `_`, `-` and `.`, none starting with a dot, joined by single slashes. `"db/./t"`, `"db/x/../t"` and `"./db/t"` were requested, and named the table `"db/t"` that the manifest closes; nothing is now asked for, looked up or written for such a key, and a manifest entry with such a key is not served.

* Case is folded in ASCII alone, the same in every locale: in Turkish `cihiget("injury")` matched none of the "Injury" titles, a table marked `"access": "PUBLIC"` was not served, and a message named a "UUİD".

* `morie_read_parquet()` refuses an 8- or 16-bit column holding a value outside its width, naming the column and the value, as a damaged file: an unsigned 8-bit word 0xFFFFFFFF came back as -1, and 0x80000000 in an unsigned 16-bit column made it a double column of -2147483648. A width the stored type does not have (an INT32 marked 64 bits wide, an INT64 marked 32) is refused too.

* `morie_read_parquet()` reads a column's logical type where it and the converted type disagree, for every type, as the format says and arrow does: `UINT_32` with a signed `INT(32)` read the word 0xFFFFFFFF as 4294967295 instead of -1.

* `morie_write_parquet()` writes a `POSIXct` of 9223372036854.775390625 seconds, the time the reader returns for the largest TIMESTAMP_MICROS: it was refused as outside the range, because the bound 2^63 / 1e6 rounds to that time. The bound is now the microsecond count itself, decided in whole numbers.

* `kanonvrf()` and `ldivvrf()` take a column named `""`, and refuse in words a name that is `NA`, that two columns of `data` share, or (as a quasi-identifier) that is `.n` or `.diversity`, the column the result adds: a name `""` stopped them in base R's words, and of two columns of one name the first was checked without a word.

* Results no longer follow `options(scipen = , OutDec = )`: under `scipen = -5` every Parquet read failed as a damaged file (a field id was looked up as "3e+00"); under `scipen = 100` `hostload()` read `1e-05` as text; under `OutDec = ","` `mdask()` warned, and stopped under `warn = 2`. Numbers become text through one helper that ignores those options, the Parquet reader and writer run with `check.bounds` off and their messages written the same under any options, quotes in messages are plain, Socrata's export is read as its bytes whatever `options(encoding = )` says, and a text column of a mirror that holds numbers keeps every digit (`1e+05` was `"1e+05"`).

* `morie_read_parquet()` decides once for a whole INT32 column, from the values in its rows, whether it is an integer column: an unsigned 8- or 16-bit column marked by its logical type, as arrow writes `uint8` and `uint16`, came back as doubles while the same column marked `UINT_8` came back as integers, and a dictionary entry of -2^31 that no row used made the column doubles. Only a value of -2^31 or an unsigned 32-bit type now makes it a double column, however the type is marked.

* `morie_read_parquet()` keeps the file's column names exactly: a column named `""` came back named after a deparse of its values (`"20:21"`), which could repeat another column's name, and a name used twice came back changed by `make.unique()` with a warning. A file with no columns reads as its rows and no columns.

* `morie_read_parquet()` reads a GZIP page made of more than one gzip member, as RFC 1952 allows, inflating each in turn within the page's stated size, and refuses a page with bytes after its last member that are not a member: such a page was refused as damaged, while one member followed by other bytes was accepted.

* `mdpath()` and the other readers of the data store check a file against the signed manifest every time they read it: a file verified once in a session was returned unchecked after it changed, even after `mdverify()` had reported it. `mdverify()` now also drops what the session cached from a file it finds changed, so the next `mdload()` refuses it.

* `morie_read_parquet()` reads a TIMESTAMP or TIME of 64 bits and an INT96 time as the double nearest to its exact number of seconds: a time in nanoseconds was rounded to a double count and rounded again when divided, so about a quarter of present-day times were one unit in the last place off.

* `hostcat()` and `hostload()` serve a table only when the manifest marks it open in a form the package knows: a table marked `"access": ["closed"]`, `"restricted": "true"` or in any other unknown form was listed and would have been requested. A key listed again in an entry that is not served is not served, and the same key listed with different entries is a damaged manifest.

* `morie_write_parquet()` writes a `POSIXct` as whole microseconds, the nearest to each time, where it wrote whole milliseconds; and `chiload(full = TRUE)` returns, on the call that writes its cache, what the cache holds: the first call kept the mirror's sub-millisecond times and every later call returned them cut to the millisecond.

* `morie_read_parquet()` reads every 32-bit word of a whole number, 0x80000000 included: that word read as `NA`, without a word, so an INT64 of 2^31, -2^31 or 2^31 + k * 2^32, one from -2^63 to -2^63 + 2^32 - 1, a UINT_32 of 2^31, and any timestamp, INT64 DECIMAL or INT96 time holding one, plain or from a dictionary, came back `NA`. An INT32 column holding -2^31, which no R integer holds, is now a double column. `morie_write_parquet()` writes such values too: one second in every 2^29 (2012-07-13 11:01:20 UTC among them) was written with a base-R warning and read back as `NA`. A footer or level length of that word is read as its value, not as `NA`.

* `morie_read_parquet()` rounds a UINT_64 of 2^63 or more once, to the nearest double, with the warning other 64-bit whole numbers past 2^53 give: it was rounded as a signed number and again when moved up by 2^64, and could be one unit in the last place off.

* `mdload()`, `mdpath()`, `mddict()` and the other readers of the data store check a file again after `options(rmoriedata.store = )` names another store: a file verified in one store, the catalog, the schema and a table loaded from it were served from the cache for the other, so a changed file there was returned unchecked. The session's record of a hosted manifest that could not be refreshed, and of a table listed without a digest, are kept per cache folder.

* `morie_read_parquet()` reads a DECIMAL kept as fixed-length bytes correctly at every length: a length of 200 holding 0 and 1 read both as `NaN`, without a word. The unscaled whole number is read as two's complement of its stated length and rounded once to the nearest double; it is exact below 2^53, larger ones are rounded with the warning 64-bit whole numbers already give, and one past the range of a double is refused. A scale past 308 no longer gives 0 or `NaN`. A precision and scale the format does not allow (a precision below 1, a scale below 0 or above the precision, or more digits than the type holds, such as precision 5 in 2 bytes or 10 in an INT32) are refused naming the column, the precision and the length. A UUID is now read as text and a FLOAT16 as a number, as arrow, DuckDB and nanoparquet write them; an INTERVAL and bytes of no logical type are still refused by name.

* `morie_read_parquet()` counts the bytes the compressed pages of fixed-length columns say they inflate to toward `options(rmoriedata.parquet_max_text_bytes = )`, as it counts text, before any page is inflated: their length is the file's word, and a 65 KB file of 1024 values of 65,536 bytes each took 1.1 GB of memory to read, a 260 KB file asked for 2 GB and a 1 MB file for 8 GB. The values are read in place from the page, without a raw vector for each, so the 65 KB file now takes 97 MB, and a file past the budget is refused naming the column, the totals and the option. A fixed length of 0, below 0 or past 2^31 - 1, and a UUID or FLOAT16 of the wrong length, are refused by name.

* `morie_read_parquet()` refuses a definition level above the column's maximum on a dictionary-encoded page, as it did on a plain one, with the same message; it was read as a present value. A column whose repetition type the format does not define is refused as damage rather than read as required.

* `morie_read_parquet()` weighs the text a file's compressed pages say they inflate to, from the page headers of every column it reads, before it inflates any of them, and refuses a file past 4 GiB (`options(rmoriedata.parquet_max_text_bytes = )`) with an error that names the totals, the largest column and the option: a 912 KB file of 160 zstd pages, each saying 64 MiB of one repeated string, took about a minute to read and is now refused at once. Pages stored uncompressed are not counted. The 8-million-row cache of `chiload("complaints", full = TRUE)` holds 1.6 GB of text, and the most in any of 335 Parquet files of public data was 146 MB.

* `morie_read_parquet()` builds a column's rows in one pass in compiled code, at their final length, without expanding the dictionary indices and missing-value levels into vectors of their own, and puts the pages and row groups of a column into one vector made once: a 184-byte file holding one run of 5e7 dictionary indices took 1.75 GB of memory for a 400 MB result, and now takes 412 MB.

* `morie_read_parquet()` honours what other writers mark a column as, or refuses the column by name. A DECIMAL (kept as whole numbers, or as fixed-length bytes as arrow's `decimal128` is) is read with its scale: 12.34 came back as 1234. An unsigned column no longer wraps to negative numbers (3000000000 came back as -1294967296). A TIME column is a `difftime`, and a timestamp in nanoseconds or in the legacy 96-bit form is a `POSIXct`, not a bare count. A 64-bit whole number of 2^53 or more is rounded, as before, and now with a warning. Fixed-length bytes that are not a DECIMAL (a UUID, an interval) and a DECIMAL of varying length are refused in the reader's words rather than as a damaged file, and a file whose row group holds no rows (as arrow writes an empty table) is read as no rows.

* `morie_read_parquet()` reads a short page whose missing-value levels are padded to a whole block, as DuckDB writes them: a DuckDB file of 2 to 13 rows with a `NULL` was refused ("says it inflates to 45 bytes; its 3 values take at most 23"). The allowance is a constant, so the bound still refuses a page that claims more than its values can take.

* The Parquet reader holds a page of text to 64 MiB, or 16 times its compressed size if that is more, before it inflates it: a 33 KB file whose one page said it inflated to 1 GiB was inflated in full (a gigabyte of memory) before its single value was read. Pages of numbers were already bounded by their count. For gzip and snappy the larger bound is what the codec can inflate the page to (1032 and 22 times), so a large, repetitive text column written by `morie_write_parquet()`, which puts a column in one page, is read back: 8 million category labels were refused at 16 times, and the cache of `chiload(full = TRUE)` was then deleted and fetched again on every call.

* The Parquet reader decodes run-length data in compiled code: a 29 KB file of fifteen million rows, each a run of its own, took two to three minutes and now takes under two seconds.

* `chiload(full = TRUE, mirror = )` keeps the instants of a mirror file in Socrata's columns whose `date` is a timestamp: midnight became `NA`, and every other time moved by Chicago's offset from UTC.

* `mdsha()` takes one string or a raw vector, as its help says: a number, a logical, a factor or a date was hashed as its text, so `mdsha(1)` equalled `mdsha("1")`.

* `mdload()` with a slug of thousands of bytes says there is no such dataset, not base R's "variable names are limited to 10000 bytes"; and a `MORIE_DATA_URL` that is not an http(s) address (the scheme in either case) is refused by name, where the failure was laid on data.rmorie.com.

* The options the package reads are checked where they are read, and a value of the wrong kind is refused in the package's own words: `options(rmoriedata.store = )` and `options(rmoriedata.cache_dir = )` must be one folder path (a store option of `1`, `NA`, `TRUE` or two strings stopped `mdload()` with base R's "invalid filename argument" or a coercion error), `chiload()`'s `mirror` (by default `options(rmoriedata.mirror = )`) one URL or folder, or `NULL`, and `options(rmoriedata.parquet_max_page_bytes = )` and `options(rmoriedata.parquet_max_rows = )` one positive number (an `NA` cap called every file damaged). `rmoriedata.lockwait` and `rmoriedata.dpart` were already checked.

* `hostload(key, refresh = TRUE)` fetches the manifest again, as `hostcat(refresh = TRUE)` does and the help says, and stops with an error saying the cached manifest is not used when it cannot fetch it: it used a cached manifest more than a day old, with a message. Without `refresh` a day-old cached manifest is still used when a new one cannot be fetched.

* `hostcat()` gives `NA` rows for a manifest entry whose `rows` is not a whole number from 0 to the integer range, without base R's warnings ("NAs introduced by coercion", "... to integer range") for one that is text or too large.

* `hostcat()` and `hostload()` refuse a manifest that is not a JSON object whose `datasets` is an array of objects with "data.rmorie.com sent a manifest that could not be read": a `datasets` that was a string or an array of numbers stopped them with base R's "subscript out of bounds", and a manifest that was an array read as an empty catalogue. An entry whose `meta` is not an object no longer stops `hostcat()`; its name falls back to its source.

* The Parquet reader steps over a page it does not use (an index page) without inflating it, and refuses, before inflating anything, a page that says it inflates to more bytes than its values can take in their type and encoding, and a column chunk with a second dictionary page: a 270 KB file in a `chiload(full = TRUE)` mirror made it inflate eight skipped pages of 1 GiB each, costing 2 GB of memory and 11 seconds. Valid files read as before.

* R sessions that start together on one cache folder no longer fail now and then on Windows with "cannot open the connection": the cached manifest of data.rmorie.com is fetched, replaced and read under an operating-system lock of its own, as each table already was, so no session reads it while another renames a fresh copy over it.

* `mdverify()` and the check each table gets when it is loaded refuse a store file that is a link out of the data store, as rmoriebricklayer's bundle check refuses a link out of its folder: a listed file replaced by a link to an identical copy elsewhere verified.

* The store's manifest signature must be written in lower-case hex, as the signer writes it: a re-cased signature verified, since it decodes to the same bytes (rmoriebricklayer 1.1.1 refuses it too).

* `kanonvrf()` and `ldivvrf()` refuse a data frame with no rows: every class of an empty table meets any threshold vacuously, which says nothing about a release, and the summary read "VIOLATED (min class size=0; 0/0 classes below threshold)".

* `dplapcnt()` and `dplaphist()` accept counts up to 2^52, where a count plus its noise is exact in a double, and the message says so. They accepted counts below 2^53, where the release was rounded (at 2^53 - 1 the offsets +2 and +4 never occurred), and said "must not exceed 2^53" while refusing 2^53 itself.

* `chiload()`, `siuload()`, `mdload()` and `mdpath()` refuse an empty or missing `type`, `as`, `lang` or `format` in their own words (match.arg() said "'arg' must be of length 1"); `mdload()` and `mdpath()` refuse a `slug` that is a function without a warning; and `hostload()`, `cihiget()` and `mdask()` refuse text that is not valid in the session's encoding before it reaches a pattern (base R's "input string 1 is invalid").

* `chiload(full = TRUE)` checks a local-directory mirror's Parquet file against the `.sha256` file beside it, as it already did for a mirror URL, and refuses one that does not match (the mirror is then skipped for Socrata): an edited file was loaded under the original's digest. A local file with no `.sha256` beside it is read as it is, and the help says so.

* `hostload()` returns a table as its file holds it. It read the file with `read.csv()`'s defaults, so codes lost their leading zeros (`046` became the number 46), column names were rewritten (`Offence Description` became `Offence.Description`) and the text `NA` became a missing value. Now the names are kept as written, an empty field is missing in a logical or number column and `""` in a text column, and a column becomes logical, integer or double only when every value in it is written the way R writes such a value; any other column stays text. Text is marked UTF-8 in every locale (it was unmarked in a non-UTF-8 locale), and bytes that are not UTF-8 are marked `"bytes"`. The help page says exactly which values count as numbers.
* A table already cached and verified loads offline once the cached manifest is more than a day old: when the manifest cannot be fetched again, the cached copy is used with a message, and the table is still checked against the digest it lists. `hostload()` failed with a network error.
* `hostload()` checks a cached table under the same lock as a download, so it can no longer delete a copy that another R session has just refreshed. A session waiting for another session's download stops with an error once that download has not grown for `options(rmoriedata.lockwait = )` seconds (600 by default); it waited for ever behind a stalled session.
* A failed download from data.rmorie.com names the function called (`hostcat()` or `hostload()`), the table and the address, without the dependency's own function name in front (`bldl:`).
* A privacy budget copied within one R session (written with `saveRDS()` and read back, passed through `serialize()`, or rebuilt from its fields) is refused like a budget from another session: the copy and the original could each spend the whole budget. `dpbudget()`'s help says what is and is not prevented.
* The Parquet reader refuses a string that is not valid UTF-8, or that holds a NUL byte, with a `parquet:` error naming the column: it marked such bytes as UTF-8, and `nchar()` or `toupper()` failed later. `columns = character(0)` gives the file's rows with no columns (it failed with "footer says 3 rows, decoded 0"), and a damaged footer length is reported as damage, not as a file over the row cap.
* The native Parquet reader is about 90 times faster and the writer about 8 times (on a 400,000-row table of 13 columns, 3,500 and 4,400 rows a second became 326,000 and 35,000): string values are read and written in compiled code, and the other per-value loops work on whole vectors. The bytes written and the values read are unchanged.
* `chiload(full = TRUE)` reads text as decimal numbers only, so `"0x1A"` is no longer 26 and `"Inf"` or `"1e400"` no longer an infinite coordinate. A value in Socrata's export that does not fit its column becomes `NA` with one warning per column, instead of refusing the whole download; a mirror's or the cache's file in the sample's columns must still fit exactly, and the error names that file (it blamed Socrata's export).
* `mdask()` no longer probes or asks an Ollama server the user did not choose: with the automatic route, a local server at `localhost:11434` is left out unless `route = "ollama"`, an `OLLAMA_*` variable or a saved Ollama setting names it.
* `cihiget()` checks `timeout` under its own name and takes 1 to 86400 seconds (0.5 was refused as "`tmout` must be a positive number"), and a failed download names `cihiget()`, not the dependency's `blfetch()`; strings marked `"bytes"` passed to `kanonvrf()`, `ldivvrf()`, `mdload()`, `mdpath()`, `mddict()`, `cihiget()`, `hostload()` and `mdask()` are refused in words, where base R stopped with "translating strings with "bytes" encoding is not allowed".
* Decimal text is read as the nearest double, the same on every platform, by `mdload()`, `hostload()` and `chiload(full = TRUE)`: R's own conversion (behind `read.csv()` and `as.numeric()`) is not correctly rounded, and read some values one bit apart on x86-64 and ARM64 (`1.239042694` was 1.2390426940000001 on one and 1.2390426939999999 on the other). The Parquet copies of five bundled tables (`tps_assault_sample`, `samples_tps_assault_sample`, `vic_criminal_incidents`, `vic_lga_criminal_incidents`, `vic_recorded_offences`) held such values and are written again from their CSV copies, so the two copies of every table give the same data frame, as the help says.
* `kanonvrf()` and `ldivvrf()` compare every numeric column exactly, whatever its class: `difftime`, `I()`, `Date`, `POSIXct`, `POSIXlt` and complex columns were compared to 15 significant digits, so two distinct values (such as two times a microsecond apart) formed one class and a violated k could be reported as satisfied. A fractional `Date` is now compared by its stored value, not its printed day. Columns that cannot be compared exactly (`bit64::integer64`, list and matrix columns) are refused with an error naming them.
* `kanonvrf()` and `ldivvrf()` build classes column by column, so strings holding control characters can no longer join two different rows into one class, and a factor level that is `NA` is missing while the string `"NA"` is a value (they were one class). As a sensitive value, an `NA` factor level is withheld and no longer counts towards diversity.
* A privacy budget of `delta = 0` refuses every release with `delta > 0`: a release at `delta = 5e-13` was accepted. The check of the totals allows only floating-point rounding, relative to the budget, and never a release more than twice what remains: a budget of `epsilon = 1e-13` paid for a release at `1e-12`.
* A privacy budget saved and read back in another R session is refused even when that session has the same process ID, as every `Rscript` started as a container's entrypoint does: each budget carries a random token drawn from the operating system when the package loads. Budgets saved by earlier versions are refused too. `dpbudget()`'s help says that a release interrupted after it is charged stays charged.
* `chiload(full = TRUE)` reads a text time with an offset or `Z` (from a mirror) as that instant: `2024-06-01T10:00:00Z` was read as 10:00 in Chicago, five hours off. A value that does not fit its column's type is refused with an error naming the column, from a mirror and from Socrata's export alike: text `"1.5"` became the integer 1, `2` became `TRUE`, and junk in Socrata's numeric columns became `NA`.
* The Zstandard decoder refuses a block whose sequence count of 0 is followed by more bytes (libzstd does too), and reports one to three stray bytes after the last frame as trailing data rather than as a truncated frame. The zstd, gzip and Snappy decoders refuse, before allocating, a size that this build of R cannot hold.
* A hosted table downloaded in parts checks that every part is there and readable before it joins any: a missing or unreadable part stopped with a base-R warning after the earlier parts had been deleted; now all parts are kept and the next run downloads only what is missing. Two sessions joining the same table at once each write a file of their own instead of sharing one.
* R sessions downloading the same hosted table at once take turns on an operating-system lock that the system releases when its holder exits or is killed, so it is never left stale: one session downloads, checks the table against the manifest's SHA-256 and only then moves it into place in one step, and the others wait and use it. The sessions shared one `.parts` folder and could delete or overwrite each other's parts, and an unchecked table sat under its final name until its checksum was read. A download that is cut short or killed still resumes from the parts it finished. The manifest is written under a name of its own and renamed, so sessions fetching it at once no longer write into one file.
* The Parquet writer refuses matrix, data frame and `integer64` columns, naming them: a matrix column was written with more values than rows, which other readers cut short. Dates and times are written down to the whole day and millisecond as R prints them, so a `Date` of -0.5 (printed 1969-12-31) no longer reads back as 1970-01-01, and dates or times outside what Parquet holds, or infinite, are refused.
* The Parquet reader reads ZSTD-compressed pages, such as those of files written with `compression = "zstd"` by nanoparquet, arrow or DuckDB, with no other package: the Zstandard decoder is in the package, written from RFC 8878 (no dictionaries), and checks every page against its stated size, and against the frame's checksum when it has one. Such a file stopped with "compression codec 6 not implemented". The writer still writes GZIP, Snappy or no compression.
* A hosted table downloaded in parts no longer comes out damaged when the disk fills up while the parts are joined: the failed write is an error that names the folder and `options(rmoriedata.cache_dir = )`, where it was a short file that then failed its checksum. Each part is deleted once it is joined, so the download needs the table's size plus one part on disk, not twice the table's size.
* The title, description and citation put the package's disclosure-control tools first (differential privacy, k-anonymity and l-diversity checks, cell suppression); the datasets follow. Nothing in the functions changes.
* `chiload(full = TRUE)` returns the bundled sample's columns, in its order and with its types (16 columns for complaints and 8 for arrests, with `date_iso` and a `POSIXct` `date`), derived from Socrata's export the way the samples were: it returned Socrata's raw 22 or 24 columns. Socrata's export is read as text first, so an IUCR code keeps its leading zero.
* `chiload(mirror = )` with a URL downloads `<type>_full.parquet` from the mirror over the package's checked https transport, and checks it against `<type>_full.parquet.sha256` when the mirror has one; a mirror that fails or does not match falls back to Socrata. A URL was taken for a missing local file, so the mirror was never used.
* `chiload()` checks its arguments in words: `limit` must be a whole number from 1 to 2147483647 (`Inf` and `1e10` failed with a coercion error), `fraction` a number above 0 and at most 1, and `full` and `refresh` `TRUE` or `FALSE` (`full = "yes"` or `NA` silently returned the sample).
* `cellsupp()` checks which hidden cells the totals determine with one factorisation for all of them, not one per cell: a 50x50 table took 152 seconds and a 60x60 table did not finish in 17 minutes; both now take well under a second, with the same cells suppressed. Negative counts are refused, and the help says that zero cells are published as they are.
* `mdload(slug, refresh = TRUE)` checks the file against the signed manifest again: a bundled file changed after its first load in a session was still returned.
* A cached `hosted/manifest.json` that does not parse is fetched again, once, with a message; it blocked `hostcat()`, `hostload()` and `hostload(refresh = TRUE)` until it was a day old.
* `hostload()` takes a large table whole when the server answers a byte-range request with the whole file, instead of failing on every run, and a failed run leaves no empty `.parts` directory.
* A cache directory that cannot be written (read-only, or a file in its place) is an error naming that directory; it was reported as a failure of data.rmorie.com.
* `dplaphist()` keeps the names and dimensions of its counts, so a `table()`'s labels stay on the release.
* The Parquet reader reports any damaged file with a `parquet:` message: about 4% of corrupt files stopped with a base-R message such as "subscript out of bounds", and a footer of 5000 nested lists overflowed the stack. Its help, and `chiload()`'s, say that a `POSIXct` column reads back in UTC (the same instant): Parquet keeps no time zone.
* Extreme arguments are refused in words: `k` or `l` of `Inf` or above the integer range in `kanonvrf()` and `ldivvrf()`, an `epsilon` above 2^20 in the counting mechanisms (both stopped with "missing value where TRUE/FALSE needed"), a `slug` that is not one name in `mddict()`. `mdsha()` takes one string (it hashed only the first of several) and hashes it as UTF-8 whatever encoding it is marked with.
* `dplapcnt()`, `dplaphist()` and `dpgmean()` draw fresh random bytes in a forked worker (`parallel::mclapply()`): the workers inherited the parent's buffer of random bytes and released identical noise, so the difference of two releases was the exact true difference.
* `chiclr()` deletes only what `chiload()` wrote (the `<type>_full.parquet` files, their checksum files and unfinished writes): it removed everything in the cache directory, subfolders and the hosted-table cache included.
* `cellsupp()` refuses a table of three or more dimensions (it was flattened to one column and suppressed against the wrong margins). `ldivvrf()` counts a class's values in one pass: 200,000 classes took minutes.
* A refused download reads the status the server answered: a table whose name holds 401 or 403 no longer turns a 404 into "need no sign-in", and a 410 names ICPSR only for an ICPSR table.
* Works with rmoriebricklayer 1.1.0 and later.
* `hostlogin()` is gone, and no key is read or sent: every table at data.rmorie.com is open, so the sign-in asked for a name, a reason and an email or GitHub account for nothing. `hostcat()` and `hostload()` work as before. A key that an earlier version stored stays in its file, unread. The manifest and services fields are read by exact name.
* `hostload()` checks every table against the manifest's SHA-256 again, whatever the field is called (`sha256_gz`, `sha256` or `sha`, as rmoriebricklayer reads it): 0.4.2 read `sha256` only, so 631 tables listed with `sha256_gz` were used unchecked and a modified cached copy loaded. A digest field that is not a SHA-256 is an error, and a table listed without any digest loads with a warning, once per session.
* Tables whose source terms do not allow redistribution (the ICPSR studies, the NCVS 38604 extract among them, and any table the manifest marks restricted) are left out of `hostcat()`, with a message counting them, and `hostload()` refuses them before any request. The A2AJ case law is an ordinary open table.
* The messages for a refused download no longer suggest signing in: the tables need no key.
* `dplapcnt()`, `dplaphist()`, `dpgmean()` and `dpbudget()` refuse an infinite `epsilon` in words; `dplapcnt(5, Inf)` stopped with "missing value where TRUE/FALSE needed".
* The signing test writes its XMSS used-index record to a temporary file, not to `~/.config/R/rmoriebricklayer`.
* The vignette's reference to the integrity checks is no longer empty.
* A privacy budget from `dpbudget()` cannot be spent from a forked worker or another R process: `dplapcnt()`, `dplaphist()` and `dpgmean()` refuse it there with an error. Four workers under `parallel::mclapply()` each spent 0.9 from one budget of 1 and the parent recorded nothing; give each worker its own budget and add up the epsilons.
* `kanonvrf()` and `ldivvrf()` compare numeric quasi-identifiers exactly: values that agree to 15 significant digits, such as `0.1 + 0.2` and `0.3`, were one class, so a class of one could be reported as a class of five. `-0` and `0` are one class, and `NaN` is missing with `NA`.
* `cellsupp()` treats an `NA` cell as unpublished in its audit, as its help says, and gives it complements like any hidden cell: it was treated as known, so a hidden cell recoverable through it was reported as protected. Infinite and fractional counts are refused, and a function or an environment gets the package's "must be a numeric matrix or table" error.
* `chiclr()` deletes only `arrests_full.parquet`, `complaints_full.parquet`, unfinished `write-*.parquet` files and their `.sha256` files: it deleted any file ending in `_full.parquet` and left the `.sha256` of an unfinished write.
* `chiload(full = TRUE, mirror = )` gives a mirror's table the bundled sample's types when its columns have the sample's names (a `date` stored as text came back as text), and refuses a column that cannot be read as the sample's type.
* `hostload()` and `mdload()` check `refresh` in words (`NA`, `"yes"`, `NULL` and `c(TRUE, FALSE)` gave base-R errors or acted as `TRUE`), and a table size in the hosted manifest that is not a whole number from 1 to 2^40 bytes is refused in words: an absurd size stopped in `seq()`.
* `mdverify()` and `mdsums()` list hidden files in the store too, and the help of `mdverify()` says what it covers: every file of the data store, not the package code or the lazy-loaded `complaint_sample` and `arrest_sample`. `mdsums()`, `siuload()` and `cihitbls()` read the store named by `options(rmoriedata.store = )`, the one they verify; they used to read the installed copy.
* `dplapcnt()` and `dplaphist()` refuse a count of 2^53 itself: 2^53 + 1 rounds back to 2^53, so the release could equal the truth.
* The Parquet writer keeps `NaN` (it read back as `NA`), refuses a data frame with no columns, which its reader could not open, and refuses list, complex, raw and `difftime` columns in words, naming the column: they were written as text. Every error of the reader starts with `parquet:`, and a damaged file no longer lets a base-R warning such as "NAs introduced by coercion to integer range" escape before the error.
* The help pages, README, vignette and website describe the package by its own purpose, disclosure control first and the datasets second, and no longer as a companion of another package; the README's function list and the reference index follow that order. The README names the real source of each table's attribution, the right path for reading the sample with `pyreadr` and the right `hostcat()` columns, and drops an out-of-date note on package size.

# rmoriedata 0.4.2

* Works with rmoriebricklayer 1.1.0 and 1.1.1 (where `yoy()` is renamed `yoychg()`): rmoriedata no longer refers to `yoy()`.
* `hostload()` downloads a table larger than twice the part size (option `rmoriedata.dpart`, 90 MB by default) in byte-range parts, each kept once whole, so a broken connection costs at most one part and running it again resumes; the joined file is checked against the manifest SHA-256.
* `hostcat()` and `hostload()` need no sign-in; a key stored earlier is still sent. ICPSR studies are no longer served by data.rmorie.com (ICPSR's terms do not allow redistribution); asking for one says where to get it.
* `hostlogin()`'s help names the arguments `rmoriebricklayer::dlogin()` takes (`affil`, `purp`, `restr`; it listed `affiliation`, `purpose`, `restricted`). A table refused with 403 is reported as a key asked for or refused: no table sits behind accepted terms any more.

# rmoriedata 0.4.1

* The Snappy and gzip page decoders check the size a file claims before allocating it. A
  damaged or hostile header asking for more than the compressed bytes can hold (a Snappy
  stream expands at most 64 bytes per 3, deflate about 1032 to 1, and both sizes are 32-bit)
  is now an R error up front. Before, R was asked for the full amount first: an ordinary build
  then failed with an error, but the address-sanitizer build CRAN runs (gcc-ASAN) aborted the
  test run.
* A function missing from the installed rmoriebricklayer is now named in the message
  that asks for an update, and the test of the old-name fallback no longer depends on
  which rmoriebricklayer is installed (a development build between the 1.0.0 rename and
  the return of the old names failed it).
* `R CMD check` on R before 4.6 no longer notes rmoriebricklayer as an unused import.

# rmoriedata 0.4.0

* Short names, without underscores, for every exported function and argument, matching
  rmoriebricklayer 1.0.0: `morie_data_load()` is `mdload()`, `morie_dp_laplace_count()` is
  `dplapcnt()`, `load_chicago_data()` is `chiload()`, `quasi_identifiers` is `qids`, and so on.
  Each help page gives the full form of its short name. The old names are not kept.
* Works with rmoriebricklayer 0.5.1 or later and calls its 1.0.0 names when they are there.
  Signing in (`hostlogin()`), `mdask()` and the downloads that carry the data key need
  rmoriebricklayer 1.0.0; with an older one they say so, and attaching rmoriedata prints a
  one-line note on how to update.
* The citation gives the CRAN DOI and the r-universe page, and the author's given names in
  full ("Ruhela VS").

# rmoriedata 0.3.7

* Needs rmoriebricklayer 0.5.14: a new data key from `morie_data_hosted_login()` needs the data
  access terms accepted first, then your name, organisation and why you need the data (and, for the
  restricted tables, a supervisor, department chair, director or coordinator). Pass them as
  arguments (`accept_terms = TRUE`, `name = `, `purpose = `, ...) or answer at the console.

# rmoriedata 0.3.6

* Needs rmoriebricklayer 0.5.13, whose download bar now redraws in the RStudio, Positron and
  R.app consoles and stays a plain line in knitr and Jupyter.
* Needs rmoriebricklayer 0.5.12, whose language-model layer `ask()` is built on (0.5.9 was
  accepted, so a build against an older one ran `ask()` on the retired hosted tier).
* `ask()` uses a language model you bring (a provider's key, Ollama, or your own server) through
  rmoriebricklayer, and the model is given rmoriedata's and rmoriebricklayer's help with tools to
  read it. Its `backend` argument is now `route` (`"auto"`, `"own"`, `"ollama"` or a provider id
  such as `"anthropic"`); the hosted MORIE tier and the `rmorie` command-line fallback are gone.
* `morie_data_hosted_load()` uses a downloaded table only when it matches the SHA-256 the
  manifest lists (fetching the manifest again once before calling a file bad); a mismatch
  deletes the copy and says so. A restricted table (the ICPSR studies, NCVS 38604, the a2aj
  case law) refused with 403 says to accept the terms at https://data.rmorie.com/terms.
* `morie_data_llm_config()` shows and saves the language-model settings (route, and the
  address, key and model of each route), shared with rmoriebricklayer, rmorie and morie.

# rmoriedata 0.3.5

* A hex logo (`man/figures/logo.png`, source `data-raw/hex_logo.svg`), on the README and the
  package website, with its favicons; the website indexes `morie_dp_budget()` and `morie_dp_spent()`.
* **A garbled download is refused, not padded.** The full Chicago export and the tables from
  data.rmorie.com are read with `fill = FALSE`: a row with a field missing or one too many was
  padded into the result (and, for Chicago, written to the cross-session cache); it is now an
  error, and a damaged hosted table's local copy is removed so the next call fetches it again.
  The Chicago tests also pin the 1% row-count tolerance at its edge (495 of 500 accepted, 494
  refused) and the request size (the service's count, at least 5,000,000 rows).
* **Privacy verifiers (review of 0.3.5).** `morie_k_anonymity_verify()` treats a missing
  quasi-identifier as a level of its own: `stats::aggregate()` had dropped every row with an `NA`
  key, so a class of one person could pass `k = 3`; class sizes now always sum to `nrow(data)`.
  `morie_l_diversity_verify()` counts only known sensitive values (`"HIV", NA, NA` is diversity 1,
  not 2). `morie_cell_suppress()` adds complementary suppressions to a fixed point and then audits
  the result exactly: a hidden cell the row and column totals determine (its indicator in the row
  space of the margin constraints) gets another complement, and the result carries
  `recoverable_mask`, `n_recoverable` and a `protected` verdict to test before publishing. The
  0.3.5 passes left a lone hidden cell in a row or column, from which the primary value followed
  by two subtractions; zero cells are no longer used as complements. Checked against brute-force
  enumeration of every margin-consistent fill on 464 random tables: no disagreement.
* **Differential privacy.** Noise comes from the operating system's CSPRNG
  (`rmoriebricklayer::random_bytes()`), not R's seeded generator, so `set.seed()` no longer
  reproduces a release. Counts and histograms use the exact discrete Laplace sampler of Canonne,
  Kamath and Steinke (2020) in integer arithmetic (whole-number releases; no floating-point
  artefact of the kind Mironov (2012) showed in the textbook Laplace sampler). The mean uses the
  analytic Gaussian mechanism of Balle and Wang (2018), valid for every epsilon; the classical
  bound, valid only for epsilon <= 1, is gone. All three mechanisms use one neighbouring relation
  (add or remove one record): the mean is a noised sum over a noised count. New
  `morie_dp_budget()` / `morie_dp_spent()` charge releases against a budget (basic composition)
  and refuse one that would exceed it. Examples no longer call `set.seed()`.
* **Parquet reader.** Every byte access is bounds-checked (an out-of-range raw index had silently
  read zeros); varints, lists, maps and nesting are capped by the bytes that remain, so the 21-byte
  file that looped forever is refused at once; the decoded row count must equal the row group's
  and the footer's exactly (no padding with `NA`, no truncation); a column chunk's type must match
  the schema's; PLAIN values must fill their page exactly; dictionary indices are range-checked;
  page sizes and footer row counts are capped (`options(rmoriedata.parquet_max_page_bytes,
  rmoriedata.parquet_max_rows)`); `PageHeader.crc` is verified when present and the writer now
  writes it. `tests/testthat/test-parquet-hostile.R` fuzzes all three codecs.
* **Downloads.** `.rmd_dl()`, which carries the MORIE key as a bearer header, goes through
  `rmoriebricklayer::bricklayer_download()` (https to public hosts only, no `file://`, size cap)
  instead of base `url()`; requires rmoriebricklayer 0.5.9. `load_cihi_data_tables()` checks the
  catalogue against the signed manifest before reading it. `morie_data_verify()` reports files
  added to the store (`listed = FALSE`), and `morie_data_checksums()` compares each digest with the
  manifest (`in_manifest`).
* **Workflows.** The SIU manifest refresh runs only on demand and uploads an artifact instead of
  committing: the manifest is covered by the XMSS-signed `_checksums.csv`, whose key never leaves
  the maintainer's machine, so it is re-signed locally with `data-raw/sign_store.R`. A new
  ASAN/UBSAN job builds the C and runs the suite, including `test-codec-hostile.R`.
* **Packaging.** `utils` is declared in `Imports`; the stale `RoxygenNote` is dropped
  (`Config/roxygen2/version` is the roxygen 8 field); `NOTICE` moves to `inst/NOTICE` so it
  installs, and its data attribution now names the publishers instead of per-file headers that did
  not exist. The licence text itself stays out of the tarball, as CRAN asks for a standard licence.
  DESCRIPTION describes the disclosure-control helpers by what they do.

* The curated-data service address comes from the signed services document at
  rmorie.com (through `rmoriebricklayer::bricklayer_services()` when the installed
  bricklayer has it; an older bricklayer keeps the default address), so the endpoint can
  move or be paused without a release. Keys are personal and issued on request at
  `www.rmorie.com/access/`; every hint says so, and `morie_data_hosted_login(token = )`
  stores one (the GitHub and emailed-code sign-ins keep working).
* `ask()` follows `rmoriebricklayer::bricklayer_llm_ask()`'s route order: an endpoint of
  your own, a local Ollama server, then the hosted MORIE tier as a last resort;
  `backend = "hosted"` insists on the hosted tier. The setup hint when nothing answers
  names all three.

# rmoriedata 0.3.4

* The Parquet store is compressed: the writer's Snappy stream was literal-only (valid, but it
  compressed nothing), so every table's Parquet copy was as large as its raw pages. Pages are now
  written with GZIP (zlib, level 9) by default, and Snappy, still available, has a real
  match-finder; both codecs and the reader are C (`src/gzip.c`, `src/snappy.c`). The Parquet copies
  shrink from 16.1 MB to 3.3 MB (the SIU corpus from 10.0 MB to 2.1 MB) and the installed package
  from about 27 MB to 14.5 MB; pandas/pyarrow read them as before.
* SIU corpus: `narrative_summary` holds each report's own account of the incident on 4,605 of 4,613
  reports (it was empty but for three values that described the SIU's investigation). The text is
  the opening of the report's "Incident Narrative" / "Description de l'incident" section, or of the
  "Notification of the SIU" / "Avis à l'UES" section in reports that have no narrative section (2005-2016
  and re-opened files), about 900 characters cut at a sentence end. It was read from the SIU's pages,
  re-crawled on 2026-10-05 at one request every 3 seconds; `data-raw/add_siu_narratives.R` rebuilds it.
* SIU corpus, round 8 (4,613 rows; every change is a row of `data-raw/siu_round8_review.csv`, with
  the reason read from the page, or a rule of `data-raw/siu_round8_rules.R`):
  - six French reports of 2005-2011 filed under /en/ are labelled French and carry the service their
    page names; three of them held "Guelph Police Service", which the pages never name (05-TCD-004
    is Toronto, 10-PFD-078 the OPP, 10-OOD-009 Ottawa);
  - a corrigendum is applied to the report it corrects, in a new column `corrigenda`, not counted as
    a report (drids 385, 620/621 and 5065 correct 328, 521/522 and 4561); six second copies of one
    report (identical page text) are removed;
  - case numbers the page body gives: drids 925/926 are 19-TCI-073a, and drid 2209 is the French
    report of 22-PCI-191 (the OPP in Quinte West), not of 21-OCI-191 as the SIU page's header says;
  - a French report carries its English report's reviewed case facts (dates, team, counts, the
    affected person's age and sex, the charges, the director's view): they were empty on about
    2,240 of 2,304 French rows; the French text fields stay French;
  - `charges_recommended` is `"FALSE"`, `"TRUE"` or empty (it had 39 spellings), and logical in the
    typed table (`morie_data_load("siu_directors_reports")`, CSV and Parquet), as `panel_reviewed` is;
    `sex_gender_affected` is `male` or `female`; one name for Kawartha Lakes and for Cornwall (the
    Cornwall Community Police Service is now the Cornwall Police Service);
  - `narrative_summary` held the SIU's mandate paragraph or the page title, not a narrative, and is
    empty except on the three rows that held report text; `supplemental_materials` lists the
    legislation and case law a report cites (it held the page's share and privacy links).
* `ask()` sends the bundled catalogue (slug, kind, rows) with the question, so the model names tables
  (it was told only to "prefer the bundled catalog", which it could not see). Through the rmorie binary it
  calls `rmorie agent [--model NAME] QUESTION`, the agent's own options: it passed `--backend`, which
  the agent refuses, and `-m` for the model; `backend` is `"auto"`, `"hosted"` or `"cli"`. The examples that need a stored key or the binary are `\dontrun`; the one that runs
  switches the hosted tier off (`MORIE_HOSTED_BASE_URL = "off"`), so it reaches no network
  whatever key the machine holds.
* `morie_dp_laplace_count()` and `morie_dp_laplace_histogram()` refuse `Inf` in words (they warned
  about integer coercion, then failed in R's internals) and refuse counts above 2^53: a double that
  large has no room for Laplace noise of scale 1/epsilon, so `morie_dp_laplace_count(1e300, 1)`
  returned exactly 1e300, a "private" release equal to the true count. A whole count beyond R's
  integer range but below 2^53 is still a count. `morie_core_mean()` refuses text instead of
  averaging `NA`.
* Help: `?rmoriedata` describes the package's functions (it said there were none); `?load_siu_reports`
  lost "% of them" to an Rd escape; "more than 160" databases at data.rmorie.com; a garbled sentence
  in `?load_chicago_data`; the README's Chicago example is bounded (`limit = 200`).
* The SIU director's-report corpus: `police_service` is the service of the subject officials
  on every row (it was the notifying force on many French rows, and on 24 English rows a
  custody, requesting or neighbouring service -- each corrected after reading the report);
  one spelling per service; 59 English reports published since the last build, reviewed by
  the same model panel, and their 60 French reports added; 54 French reports filed under
  /en/ relabelled; 29 rows that held no director's report removed.

* `ask()` answers through the hosted MORIE tier with the key
  `morie_data_hosted_login()` stores (ollama.com cloud models and additional AI
  models such as `kimi-k2.6:cf` or `gpt-oss-120b:cf`), and only falls back to the
  optional `rmorie` command-line agent when no key is stored.

* Hosted tables download with a live progress bar (percent, size, rate) in
  an interactive session; `options(morie.quiet = TRUE)` silences it.

* Requires rmoriebricklayer 0.5.2 or newer (the login flow).
* `morie_data_hosted_login()` signs in to the hosted MORIE tier (GitHub device
  flow, email code, or a key you hold) and stores the key in the credentials
  file every MORIE package reads, so rmoriedata alone is enough to use
  data.rmorie.com.
* `morie_data_hosted_catalog()` and `morie_data_hosted_load("db/table")`: the
  160 databases the MORIE project materialises from BigQuery public datasets,
  served from the edge at data.rmorie.com and opened by the MORIE key that
  rmorie, morie or rmoriebricklayer store. Cached under the package cache
  directory (`tempdir()` unless `options(rmoriedata.cache_dir = )`).

# rmoriedata 0.3.3

* Nothing is written outside `tempdir()` unless the user asks. The
  Chicago full-dataset cache lives under `tempdir()` by default and moves
  to a persistent directory only through
  `options(rmoriedata.cache_dir = )`; `clear_chicago_cache()` empties it.
  `load_chicago_data(as = "parquet_path")` also writes under `tempdir()`:
  it wrote the bundled sample into the user's `R_user_dir()` cache, and a
  bounded `full = TRUE` fetch could land on the full-dataset cache path.
  The schema names the language column of `siu_directors_reports` and
  `siu_drid_manifest` `_language`, as the files do; it carried the
  `X_language` that `check.names` had made of it, so the typed store and
  `load_siu_reports()` disagreed on the name. `load_siu_reports()` documents
  that it returns the corpus as text (`""` for empty cells) while
  `morie_data_load("siu_directors_reports")` returns the typed frame.
* Every bundled table ships as Parquet again, next to its CSV
  (`inst/extdata/parquet/<slug>.parquet`, plus `_catalog.parquet` and
  `siu_directors_reports_corpus.parquet`). `morie_data_load(format = "parquet")` and
  `load_siu_reports(format = "parquet")` read those copies; the new
  `morie_data_path(slug, format)` returns the verified path of either
  copy, which is the bridge to `pandas.read_parquet()`. The catalog gains
  a `parquet_path` column and the signed manifest covers the new files.
* The Parquet writer no longer mangles non-ASCII text in a C locale
  (`enc2utf8()` on an unmarked string turned each byte into its `<c3><a9>`
  display form, and `load_chicago_data(full = TRUE)` wrote that into the
  cross-session cache). `load_siu_reports()` reads its CSV as UTF-8 like
  the store does, so both copies agree in every locale; a data page v2
  file is reported as such before any decompression; and CI runs the
  check in a C locale. Every CSV reader in the package now declares
  UTF-8, so a live Chicago fetch and its cached copy are `identical()`
  in any locale. A string that is not valid UTF-8 and carries no
  encoding mark is refused by column name (a Parquet string is UTF-8;
  escaping lost the data, passing the bytes through made a file no other
  reader opens), and duplicate column names are refused on write and kept
  apart on read. The cross-session Chicago cache carries a SHA-256
  sidecar checked on every read. `load_cihi_data_tables()` rejects an
  `archived_only` that is not TRUE or FALSE instead of ignoring it.
* `morie_data_checksums()` gains a `path` column relative to the extdata
  root; the bare `file` basenames it returned were not unique and 20 of
  them did not resolve from the root (`morie_data_verify()` already
  returned `path`).
* `ask()` quotes every argument it hands to the `rmorie` CLI. The
  preamble contains a parenthesis, so with the CLI installed every call
  had died in the shell before the binary ran; a `;` in the question
  would have run as a command. `model` and `backend` are validated, and a
  blank or `NA` question is rejected like `""` and `NULL`. A stub binary
  on `PATH` now exercises the branch the tests never reached.
* `morie_data_load()` on a dictionary slug says to use
  `morie_data_dictionary()` instead of pointing back at the catalog.
* `load_chicago_data(full = TRUE)` no longer caches a response that is not
  the dataset. A 200 carrying an outage page, a header-only body or an
  export shorter than the row count the service reports is refused with
  the reason; before, an outage was written to the cross-session cache and
  every later session read the empty frame back. The cache is written to
  a temporary file and renamed, so a concurrent reader never sees a
  half-written file; a cache that cannot be read is discarded and
  refetched; and a new `refresh = TRUE` argument refetches on demand. When
  the service's count endpoint is down the data is returned but not
  cached across sessions.
* `fetch_cihi_table()` checks the downloaded file's size and signature
  against the catalogue's declared format and validates `which` (a whole
  number within the catalogue, or a non-empty title substring) and
  `timeout` before any request. A live URL that answers 200 with an
  outage page now falls through to the Wayback copy.
* The verifier pins the signing key's XMSS root and public seed in package
  code. A store re-signed with another key, even with a consistent
  manifest and shipped public key, no longer verifies; the signature now
  means more than a checksum against local tampering.
* CSV tables are read with `encoding = "UTF-8"` instead of
  `fileEncoding = "UTF-8-BOM"`: in a C locale the latter truncated 22 of
  the 99 tables (5 to zero rows); the bytes are now left alone and
  marked as UTF-8 in every locale.
* The data store is signed. `_checksums.csv` lists every shipped file
  with its SHA-256, and the manifest's own SHA-256 carries an XMSS
  (RFC 8391, SHA-256) signature whose public key ships as
  `_signing_key.json`. The signature is checked once per session and each
  file when first read, so a modified or corrupted install errors instead
  of returning altered data; `morie_data_verify()` checks the whole store
  at once. Needs rmoriebricklayer 0.4.0 or newer for the verification.
* `load_siu_reports(format = "parquet")` pointed at the parquet copy this
  release removed; the option now errors with a note that the gzip CSV is
  the same corpus. rmorie reads the corpus through the default `"csv"`.
* `morie_dp_gaussian_mean()` now rejects infinite `lower` or `upper` with
  the error its message already promised, instead of returning `NaN` with
  a warning from `rnorm()`.

* The data store ships every table once. `morie_data_load()` reads the
  table's CSV (the file rmorie reads by name) and applies a bundled column
  schema, so each table comes back with exactly the names and classes the
  retired parquet copies had (verified identical for all 99 tables), and
  keeps it in a session cache: repeated loads are instant. The parquet
  directory, a duplicate `samples/` directory and a second copy of the SIU
  reports are gone, which takes the source tarball from 6.8 MB to under the
  5 MB CRAN cap. The ten Victoria tables that existed only as parquet now
  ship as CSV under `vic/`. `morie_data_catalog()` has `n_rows` and
  `n_cols` for every table; `morie_data_dictionary()` returns the shipped
  JSON.
* Documentation is generated with markdown roxygen; backticks in the help pages are now `\code{}` (they rendered as stray opening quotes in the PDF manual).

# rmoriedata 0.3.2 - 2026-09-08

## describe_corpus.Rds ships here again

The narrative corpus behind `morie_describe()` was excluded from the
0.3.1 tarball to get this package under 5 MB, which left rmorie
carrying the only shipped copy. rmorie has no room for it either, so
the corpus is back where it belongs, and both packages sit in the
5-10 MB range CRAN accepts with a written justification.

# rmoriedata 0.3.1 - 2026-09-08

## Source tarball down to 4.77 MB, under CRAN's 5 MB guideline

The package shipped 9.2 MB, and most of the excess was duplication:

* `rmoriedata.sqlite` (15 MB uncompressed) was retired by the
  SQLite-to-Parquet migration and no shipped code reads it. Kept in the
  repository, excluded from the tarball.
* The SIU director's-report corpus was bundled three times -- as a
  top-level Parquet file, again inside the Parquet store, and as a
  `.csv.gz`. `load_siu_reports(format = "parquet")` now reads the store
  copy that `morie_data_load()` already serves, so the top-level
  duplicate is gone. The CSV remains: it is the default format and a
  genuinely different encoding, not a third copy of the same one.
* `describe_corpus.Rds` (1.6 MB, and it does not compress) is referenced
  by no R code, Rd page or test. Excluded.

Verified after the change: the Parquet path, the CSV path and the
`siu_directors_reports` store slug all return the same 5,157 x 65 corpus.

# rmoriedata 0.3.0 - 2026-09-08

## Native Parquet codec: one fewer hard dependency

* `nanoparquet` is gone from Imports. The bundled store is now read and
  written by this package's own codec (`R/aaa_parquet.R`), so a plain
  install no longer pulls a compiled Parquet dependency, and
  `load_siu_reports(format = "parquet")` works on a machine that never
  had one -- previously it turned a missing optional package into a hard
  stop, despite the corpus being bundled in exactly that format.

## Victorian crime data

* Ten Victorian (Australia) crime tables added to the bundled Parquet
  store, from the Crime Statistics Agency's "Latest Victorian crime data"
  release (year ending March 2026, CC BY 4.0): criminal incidents,
  recorded offences, victim reports, alleged offender incidents, family
  incidents, the LGA cuts of each, and the two Indigenous-status
  breakdowns. Reach them as `morie_data_load("vic_<key>")`; they appear
  in `morie_data_catalog()` like any other slug.
* The workbooks are .xlsx and were read with rmorie's native reader, so
  the bundled data comes through the same code path a user hits -- no
  readxl/openxlsx dependency and no second parser to disagree with the
  first. Rebuild with `data-raw/build_vic_tables.R`.
* This closes a real gap rather than adding a convenience: rmorie's
  `morie_datasets_vic_table()` defaults to `offline = TRUE`, and with
  nothing bundled it returned a 0-row frame on any machine that had not
  already downloaded the workbook.

# rmoriedata 0.2.5

* `load_chicago_data(full = TRUE)` gains `limit` (exact row cap) and
  `fraction` (share of the live dataset, total looked up first); bounded
  fetches never touch the full-dataset cache. Network examples are now
  `\donttest{}` with `try()` so they degrade gracefully offline.

* SIU corpus also bundled as Parquet; `load_siu_reports(format = "parquet")` reads it via nanoparquet (columnar / SQL-friendly). CSV remains the default (no extra dependency).

# rmoriedata 0.2.4

* SIU corpus: bundle the multi-agent panel-REVIEWED director's reports (subject-official count now 100% for all 2182 English reports; witness-officer-only cases resolved to 0). Adds a `panel_reviewed` flag column (65 cols).

# rmoriedata 0.2.3

* CRAN size compliance: removed the legacy `inst/extdata/rmoriedata.sqlite`
  (retired by the sqlite-to-parquet migration; no shipped code read it —
  the loader API is Parquet-only via `nanoparquet`, and the file remains
  backed up outside the package). Tarball drops from 5.5 MB to 4.25 MB.
* License field is now plain `AGPL (>= 3)` (the LICENSE file was a
  verbatim copy of the standard license, which CRAN flags).
* `CITATION.cff`, `NOTICE`, and `LICENSE` are excluded from the built
  package (`.Rbuildignore`), clearing the top-level-files NOTE.

# rmoriedata 0.2.0

### Connected to the shared rmorie C core

* rmoriedata now declares `LinkingTo: rmoriebricklayer (>= 0.2.0)` and links
  the ecosystem's shared compiled core instead of duplicating any C code.
* New exports `morie_core_sha256()` and `morie_core_mean()` call the shared
  kernels directly (fast data-integrity hashing + summaries for the integrated
  fixtures, with no dependency on rmorie). Tests assert they are
  byte-identical to `rmoriebricklayer`'s own `core_sha256()` / `core_mean()`.

# rmoriedata 0.1.1

### New exported helpers — differential privacy + re-identification risk

Six small, base-R-only helpers for analysts releasing aggregate statistics
from the integrated fixtures (or any other dataset) without re-identification
risk:

* `morie_dp_laplace_count()` — (epsilon, 0)-DP count via the Laplace
  mechanism (sensitivity 1).
* `morie_dp_gaussian_mean()` — approximate (epsilon, delta)-DP mean of a
  bounded numeric vector via the analytic Gaussian mechanism.
* `morie_dp_laplace_histogram()` — per-bin Laplace noise on a histogram.
* `morie_k_anonymity_verify()` — checks k-anonymity over a set of
  quasi-identifiers and returns the offending equivalence classes.
* `morie_l_diversity_verify()` — per-class distinct-count check on a
  sensitive attribute.
* `morie_cell_suppress()` — small-cell suppression with optional
  complementary suppression so primary-suppressed cells can't be
  reconstructed from row/column marginals (StatCan-style).

All helpers use only base R + the existing `stats` import; no new
runtime dependencies. Inputs are validated and edge cases (empty
vectors, NAs, out-of-bounds inputs, invalid privacy parameters) throw
informative errors.

### Tests

* `tests/testthat/test-dp.R` — Monte-Carlo convergence + variance-scaling
  sanity tests for the DP mechanisms; input-validation coverage.
* `tests/testthat/test-k-anonymity.R` — hand-built fixtures with known
  equivalence-class structure; complementary-suppression correctness.

# rmoriedata 0.1.0

* Initial public release. Integrated fixtures only; no exported functions.
