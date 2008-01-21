#!perl

use strict;
use warnings;
use Runops::Switch;
use Test::More tests => 1;
use feature qw(say);

open my $tmp, '>', \my $out;
say $tmp "foo";
is($out, "foo\n", "say works");
