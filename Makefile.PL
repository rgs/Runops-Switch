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
