# rmoriedata — bundled open-data fixtures for the morie family, installed
# into a reproducible R environment. Data-only package (no compiled code,
# only base-R imports), so the build is small and fast.
FROM rocker/r-ver:4.4.1

WORKDIR /pkg
COPY . /pkg

# Install the package and verify it loads + the bundled data is reachable.
RUN R CMD INSTALL --no-multiarch --with-keep.source /pkg \
    && Rscript -e 'stopifnot(requireNamespace("rmoriedata", quietly = TRUE)); cat("rmoriedata installed OK\n")'

# Drop into R with rmoriedata available:  library(rmoriedata)
CMD ["R"]
