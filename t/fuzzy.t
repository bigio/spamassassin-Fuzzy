#!/usr/bin/perl

use lib '.'; use lib 't';

use Test::More;
plan tests => 9;

sub tstprefs {
  my $rules = shift;
  open(OUT, '>', 't/rules/fuzzy.cf') or die("Cannot write to rules directory: $!");
  print OUT $rules;
  close OUT;
}

sub tstcleanup {
  unlink('t/rules/fuzzy.cf');
}

my $sarun = qx{which spamassassin 2>&1};

tstprefs("
  loadplugin Mail::SpamAssassin::Plugin::Fuzzy ../../Fuzzy.pm

  ifplugin Mail::SpamAssassin::Plugin::Fuzzy

    fuzzy_redis_srv 127.0.0.1:6379
    fuzzy_redis_db  3

    body        FUZZY100      eval:fuzzy_check_100()
    describe    FUZZY100      Message body checked in spam signature and 100% spam
    score       FUZZY100      1.5

  endif
");

chomp($sarun);
my $test = qx($sarun -t --siteconfigpath=t/rules < t/data/gtube.eml);
like($test, "/FUZZY100/");

tstcleanup();
