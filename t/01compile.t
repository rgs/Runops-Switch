#!perl

use Test::More tests => 5;

use_ok('Runops::Switch');
pass('and it continues to work');
eval  { pass('... in eval {}') };
eval q{ pass('... in eval STRING') };

my $file = "dotest.pl";
open my $fh, ">", $file or die $!;
print $fh <<DOFILE;
pass("passes in done file");
1;
DOFILE
close $fh;

do $file;
END { unlink $file }
