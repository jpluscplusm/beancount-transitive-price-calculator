# Beancount transitive price calculator

This is a relatively unsophisticated AWK script that takes currency and commodity prices in [beancount](https://beancount.github.io/)'s plain text format, calculates explicit price information that is already implicitly held within the input data, and emits it in beancount's price format, suitable for direct consumption by beancount.

NB This script cannot *generate* price data, from online sources or anywhere else! It only exposes information that your input data already contains, albeit less visibly.

Its main use is to help in the situation where you have prices for 2 currencies, both in terms of a 3rd currency, but want to see the price of the 2 currencies in terms of each other. Beancount doesn't (currently!) use this implicit information, hence a script such as this one is required.

## Usage

```
cat *.beancount *.prices \
| awk -f transitive-prices.awk paths="CURRENCY_1:LINK_A:CURRENCY_2 CURRENCY_3:LINK_B:CURRENCY_4"
```

Where:
- the output required is:
  - prices for `CURRENCY_1` in terms of `CURRENCY_2`, and
  - prices for `CURRENCY_3` in terms of `CURRENCY_4`;
- the input files contain prices, seperately, for both `CURRENCY_1` and
  `CURRENCY_2` in terms of `LINK_A` (or vice versa);
- the input files optionally (see below) contain prices for `CURRENCY_3` and
  `CURRENCY_4` in terms of `LINK_B` (or vice versa).

Multiple `CURRENCY_1:LINK:CURRENCY_2` tuples may be included in the `paths` parameter, separated by spaces. These will be processed in the order specified, which enables the ability to create multi-hop currency chains as discussed below.

### Example

```
$ cat B.price 
2020-01-01 price B 100 A
2020-01-01 price B 5   C
2020-01-02 price A 0.02 B
2020-01-02 price C 0.35 B
$ cat B.price | awk -f transitive-prices.awk paths="A:B:C"
2020-01-01 price A 0.05 C
2020-01-02 price A 0.0571429 C
```

## Input requirements

The input does not need to be sorted, and the script should be able to cope with beancount input files containing a mixture of price directives, non-price directives, and non-directive lines.

Prices are only calculated when there is price data present on the same day for both links in a chain.  In other words, if you require currency A in terms of C, calculated via B, then an output price will only be present for those days where the input data contains an A:B price and a B:C price _on the same day_.

## Output format

The output is unsorted price data for each tuple specified in the `paths` parameter. For each tuple (`A:B:C`), the first currency specified has price data emitted in terms of the last. The pivot currency (`B` in this example) does not explicitly appear in the output.

You can pipe the output through `sort -n` to get a solely date-sorted price list, or through `sort -nk3,3 -nk1,1` for a per-currency, date-sorted price list. Beancount itself does not require sorted price data.

## Multi-hop chains

The currency chains are calculated in the order specified in the "paths" variable. The price data produced as a result of calculating each path is available for all subsequently specified paths, as if it were first-class input data.

This means that it is possible to calculate a multi-hop chain.

If you already have:

- prices for currencies A and C in terms of B
- prices for currencies C and E in terms of D

... then is it possible to calculate A in terms of E, after priming the internal price database with the appropriate interim values.

This is done as follows:

```
$ cat B.price 
2020-01-01 price B 100 A
2020-01-01 price B 5   C
2020-01-02 price A 0.02 B
2020-01-02 price C 0.35 B
$ cat D.price 
2020-01-01 price D 0.1  C
2020-01-01 price D 3    E
2020-01-02 price C 11   D
2020-01-02 price E 0.32 D
$ cat [BD].price \
  | awk -f transitive-prices.awk paths='A:B:C C:D:E A:C:E' 
2020-01-01 price A 0.05 C
2020-01-02 price A 0.0571429 C
2020-01-01 price C 30 E
2020-01-02 price C 34.375 E
2020-01-01 price A 1.5 E
2020-01-02 price A 1.96429 E
```

This works because the internal price database gets primed with both A and E in terms of C.

In the case of a non-symmetric chain, where there isn't a neat A:B:C & C:D:E relationship in your input data, you'll have to choose and construct appropriate "waypoints" in the chain to synthesise. This script isn't clever enough to figure them out on its own!

If you want to exclude the interim values from your final price list, you can either use a simple grep:

```
$ cat [BD].price \
  | awk -f transitive-prices.awk paths='A:B:C C:D:E A:C:E' \
  | grep 'A.*E'
2020-01-01 price A 1.5 E
2020-01-02 price A 1.96429 E
```

... or, if your currency names are more complex, involve regex metacharacters, or have overlapping substrings, you can use a slightly more complex but robust awk invocation:

```
$ cat [BD].price \
  | awk -f transitive-prices.awk paths='A:B:C C:D:E A:C:E' \
  | awk '$3=="A" && $5=="E"{print}'
2020-01-01 price A 1.5 E
2020-01-02 price A 1.96429 E
```

## Beancount's implicit prices

There's a beancount module (enabled in your main beancount file with `plugin "beancount.plugins.implicit_prices"`) that generates an implicit price directive every time you buy or sell a commodity, using the transaction cost to generate the prices.

If you use this plugin, then instead of providing the input to this script by simply `cat`'ing the input files, instead use `bean-report all_prices` output.

**Using this method also has the advantage of following any beancount "include" directives your ledger might contain.**

For example, here I'll use my real-life beancount ledger prices to derive USD:EUR prices.

First, let's check that there aren't any USD:EUR prices in my ledger or its includes:

```
$ bean-report ledger.beancount all_prices \
  | grep -c 'USD.*EUR'
0
```

Now let's use the transitive price calculator to process bean-report's output, using my knowledge that it contains both USD and EUR prices in terms of GBP:

```
$ bean-report ledger.beancount all_prices \
  | awk -f ../beancount-transitive-price-calculator/transitive-prices.awk paths="USD:GBP:EUR" \
  | grep -c 'USD.*EUR'
2734
```

Lastly, let's randomly sample the output to check the accuracy:

```
$ bean-report ledger.beancount all_prices \
  | awk -f ../beancount-transitive-price-calculator/transitive-prices.awk paths="USD:GBP:EUR" \
  | grep 'USD.*EUR' \
  | shuf -n 1
2012-07-24 price USD 0.824832 EUR
```

Comparing against [an historic online source](https://www.exchangerates.org.uk/USD-EUR-24_07_2012-exchange-rate-history.html), which shows a rate of 0.8289, we can see that the difference is `( ( 0.8289 - 0.824832 ) / 0.8289 ) == 0.004907`, or about half a percentage point. This is well within the bounds of the accuracy acheivable from consumer data sources and differing (mid-)market rates, etc.

Take into account the additional fact that real life currency rates [aren't actually transitive](https://travel.stackexchange.com/a/88969), especially within the consumer market context to which most of us have access, and we're happy that the script's performing as well as it can, given its constraints.

## Misc. internal notes

For each input price provided, the direct price (A in terms of B, which we'll call "A:B") is stored for that day in the "direct" price database. When input files contain price data with duplicate A:B entries for the same day, the final entry observed is stored. 

For each A:B price observed, the inverse B:A price is calculated and stored for that day in the "inverse" price database. As above, the final entry calculated for each day is the only one stored.

After all input files have been consumed, the direct and inverse price databases are merged, with preference given to entries in the "direct" database. This aims to use explicitly provided prices where possible, falling back to calculated prices if required.

HOWEVER, the combination of the above rules is subtle. Consider this input data (possibly split across multiple files, of course):

```
2020-01-01 price A 10.0 B
2020-01-01 price B 0.90 A
```

After these input prices are consumed, there exist difference prices for A in terms of B and B in terms of A, on the same day. The "inverse" price of both directives has been overridden by a "direct" price, which was explicitly present in the input data.

It is very unlikely that this will occur often, and even more unlikely that it will present a problem if it does occur. If you have an idea for a better treatment of this corner-corner-case, please get in touch!

This script has been minimally tested with GNU AWK, gawk, and the (current) Debian default AWK, mawk.
