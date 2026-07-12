# rmoriedata — bundled open-data fixtures for the morie family, installed
# into a reproducible R environment. Data-only package (no compiled code,
# only base-R imports), so the build is small and fast.
FROM rocker/r-ver:4.6.1

WORKDIR /pkg

# Install dependencies straight from DESCRIPTION (the authoritative list),
# so new Imports never drift out of sync with this image. rmoriebricklayer
# resolves from r-universe, the rest from Posit's CRAN mirror.
COPY DESCRIPTION /pkg/DESCRIPTION
RUN R -e "options(repos = c('https://rootcoder007.r-universe.dev', 'https://packagemanager.posit.co/cran/__linux__/jammy/latest')); \
          install.packages('remotes'); \
          remotes::install_deps('/pkg', dependencies = c('Depends', 'Imports', 'LinkingTo'))"

COPY . /pkg

# Install the package and verify the Parquet-backed catalogue loads.
RUN R CMD INSTALL --no-multiarch --with-keep.source /pkg \
    && Rscript -e 'stopifnot(requireNamespace("rmoriedata", quietly = TRUE)); cat(nrow(rmoriedata::morie_data_catalog()), "datasets in the bundled store\n")'

# Drop into R with rmoriedata available:  library(rmoriedata)
CMD ["R"]
