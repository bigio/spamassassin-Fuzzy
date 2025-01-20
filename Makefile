PREFIX ?= /usr/local

check:
	perl -cw Fuzzy.pm
	podchecker Fuzzy.pm

doc:
	pod2man Fuzzy.pm > "man/man3p/Mail::SpamAssassin::Plugin::Fuzzy.3p"
	pod2man bin/fuzzystore.pl > "man/man1/fuzzystore.pl.1"

install:
	mkdir -p ${PREFIX}/share/man/{man1,man3p}
	install -m 644 Fuzzy.pm /etc/mail/spamassassin/
	install -m 644 Fuzzy.pre /etc/mail/spamassassin/
	install -m 644 Fuzzy.cf /etc/mail/spamassassin/
	install -m 755 bin/fuzzystore.pl ${PREFIX}/bin
	install -m 644 man/man3p/Mail::SpamAssassin::Plugin::Fuzzy.3p ${PREFIX}/share/man/man3p/
