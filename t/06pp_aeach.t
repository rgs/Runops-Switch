#!perl

use strict;
use warnings;
use Runops::Switch;
use Test::More;

BEGIN {
    if ($] < 5.011) {
        plan skip_all => "Requires 5.11";
        exit(0);
    }
}

use feature ':5.10';

# steal tests from t/op/each_array.t

use vars qw(@array @r $k $v);

plan tests => 48;

@array = qw(crunch zam bloop);

(@r) = each @array;
is (scalar @r, 2);
is ($r[0], 0);
is ($r[1], 'crunch');
($k, $v) = each @array;
is ($k, 1);
is ($v, 'zam');
($k, $v) = each @array;
is ($k, 2);
is ($v, 'bloop');
(@r) = each @array;
is (scalar @r, 0);

(@r) = each @array;
is (scalar @r, 2);
is ($r[0], 0);
is ($r[1], 'crunch');
($k) = each @array;
is ($k, 1);

SKIP: {
    skip '$[ deprecated since 5.12',3 if $] >= 5.012;
    $[ = 2;
    my ($k, $v) = each @array;
    is ($k, 4);
    is ($v, 'bloop');
    (@r) = each @array;
    is (scalar @r, 0);
}

my @lex_array = qw(PLOP SKLIZZORCH RATTLE PBLRBLPSFT);

(@r) = each @lex_array;
is (scalar @r, 2);
is ($r[0], 0);
is ($r[1], 'PLOP');
($k, $v) = each @lex_array;
is ($k, 1);
is ($v, 'SKLIZZORCH');
($k) = each @lex_array;
is ($k, 2);
SKIP: {
    skip '$[ deprecated since 5.12',2 if $] >= 5.012;
    $[ = -42;
    my ($k, $v) = each @lex_array;
    is ($k, -39);
    is ($v, 'PBLRBLPSFT');
}
(@r) = each @lex_array;
is (scalar @r, 2);

my $ar = ['bacon'];

(@r) = each @$ar;
is (scalar @r, 2);
is ($r[0], 0);
is ($r[1], 'bacon');

(@r) = each @$ar;
is (scalar @r, 0);

is (each @$ar, 0);
is (scalar each @$ar, undef);

my @keys;
@keys = keys @array;
is ("@keys", "0 1 2");

@keys = keys @lex_array;
is ("@keys", "0 1 2 3");

SKIP: {
    skip '$[ deprecated since 5.12',2 if $] >= 5.012;
    $[ = 1;

    @keys = keys @array;
    is ("@keys", "1 2 3");

    @keys = keys @lex_array;
    is ("@keys", "1 2 3 4");
}

($k, $v) = each @array;
is ($k, 0);
is ($v, 'crunch');

@keys = keys @array;
is ("@keys", "0 1 2");

($k, $v) = each @array;
is ($k, 0);
is ($v, 'crunch');



my @values;
@values = values @array;
is ("@values", "@array");

@values = values @lex_array;
is ("@values", "@lex_array");

SKIP: {
    skip '$[ deprecated since 5.12',2 if $] >= 5.012;
    $[ = 1;

    @values = values @array;
    is ("@values", "@array");

    @values = values @lex_array;
    is ("@values", "@lex_array");
}

($k, $v) = each @array;
is ($k, 0);
is ($v, 'crunch');

@values = values @array;
is ("@values", "@array");

($k, $v) = each @array;
is ($k, 0);
is ($v, 'crunch');

