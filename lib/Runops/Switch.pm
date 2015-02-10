package Runops::Switch;

use strict;
#use warnings;

our $VERSION = '0.06';

use DynaLoader ();
our @ISA = qw(DynaLoader);

bootstrap Runops::Switch $VERSION;

1;

__END__

=head1 NAME

Runops::Switch - Alternate runloop for the perl interpreter

=head1 SYNOPSIS

    perl -MRunops::Switch foo.pl

=head1 DESCRIPTION

This module provides an alternate runops loop. It's based on a large switch
statement, instead of function pointer calls like the regular perl one (in
F<run.c> in the perl source code.) I wrote it for benchmarking purposes.

Some ops are selectively inlined to reduce the function calling overhead.

As dynamic extension there is no notable speedup measurable, which is
understandable, as direct threading beats switch dispatch usually.

516 non-threaded:

    $ ./TEST op/*.t
    u=0.46 s=0.06 cu=16.27 cs=0.95 scripts=182 tests=47170
    $ PERL5OPT_TEST=-MRunops::Switch ./TEST op/.t
    u=0.49 s=0.02 cu=16.39 cs=0.83 scripts=182 tests=47170 (dynamic_ext overhead)

=head1 TODO

When the compiler understands the computed goto extension (gcc, clang,
icc, sun) it will use that instead, as this omits the range check in switch.

Generate a dispatch table at boot time, maybe even with compressed pointers to
fit into a cache line.

Further reading:

- L<http://www.emulators.com/docs/nx25_nostradamus.htm>

- L<http://www.cs.toronto.edu/~matz/dissertation/matzDissertation-latex2html/node6.html>

=head1 KNOWN PROBLEMS

This module calls directly the C<pp_*> functions from the Perl interpreter (not
through a function pointer). Since those functions aren't part of the public
Perl API, they won't be available unless you happen to run an OS that exports
every symbol by default (such as Linux without C<PERL_DL_NONLAZY> set).
Notably, this module does not compile on Windows.

=head1 AUTHOR

Written by Rafael Garcia-Suarez, based on an idea that Nicholas Clark had while
watching a talk by Leopold Toetsch. The thread is here :

    http://www.xray.mpe.mpg.de/mailing-lists/perl5-porters/2005-09/msg00012.html

Maintenance after 5.12 by Reini Urban.

This program is free software; you may redistribute it and/or modify it under
the same terms as Perl itself.

=cut
