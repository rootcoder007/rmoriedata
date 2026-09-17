# Sign the data store. Run from the package root after any change under
# inst/extdata (and after `git add` of any new file there):
#
#   Rscript data-raw/sign_store.R
#
# Writes inst/extdata/_checksums.csv (path, bytes, sha256 of every shipped
# file), signs the SHA-256 of that file with the XMSS (RFC 8391, SHA-256)
# key at ~/.morie/rmoriedata-signing-key.rds, writes the signature to
# _checksums.sig and the public key to _signing_key.json. XMSS is stateful:
# the advanced key state is saved back, so an index is never reused. The
# private key never enters the repository.
suppressPackageStartupMessages(library(rmoriebricklayer))
ed <- "inst/extdata"
key_path <- path.expand("~/.morie/rmoriedata-signing-key.rds")
if (!file.exists(key_path)) {
  dir.create(dirname(key_path), showWarnings = FALSE, recursive = TRUE)
  saveRDS(pqc_keygen(height = 10L), key_path)
  Sys.chmod(key_path, "600")
  message("new signing key written to ", key_path, " (back it up)")
}
key <- readRDS(key_path)
files <- sort(system2("git", c("ls-files", ed), stdout = TRUE))
files <- files[!basename(files) %in% c("_checksums.csv", "_checksums.sig",
                                        "_signing_key.json")]
# only what R CMD build ships: drop anything .Rbuildignore excludes
ign <- readLines(".Rbuildignore", warn = FALSE)
ign <- ign[nzchar(ign) & !startsWith(ign, "#")]
for (pat in ign) files <- files[!grepl(pat, files, perl = TRUE)]
man <- data.frame(path = sub(paste0("^", ed, "/"), "", files),
                  bytes = file.size(files),
                  sha256 = vapply(files, sha256_file, ""),
                  stringsAsFactors = FALSE)
rownames(man) <- NULL
mf <- file.path(ed, "_checksums.csv")
utils::write.csv(man, mf, row.names = FALSE, fileEncoding = "UTF-8")
bytes <- readBin(mf, "raw", n = file.size(mf))
sig <- capsule_sign(core_sha256(bytes), key)
saveRDS(sig$key_state, key_path)
sig$key_state <- NULL
writeLines(bricklayer_json_to_json(unclass(sig)), file.path(ed, "_checksums.sig"))
writeLines(bricklayer_json_to_json(unclass(signing_public_key(key))),
           file.path(ed, "_signing_key.json"))
# self-check through the same path the package uses
s2 <- bricklayer_json_from_json(paste(readLines(file.path(ed, "_checksums.sig")), collapse = "\n"))
class(s2) <- c("bricklayer_signature", "list")
p2 <- bricklayer_json_from_json(paste(readLines(file.path(ed, "_signing_key.json")), collapse = "\n"))
class(p2) <- c("bricklayer_public_key", "list")
stopifnot(isTRUE(capsule_verify(core_sha256(bytes), s2, p2)))
message(nrow(man), " files in the manifest; signature index ", sig$index,
        "; verified through the JSON round trip")
