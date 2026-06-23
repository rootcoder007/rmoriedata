# rmoriedata — bundled open-data fixtures for the morie family, installed
# into a reproducible R environment. Data-only package (no compiled code,
# only base-R imports), so the build is small and fast.
FROM rocker/r-ver:4.4.1

# DBI + RSQLite power the data loaders (binary install via Posit PM).
RUN R -e "options(repos = c(CRAN = 'https://packagemanager.posit.co/cran/__linux__/jammy/latest')); \
          install.packages(c('DBI','RSQLite'))"

WORKDIR /pkg
COPY . /pkg

# Install the package and verify the SQLite-backed catalogue loads.
RUN R CMD INSTALL --no-multiarch --with-keep.source /pkg \
    && Rscript -e 'stopifnot(requireNamespace("rmoriedata", quietly = TRUE)); cat(nrow(rmoriedata::morie_data_catalog()), "datasets in the bundled store\n")'

# Drop into R with rmoriedata available:  library(rmoriedata)
CMD ["R"]
