#!perl
# from CORE t/op/fork.t

# tests for both real and emulated fork()
use Test::More;
use Runops::Switch;

BEGIN {
    require Config;
    skip_all('no fork')
	unless ($Config::Config{d_fork} or $Config::Config{d_pseudofork});
}

skip_all('fork/status problems on MPE/iX')
    if $^O eq 'mpeix';

$|=1;

# from CORE t/test.pl:
# Many tests use the same format in __DATA__ or external files to specify a
# sequence of (fresh) tests to run, extra files they may temporarily need, and
# what the expected output is. So have excatly one copy of the code to run that
#
# Each program is source code to run followed by an "EXPECT" line, followed
# by the expected output.
#
# The code to run may contain (note the '# ' on each):
#   # TODO reason for todo
#   # SKIP reason for skip
#   # SKIP ?code to test if this should be skipped
#   # NAME name of the test (as with ok($ok, $name))
#
# The expected output may contain:
#   OPTION list of options
#   OPTIONS list of options
#   PREFIX
#     indicates that the supplied output is only a prefix to the
#     expected output
#
# The possible options for OPTION may be:
#   regex - the expected output is a regular expression
#   random - all lines match but in any order
#   fatal - the code will fail fatally (croak, die)
#
# If the actual output contains a line "SKIPPED" the test will be
# skipped.
#
# If the global variable $FATAL is true then OPTION fatal is the
# default.

$::FATAL = 0;
# A regexp that matches the tempfile names
$::tempfile_regexp = 'tmp\d+[A-Z][A-Z]?';
use File::Temp 'tempfile';

# A somewhat safer version of the sometimes wrong $^X.
sub which_perl {
    unless (defined $Perl) {
	$Perl = $^X;

	# VMS should have 'perl' aliased properly
	return $Perl if $is_vms;

	my $exe;
	if (! eval {require Config; 1}) {
	    warn "test.pl had problems loading Config: $@";
	    $exe = '';
	} else {
	    $exe = $Config::Config{_exe};
	}
       $exe = '' unless defined $exe;

	# This doesn't absolutize the path: beware of future chdirs().
	# We could do File::Spec->abs2rel() but that does getcwd()s,
	# which is a bit heavyweight to do here.

	if ($Perl =~ /^perl\Q$exe\E$/i) {
	    my $perl = "perl$exe";
	    if (! eval {require File::Spec; 1}) {
		warn "test.pl had problems loading File::Spec: $@";
		$Perl = "$perl";
	    } else {
		$Perl = File::Spec->catfile(File::Spec->curdir(), $perl);
	    }
	}

	# Build up the name of the executable file from the name of
	# the command.

	if ($Perl !~ /\Q$exe\E$/i) {
	    $Perl = $Perl . $exe;
	}

	warn "which_perl: cannot find $Perl from $^X" unless -f $Perl;

	# For subcommands to use.
	$ENV{PERLEXE} = $Perl;
    }
    return $Perl;
}

sub _quote_args {
    my ($runperl, $args) = @_;

    foreach (@$args) {
	# In VMS protect with doublequotes because otherwise
	# DCL will lowercase -- unless already doublequoted.
       $_ = q(").$_.q(") if $is_vms && !/^\"/ && length($_) > 0;
       $runperl = $runperl . ' ' . $_;
    }
    return $runperl;
}

sub _print_stderr {
    local($\, $", $,) = (undef, ' ', '');
    print STDERR @_;
}

sub _create_runperl { # Create the string to qx in runperl().
    my %args = @_;
    my $runperl = which_perl();
    if ($runperl =~ m/\s/) {
        $runperl = qq{"$runperl"};
    }
    #- this allows, for example, to set PERL_RUNPERL_DEBUG=/usr/bin/valgrind
    if ($ENV{PERL_RUNPERL_DEBUG}) {
	$runperl = "$ENV{PERL_RUNPERL_DEBUG} $runperl";
    }
    unless ($args{nolib}) {
	$runperl = $runperl . ' "-I../lib"'; # doublequotes because of VMS
    }
    if ($args{switches}) {
	local $Level = 2;
	die "test.pl:runperl(): 'switches' must be an ARRAYREF " . _where()
	    unless ref $args{switches} eq "ARRAY";
	$runperl = _quote_args($runperl, $args{switches});
    }
    if (defined $args{prog}) {
	die "test.pl:runperl(): both 'prog' and 'progs' cannot be used " . _where()
	    if defined $args{progs};
        $args{progs} = [$args{prog}]
    }
    if (defined $args{progs}) {
	die "test.pl:runperl(): 'progs' must be an ARRAYREF " . _where()
	    unless ref $args{progs} eq "ARRAY";
        foreach my $prog (@{$args{progs}}) {
	    if ($prog =~ tr/'"// && !$args{non_portable}) {
		warn "quotes in prog >>$prog<< are not portable";
	    }
            if ($is_mswin || $is_netware || $is_vms) {
                $runperl = $runperl . qq ( -e "$prog" );
            }
            else {
                $runperl = $runperl . qq ( -e '$prog' );
            }
        }
    } elsif (defined $args{progfile}) {
	$runperl = $runperl . qq( "$args{progfile}");
    } else {
	# You probably didn't want to be sucking in from the upstream stdin
	die "test.pl:runperl(): none of prog, progs, progfile, args, "
	    . " switches or stdin specified"
	    unless defined $args{args} or defined $args{switches}
		or defined $args{stdin};
    }
    if (defined $args{stdin}) {
	# so we don't try to put literal newlines and crs onto the
	# command line.
	$args{stdin} =~ s/\n/\\n/g;
	$args{stdin} =~ s/\r/\\r/g;

	if ($is_mswin || $is_netware || $is_vms) {
	    $runperl = qq{$Perl -Mblib -MRunops::Switch -e "print qq(} .
		$args{stdin} . q{)" | } . $runperl;
	}
	else {
	    $runperl = qq{$Perl -Mblib -MRunops::Switch -e 'print qq(} .
		$args{stdin} . q{)' | } . $runperl;
	}
    }
    if (defined $args{args}) {
	$runperl = _quote_args($runperl, $args{args});
    }
    $runperl = $runperl . ' 2>&1' if $args{stderr};
    if ($args{verbose}) {
	my $runperldisplay = $runperl;
	$runperldisplay =~ s/\n/\n\#/g;
	_print_stderr "# $runperldisplay\n";
    }
    return $runperl;
}

sub runperl {
    die "test.pl:runperl() does not take a hashref"
	if ref $_[0] and ref $_[0] eq 'HASH';
    my $runperl = &_create_runperl;
    my $result;

    my $tainted = ${^TAINT};
    my %args = @_;
    exists $args{switches} && grep m/^-T$/, @{$args{switches}} and $tainted = $tainted + 1;

    if ($tainted) {
	# We will assume that if you're running under -T, you really mean to
	# run a fresh perl, so we'll brute force launder everything for you
	my $sep;

	if (! eval {require Config; 1}) {
	    warn "test.pl had problems loading Config: $@";
	    $sep = ':';
	} else {
	    $sep = $Config::Config{path_sep};
	}

	my @keys = grep {exists $ENV{$_}} qw(CDPATH IFS ENV BASH_ENV);
	local @ENV{@keys} = ();
	# Untaint, plus take out . and empty string:
	local $ENV{'DCL$PATH'} = $1 if $is_vms && exists($ENV{'DCL$PATH'}) && ($ENV{'DCL$PATH'} =~ /(.*)/s);
	$ENV{PATH} =~ /(.*)/s;
	local $ENV{PATH} =
	    join $sep, grep { $_ ne "" and $_ ne "." and -d $_ and
		($is_mswin or $is_vms or !(stat && (stat _)[2]&0022)) }
		    split quotemeta ($sep), $1;
	if ($is_cygwin) {   # Must have /bin under Cygwin
	    if (length $ENV{PATH}) {
		$ENV{PATH} = $ENV{PATH} . $sep;
	    }
	    $ENV{PATH} = $ENV{PATH} . '/bin';
	}
	$runperl =~ /(.*)/s;
	$runperl = $1;

	$result = `$runperl`;
    } else {
	$result = `$runperl`;
    }
    $result =~ s/\n\n/\n/ if $is_vms; # XXX pipes sometimes double these
    return $result;
}

# Nice alias
*run_perl = *run_perl = \&runperl; # shut up "used only once" warning

sub run_multiple_progs {
    my $up = shift;
    my @prgs;
    if ($up) {
	# The tests in lib run in a temporary subdirectory of t, and always
	# pass in a list of "programs" to run
	@prgs = @_;
    } else {
	# The tests below t run in t and pass in a file handle.
	my $fh = shift;
	local $/;
	@prgs = split "\n########\n", <$fh>;
    }

    my $tmpfile = tempfile('tmpXXXXX');

    for (@prgs){
	unless (/\n/) {
	    print "# From $_\n";
	    next;
	}
	my $switch = "";
	my @temps ;
	my @temp_path;
	if (s/^(\s*-\w+)//) {
	    $switch = $1;
	}
	my ($prog, $expected) = split(/\nEXPECT(?:\n|$)/, $_, 2);

	my %reason;
	foreach my $what (qw(skip todo)) {
	    $prog =~ s/^#\s*\U$what\E\s*(.*)\n//m and $reason{$what} = $1;
	    # If the SKIP reason starts ? then it's taken as a code snippet to
	    # evaluate. This provides the flexibility to have conditional SKIPs
	    if ($reason{$what} && $reason{$what} =~ s/^\?//) {
		my $temp = eval $reason{$what};
		if ($@) {
		    die "# In \U$what\E code reason:\n# $reason{$what}\n$@";
		}
		$reason{$what} = $temp;
	    }
	}
	my $name = '';
	if ($prog =~ s/^#\s*NAME\s+(.+)\n//m) {
	    $name = $1;
	}

	if ($prog =~ /--FILE--/) {
	    my @files = split(/\n--FILE--\s*([^\s\n]*)\s*\n/, $prog) ;
	    shift @files ;
	    die "Internal error: test $_ didn't split into pairs, got " .
		scalar(@files) . "[" . join("%%%%", @files) ."]\n"
		    if @files % 2;
	    while (@files > 2) {
		my $filename = shift @files;
		my $code = shift @files;
		push @temps, $filename;
		if ($filename =~ m#(.*)/# && $filename !~ m#^\.\./#) {
		    require File::Path;
		    File::Path::mkpath($1);
		    push(@temp_path, $1);
		}
		open my $fh, '>', $filename or die "Cannot open $filename: $!\n";
		print $fh $code;
		close $fh or die "Cannot close $filename: $!\n";
	    }
	    shift @files;
	    $prog = shift @files;
	}

	open my $fh, '>', $tmpfile or die "Cannot open >$tmpfile: $!";
	print $fh q{
        BEGIN {
            open STDERR, '>&', STDOUT
              or die "Can't dup STDOUT->STDERR: $!;";
        }
	};
	print $fh "\n#line 1\n";  # So the line numbers don't get messed up.
	print $fh $prog,"\n";
	close $fh or die "Cannot close $tmpfile: $!";
	my $results = runperl( stderr => 1, 
			       progfile => $tmpfile,
			       $up ? (switches => ["-I$up/lib", $switch], nolib => 1)
			           : (switches => ['-Mblib','-MRunops::Switch',$switch])
	                     );
	my $status = $?;
	$results =~ s/\n+$//;
	# allow expected output to be written as if $prog is on STDIN
	$results =~ s/$::tempfile_regexp/-/g;
	if ($^O eq 'VMS') {
	    # some tests will trigger VMS messages that won't be expected
	    $results =~ s/\n?%[A-Z]+-[SIWEF]-[A-Z]+,.*//;

	    # pipes double these sometimes
	    $results =~ s/\n\n/\n/g;
	}
	# bison says 'parse error' instead of 'syntax error',
	# various yaccs may or may not capitalize 'syntax'.
	$results =~ s/^(syntax|parse) error/syntax error/mig;
	# allow all tests to run when there are leaks
	$results =~ s/Scalars leaked: \d+\n//g;

	$expected =~ s/\n+$//;
	my $prefix = ($results =~ s#^PREFIX(\n|$)##) ;
	# any special options? (OPTIONS foo bar zap)
	my $option_regex = 0;
	my $option_random = 0;
	my $fatal = $::FATAL;
	if ($expected =~ s/^OPTIONS? (.+)\n//) {
	    foreach my $option (split(' ', $1)) {
		if ($option eq 'regex') { # allow regular expressions
		    $option_regex = 1;
		}
		elsif ($option eq 'random') { # all lines match, but in any order
		    $option_random = 1;
		}
		elsif ($option eq 'fatal') { # perl should fail
		    $fatal = 1;
		}
		else {
		    die "$0: Unknown OPTION '$option'\n";
		}
	    }
	}
	die "$0: can't have OPTION regex and random\n"
	    if $option_regex + $option_random > 1;
	my $ok = 0;
	if ($results =~ s/^SKIPPED\n//) {
	    print "$results\n" ;
	    $ok = 1;
	}
	else {
	    if ($option_random) {
	        my @got = sort split "\n", $results;
	        my @expected = sort split "\n", $expected;

	        $ok = "@got" eq "@expected";
	    }
	    elsif ($option_regex) {
	        $ok = $results =~ /^$expected/;
	    }
	    elsif ($prefix) {
	        $ok = $results =~ /^\Q$expected/;
	    }
	    else {
	        $ok = $results eq $expected;
	    }

	    if ($ok && $fatal && !($status >> 8)) {
		$ok = 0;
	    }
	}

	local $::TODO = $reason{todo};

	unless ($ok) {
	    my $err_line = "PROG: $switch\n$prog\n" .
			   "EXPECTED:\n$expected\n";
	    $err_line   .= "EXIT STATUS: != 0\n" if $fatal;
	    $err_line   .= "GOT:\n$results\n";
	    $err_line   .= "EXIT STATUS: " . ($status >> 8) . "\n" if $fatal;
	    if ($::TODO) {
		$err_line =~ s/^/# /mg;
		print $err_line;  # Harness can't filter it out from STDERR.
	    }
	    else {
		print STDERR $err_line;
	    }
	}

	ok($ok, $name);

	foreach (@temps) {
	    unlink $_ if $_;
	}
	foreach (@temp_path) {
	    File::Path::rmtree $_ if -d $_;
	}
    }
}

run_multiple_progs('', \*DATA);

done_testing();

__END__
$| = 1;
if ($cid = fork) {
    sleep 1;
    if ($result = (kill 9, $cid)) {
	print "ok 2\n";
    }
    else {
	print "not ok 2 $result\n";
    }
    sleep 1 if $^O eq 'MSWin32';	# avoid WinNT race bug
}
else {
    print "ok 1\n";
    sleep 10;
}
EXPECT
OPTION random
ok 1
ok 2
########
$| = 1;
if ($cid = fork) {
    sleep 1;
    print "not " unless kill 'INT', $cid;
    print "ok 2\n";
}
else {
    # XXX On Windows the default signal handler kills the
    # XXX whole process, not just the thread (pseudo-process)
    $SIG{INT} = sub { exit };
    print "ok 1\n";
    sleep 5;
    die;
}
EXPECT
OPTION random
ok 1
ok 2
########
$| = 1;
sub forkit {
    print "iteration $i start\n";
    my $x = fork;
    if (defined $x) {
	if ($x) {
	    print "iteration $i parent\n";
	}
	else {
	    print "iteration $i child\n";
	}
    }
    else {
	print "pid $$ failed to fork\n";
    }
}
while ($i++ < 3) { do { forkit(); }; }
EXPECT
OPTION random
iteration 1 start
iteration 1 parent
iteration 1 child
iteration 2 start
iteration 2 parent
iteration 2 child
iteration 2 start
iteration 2 parent
iteration 2 child
iteration 3 start
iteration 3 parent
iteration 3 child
iteration 3 start
iteration 3 parent
iteration 3 child
iteration 3 start
iteration 3 parent
iteration 3 child
iteration 3 start
iteration 3 parent
iteration 3 child
########
$| = 1;
fork()
 ? (print("parent\n"),sleep(1))
 : (print("child\n"),exit) ;
EXPECT
OPTION random
parent
child
########
$| = 1;
fork()
 ? (print("parent\n"),exit)
 : (print("child\n"),sleep(1)) ;
EXPECT
OPTION random
parent
child
########
$| = 1;
@a = (1..3);
for (@a) {
    if (fork) {
	print "parent $_\n";
	$_ = "[$_]";
    }
    else {
	print "child $_\n";
	$_ = "-$_-";
    }
}
print "@a\n";
EXPECT
OPTION random
parent 1
child 1
parent 2
child 2
parent 2
child 2
parent 3
child 3
parent 3
child 3
parent 3
child 3
parent 3
child 3
[1] [2] [3]
-1- [2] [3]
[1] -2- [3]
[1] [2] -3-
-1- -2- [3]
-1- [2] -3-
[1] -2- -3-
-1- -2- -3-
########
$| = 1;
foreach my $c (1,2,3) {
    if (fork) {
	print "parent $c\n";
    }
    else {
	print "child $c\n";
	exit;
    }
}
while (wait() != -1) { print "waited\n" }
EXPECT
OPTION random
child 1
child 2
child 3
parent 1
parent 2
parent 3
waited
waited
waited
########
use Config;
$| = 1;
$\ = "\n";
fork()
 ? print($Config{osname} eq $^O)
 : print($Config{osname} eq $^O) ;
EXPECT
OPTION random
1
1
########
$| = 1;
$\ = "\n";
fork()
 ? do { require Config; print($Config::Config{osname} eq $^O); }
 : do { require Config; print($Config::Config{osname} eq $^O); }
EXPECT
OPTION random
1
1
########
$| = 1;
use Cwd;
my $cwd = cwd(); # Make sure we load Win32.pm while "../lib" still works.
$\ = "\n";
my $dir;
if (fork) {
    $dir = "f$$.tst";
    mkdir $dir, 0755;
    chdir $dir;
    print cwd() =~ /\Q$dir/i ? "ok 1 parent" : "not ok 1 parent";
    chdir "..";
    rmdir $dir;
}
else {
    sleep 2;
    $dir = "f$$.tst";
    mkdir $dir, 0755;
    chdir $dir;
    print cwd() =~ /\Q$dir/i ? "ok 1 child" : "not ok 1 child";
    chdir "..";
    rmdir $dir;
}
EXPECT
OPTION random
ok 1 parent
ok 1 child
########
$| = 1;
$\ = "\n";
my $getenv;
if ($^O eq 'MSWin32' || $^O eq 'NetWare') {
    $getenv = qq[$^X -e "print \$ENV{TST}"];
}
else {
    $getenv = qq[$^X -e 'print \$ENV{TST}'];
}
$ENV{TST} = 'foo';
if (fork) {
    sleep 1;
    print "parent before: " . `$getenv`;
    $ENV{TST} = 'bar';
    print "parent after: " . `$getenv`;
}
else {
    print "child before: " . `$getenv`;
    $ENV{TST} = 'baz';
    print "child after: " . `$getenv`;
}
EXPECT
OPTION random
child before: foo
child after: baz
parent before: foo
parent after: bar
########
$| = 1;
$\ = "\n";
if ($pid = fork) {
    waitpid($pid,0);
    print "parent got $?"
}
else {
    exit(42);
}
EXPECT
OPTION random
parent got 10752
########
$| = 1;
$\ = "\n";
my $echo = 'echo';
if ($pid = fork) {
    waitpid($pid,0);
    print "parent got $?"
}
else {
    exec("$echo foo");
}
EXPECT
OPTION random
foo
parent got 0
########
if (fork) {
    die "parent died";
}
else {
    die "child died";
}
EXPECT
OPTION random
parent died at - line 2.
child died at - line 5.
########
if ($pid = fork) {
    eval { die "parent died" };
    print $@;
}
else {
    eval { die "child died" };
    print $@;
}
EXPECT
OPTION random
parent died at - line 2.
child died at - line 6.
########
if (eval q{$pid = fork}) {
    eval q{ die "parent died" };
    print $@;
}
else {
    eval q{ die "child died" };
    print $@;
}
EXPECT
OPTION random
parent died at (eval 2) line 1.
child died at (eval 2) line 1.
########
BEGIN {
    $| = 1;
    fork and exit;
    print "inner\n";
}
# XXX In emulated fork(), the child will not execute anything after
# the BEGIN block, due to difficulties in recreating the parse stacks
# and restarting yyparse() midstream in the child.  This can potentially
# be overcome by treating what's after the BEGIN{} as a brand new parse.
#print "outer\n"
EXPECT
OPTION random
inner
########
sub pipe_to_fork ($$) {
    my $parent = shift;
    my $child = shift;
    pipe($child, $parent) or die;
    my $pid = fork();
    die "fork() failed: $!" unless defined $pid;
    close($pid ? $child : $parent);
    $pid;
}

if (pipe_to_fork('PARENT','CHILD')) {
    # parent
    print PARENT "pipe_to_fork\n";
    close PARENT;
}
else {
    # child
    while (<CHILD>) { print; }
    close CHILD;
    exit;
}

sub pipe_from_fork ($$) {
    my $parent = shift;
    my $child = shift;
    pipe($parent, $child) or die;
    my $pid = fork();
    die "fork() failed: $!" unless defined $pid;
    close($pid ? $child : $parent);
    $pid;
}

if (pipe_from_fork('PARENT','CHILD')) {
    # parent
    while (<PARENT>) { print; }
    close PARENT;
}
else {
    # child
    print CHILD "pipe_from_fork\n";
    close CHILD;
    exit;
}
EXPECT
OPTION random
pipe_from_fork
pipe_to_fork
########
$|=1;
if ($pid = fork()) {
    print "forked first kid\n";
    print "waitpid() returned ok\n" if waitpid($pid,0) == $pid;
}
else {
    print "first child\n";
    exit(0);
}
if ($pid = fork()) {
    print "forked second kid\n";
    print "wait() returned ok\n" if wait() == $pid;
}
else {
    print "second child\n";
    exit(0);
}
EXPECT
OPTION random
forked first kid
first child
waitpid() returned ok
forked second kid
second child
wait() returned ok
########
pipe(RDR,WTR) or die $!;
my $pid = fork;
die "fork: $!" if !defined $pid;
if ($pid == 0) {
    close RDR;
    print WTR "STRING_FROM_CHILD\n";
    close WTR;
} else {
    close WTR;
    chomp(my $string_from_child  = <RDR>);
    close RDR;
    print $string_from_child eq "STRING_FROM_CHILD", "\n";
}
EXPECT
OPTION random
1
########
# [perl #39145] Perl_dounwind() crashing with Win32's fork() emulation
sub { @_ = 3; fork ? die "1\n" : die "1\n" }->(2);
EXPECT
OPTION random
1
1
########
# [perl #72604] @DB::args stops working across Win32 fork
$|=1;
sub f {
    if ($pid = fork()) {
	print "waitpid() returned ok\n" if waitpid($pid,0) == $pid;
    }
    else {
	package DB;
	my @c = caller(0);
	print "child: called as [$c[3](", join(',',@DB::args), ")]\n";
	exit(0);
    }
}
f("foo", "bar");
EXPECT
OPTION random
child: called as [main::f(foo,bar)]
waitpid() returned ok
########
# Windows 2000: https://rt.cpan.org/Ticket/Display.html?id=66016#txn-908976
system $^X,  "-e", "if (\$pid=fork){sleep 1;kill(9, \$pid)} else {sleep 5}";
print $?>>8, "\n";
EXPECT
0
########
# Windows 7: https://rt.cpan.org/Ticket/Display.html?id=66016#txn-908976
system $^X,  "-e", "if (\$pid=fork){kill(9, \$pid)} else {sleep 5}";
print $?>>8, "\n";
EXPECT
0
########
# Windows fork() emulation: can we still waitpid() after signalling SIGTERM?
$|=1;
if (my $pid = fork) {
    sleep 1;
    print "1\n";
    kill 'TERM', $pid;
    waitpid($pid, 0);
    print "4\n";
}
else {
    $SIG{TERM} = sub { print "2\n" };
    sleep 3;
    print "3\n";
}
EXPECT
1
2
3
4
