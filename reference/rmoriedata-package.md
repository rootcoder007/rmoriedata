# rmoriedata: Disclosure control for aggregate releases, with open datasets

Tools for releasing aggregate statistics safely: differential privacy
([`dplapcnt()`](https://rootcoder007.github.io/rmoriedata/reference/dplapcnt.md)
and
[`dplaphist()`](https://rootcoder007.github.io/rmoriedata/reference/dplaphist.md)
for counts,
[`dpgmean()`](https://rootcoder007.github.io/rmoriedata/reference/dpgmean.md)
for means, with the budget kept by
[`dpbudget()`](https://rootcoder007.github.io/rmoriedata/reference/dpbudget.md)
and
[`dpspent()`](https://rootcoder007.github.io/rmoriedata/reference/dpspent.md)),
checks of k-anonymity and l-diversity
([`kanonvrf()`](https://rootcoder007.github.io/rmoriedata/reference/kanonvrf.md),
[`ldivvrf()`](https://rootcoder007.github.io/rmoriedata/reference/ldivvrf.md)),
and cell suppression audited for exact recovery from the margins
([`cellsupp()`](https://rootcoder007.github.io/rmoriedata/reference/cellsupp.md)).

## Details

Open datasets to use them on come with the package:
[`mdcat()`](https://rootcoder007.github.io/rmoriedata/reference/mdcat.md)
lists the bundled tables and
[`mdload()`](https://rootcoder007.github.io/rmoriedata/reference/mdload.md)
loads one;
[`siuload()`](https://rootcoder007.github.io/rmoriedata/reference/siuload.md),
[`chiload()`](https://rootcoder007.github.io/rmoriedata/reference/chiload.md),
[`cihitbls()`](https://rootcoder007.github.io/rmoriedata/reference/cihitbls.md)
and
[`cihiget()`](https://rootcoder007.github.io/rmoriedata/reference/cihiget.md)
read their datasets;
[`mdverify()`](https://rootcoder007.github.io/rmoriedata/reference/mdverify.md)
checks the bundle's checksums;
[`hostcat()`](https://rootcoder007.github.io/rmoriedata/reference/hostcat.md)
and
[`hostload()`](https://rootcoder007.github.io/rmoriedata/reference/hostcat.md)
reach the tables served at data.rmorie.com; and
[`mdask()`](https://rootcoder007.github.io/rmoriedata/reference/mdask.md)
asks a language model about the catalogue. The raw files are also at
`system.file("extdata", package = "rmoriedata")`.

## See also

Useful links:

- <https://rootcoder007.github.io/rmoriedata/>

- <https://github.com/rootcoder007/rmoriedata>

- Report bugs at <https://github.com/rootcoder007/rmoriedata/issues>

## Author

**Maintainer**: Vansh Singh Ruhela <vsruhela@proton.me>
([ORCID](https://orcid.org/0009-0004-1750-3592))

Authors:

- Vansh Singh Ruhela <vsruhela@proton.me>
  ([ORCID](https://orcid.org/0009-0004-1750-3592))
