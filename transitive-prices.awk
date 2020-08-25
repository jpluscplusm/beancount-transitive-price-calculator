paths == "" {
	print "Usage: (please read the documentation at https://github.com/jpluscplusm/beancount-inverse-price-calculator)"
	print "$ cat *.beancount | awk -f transitive-prices.awk paths='GBP:EUR:USD'"
	exit 1
}

   $1 ~ /^[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]$/ \
&& $2 == "price" \
&& $3 ~ /[A-Z0-9'._-]+/ \
&& $4 ~ /[0-9.]+/ \
&& $5 ~ /[A-Z0-9'._-]+/ {
	date  = $1
	from  = $3
	to    = $5
	price = $4
	direct[date,from,to] = price
	prices[date,to,from] = (1/price)
}

END {
	for ( key in direct ) {
		prices[key] = direct[key]
	}

	split(paths, required_chain, " ")
	for ( required_price in required_chain ) {
		split(required_chain[required_price], currency_path, ":")
		currency_one  = currency_path[1]
		currency_join = currency_path[2]
		currency_two  = currency_path[3]

		for ( combined in prices ) {
			split(combined, price_entry, SUBSEP)
			date = price_entry[1]
			from = price_entry[2]
			to   = price_entry[3]

			if ( from == currency_one && to == currency_two ) {
				print date, "price", from, prices[date,from,to], to
			} else if ( ( date, currency_one,  currency_two ) in prices ) {
				continue
			} else if ( from == currency_one && to == currency_join ) {
				if ( ( date, currency_join, currency_two ) in prices ) {
					price = prices[date,currency_one,currency_join] * prices[date,currency_join, currency_two]
					print date, "price", currency_one, price, currency_two
					prices[date,currency_one,currency_two] = price
					prices[date,currency_two,currency_one] = (1/price)
				}
			}
		}
	}
}
