#!perl -w

use 5.008;
use strict;
use ExtUtils::MakeMaker;

if ($^O eq 'MSWin32' or $^O eq 'aix') {
    die "Not supported on $^O\n";
}

WriteMakefile(
    AUTHOR => 'Rafael Garcia-Suarez <rgarciasuarez@gmail.com>',
    NAME		=> 'Runops::Switch',
    VERSION_FROM	=> 'lib/Runops/Switch.pm',
    LICENSE		=> 'perl',
);

package MY;
sub test {
  local $_ = shift->SUPER::test(@_);
  s/PERL_DL_NONLAZY=1 //g;
  return $_;
}
sub depend {
  "
README : \$(VERSION_FROM)
	pod2text \$(VERSION_FROM) > README
"
}
