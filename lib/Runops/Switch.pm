package Runops::Switch;

use strict;
use warnings;

our $VERSION = '0.04';

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

=head1 KNOWN PROBLEMS

This module calls directly the C<pp_*> functions from the Perl interpreter (not
through a function pointer). Since those functions aren't part of the public
Perl API, they won't be available unless you happen to run an OS that exports
every symbol by default (such as Linux). Notably, this module does not compile
on Windows.

=head1 AUTHOR

Written by Rafael Garcia-Suarez, based on an idea that Nicholas Clark had while
watching a talk by Leopold Toetsch. The thread is here :

    http://www.xray.mpe.mpg.de/mailing-lists/perl5-porters/2005-09/msg00012.html

This program is free software; you may redistribute it and/or modify it under
the same terms as Perl itself.

=cut
