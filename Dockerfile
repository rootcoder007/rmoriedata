# rmoriedata — bundled open-data fixtures for the morie family, installed
# into a reproducible R environment. Data-only package (no compiled code,
# only base-R imports), so the build is small and fast.
FROM rocker/r-ver:4.6.1

WORKDIR /pkg

# rmoriebricklayer now carries a C++/libcurl fetch core, so the image needs
# libcurl's dev headers to compile it.
RUN apt-get update \
    && apt-get install -y --no-install-recommends libcurl4-openssl-dev libssl-dev \
    && rm -rf /var/lib/apt/lists/*

# Install dependencies straight from DESCRIPTION (the authoritative list),
# so new Imports never drift out of sync with this image. rmoriebricklayer
# is not on CRAN: prefer its GitHub HEAD (always the latest, e.g. new
# exports like bricklayer_fetch), fall back to the r-universe binary; the
# rest resolve from Posit's CRAN mirror.
COPY DESCRIPTION /pkg/DESCRIPTION
RUN R -e "options(repos = c('https://rootcoder007.r-universe.dev', 'https://packagemanager.posit.co/cran/__linux__/jammy/latest')); \
          install.packages('remotes'); \
          ok <- tryCatch({ remotes::install_github('rootcoder007/rmorie-bricklayer', upgrade = 'never'); TRUE }, error = function(e) { message(conditionMessage(e)); FALSE }); \
          if (!ok || !requireNamespace('rmoriebricklayer', quietly = TRUE)) install.packages('rmoriebricklayer'); \
          stopifnot(requireNamespace('rmoriebricklayer', quietly = TRUE)); \
          remotes::install_deps('/pkg', dependencies = c('Depends', 'Imports', 'LinkingTo'))"

COPY . /pkg

# Install the package and verify the Parquet-backed catalogue loads.
RUN R CMD INSTALL --no-multiarch --with-keep.source /pkg \
    && Rscript -e 'stopifnot(requireNamespace("rmoriedata", quietly = TRUE)); cat(nrow(rmoriedata::morie_data_catalog()), "datasets in the bundled store\n")'

# Drop into R with rmoriedata available:  library(rmoriedata)
CMD ["R"]
