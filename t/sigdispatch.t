#!perl -w
# from CORE t/op/sigdispatch.t

use Test::More;
use Runops::Switch;
use strict;
use Config;

plan tests => 17;

# from CORE t/test.pl:
my $NO_ENDING = 0;

# Set a watchdog to timeout the entire test file
# NOTE:  If the test file uses 'threads', then call the watchdog() function
#        _AFTER_ the 'threads' module is loaded.
sub watchdog ($;$)
{
    my $timeout = shift;
    my $method  = shift || "";
    my $timeout_msg = 'Test process timed out - terminating';

    # Valgrind slows perl way down so give it more time before dying.
    $timeout *= 10 if $ENV{PERL_VALGRIND};

    my $pid_to_kill = $$;   # PID for this process

    if ($method eq "alarm") {
        goto WATCHDOG_VIA_ALARM;
    }

    # shut up use only once warning
    my $threads_on = $threads::threads && $threads::threads;
    my $is_mswin    = $^O eq 'MSWin32';
    my $is_netware  = $^O eq 'NetWare';
    my $is_vms      = $^O eq 'VMS';
    my $is_cygwin   = $^O eq 'cygwin';

    # Don't use a watchdog process if 'threads' is loaded -
    #   use a watchdog thread instead
    if (!$threads_on || $method eq "process") {

        # On Windows and VMS, try launching a watchdog process
        #   using system(1, ...) (see perlport.pod)
        if ($is_mswin || $is_vms) {
            # On Windows, try to get the 'real' PID
            if ($is_mswin) {
                eval { require Win32; };
                if (defined(&Win32::GetCurrentProcessId)) {
                    $pid_to_kill = Win32::GetCurrentProcessId();
                }
            }

            # If we still have a fake PID, we can't use this method at all
            return if ($pid_to_kill <= 0);

            # Launch watchdog process
            my $watchdog;
            eval {
                local $SIG{'__WARN__'} = sub {
                    diag("Watchdog warning: $_[0]");
                };
                my $sig = $is_vms ? 'TERM' : 'KILL';
                my $cmd = _create_runperl( prog =>  "sleep($timeout);" .
                                                    "warn qq/# $timeout_msg" . '\n/;' .
                                                    "kill($sig, $pid_to_kill);");
                $watchdog = system(1, $cmd);
            };
            if ($@ || ($watchdog <= 0)) {
                diag('Failed to start watchdog');
                diag($@) if $@;
                undef($watchdog);
                return;
            }

            # Add END block to parent to terminate and
            #   clean up watchdog process
            eval "END { local \$! = 0; local \$? = 0;
                        wait() if kill('KILL', $watchdog); };";
            return;
        }

        # Try using fork() to generate a watchdog process
        my $watchdog;
        eval { $watchdog = fork() };
        if (defined($watchdog)) {
            if ($watchdog) {   # Parent process
                # Add END block to parent to terminate and
                #   clean up watchdog process
                eval "END { local \$! = 0; local \$? = 0;
                            wait() if kill('KILL', $watchdog); };";
                return;
            }

            ### Watchdog process code

            # Load POSIX if available
            eval { require POSIX; };

            # Execute the timeout
            sleep($timeout - 2) if ($timeout > 2);   # Workaround for perlbug #49073
            sleep(2);

            # Kill test process if still running
            if (kill(0, $pid_to_kill)) {
                diag($timeout_msg);
                kill('KILL', $pid_to_kill);
		if ($is_cygwin) {
		    # sometimes the above isn't enough on cygwin
		    sleep 1; # wait a little, it might have worked after all
		    system("/bin/kill -f $pid_to_kill");
		}
            }

            # Don't execute END block (added at beginning of this file)
            $NO_ENDING = 1;

            # Terminate ourself (i.e., the watchdog)
            POSIX::_exit(1) if (defined(&POSIX::_exit));
            exit(1);
        }

        # fork() failed - fall through and try using a thread
    }

    # Use a watchdog thread because either 'threads' is loaded,
    #   or fork() failed
    if (eval {require threads; 1}) {
        'threads'->create(sub {
                # Load POSIX if available
                eval { require POSIX; };

                # Execute the timeout
                my $time_left = $timeout;
                do {
                    $time_left = $time_left - sleep($time_left);
                } while ($time_left > 0);

                # Kill the parent (and ourself)
                select(STDERR); $| = 1;
                diag($timeout_msg);
                POSIX::_exit(1) if (defined(&POSIX::_exit));
                my $sig = $is_vms ? 'TERM' : 'KILL';
                kill($sig, $pid_to_kill);
            })->detach();
        return;
    }

    # If everything above fails, then just use an alarm timeout
WATCHDOG_VIA_ALARM:
    if (eval { alarm($timeout); 1; }) {
        # Load POSIX if available
        eval { require POSIX; };

        # Alarm handler will do the actual 'killing'
        $SIG{'ALRM'} = sub {
            select(STDERR); $| = 1;
            diag($timeout_msg);
            POSIX::_exit(1) if (defined(&POSIX::_exit));
            my $sig = $is_vms ? 'TERM' : 'KILL';
            kill($sig, $pid_to_kill);
        };
    }
}

watchdog(15);

$SIG{ALRM} = sub {
    die "Alarm!\n";
};

pass('before the first loop');

alarm 2;

eval {
    1 while 1;
};

is($@, "Alarm!\n", 'after the first loop');

pass('before the second loop');

alarm 2;

eval {
    while (1) {
    }
};

is($@, "Alarm!\n", 'after the second loop');

SKIP: {
    skip('We can\'t test blocking without sigprocmask', 11)
	if !$Config{d_sigprocmask};
    skip('This doesn\'t work on OpenBSD threaded builds RT#88814', 11)
        if $^O eq 'openbsd' && $Config{useithreads};

    require POSIX;
    my $new = POSIX::SigSet->new(&POSIX::SIGUSR1);
    POSIX::sigprocmask(&POSIX::SIG_BLOCK, $new);
    
    my $gotit = 0;
    $SIG{USR1} = sub { $gotit++ };
    kill SIGUSR1, $$;
    is $gotit, 0, 'Haven\'t received third signal yet';
    
    my $old = POSIX::SigSet->new();
    POSIX::sigsuspend($old);
    is $gotit, 1, 'Received third signal';
    
	{
		kill SIGUSR1, $$;
		local $SIG{USR1} = sub { die "FAIL\n" };
		POSIX::sigprocmask(&POSIX::SIG_BLOCK, undef, $old);
		ok $old->ismember(&POSIX::SIGUSR1), 'SIGUSR1 is blocked';
		eval { POSIX::sigsuspend(POSIX::SigSet->new) };
		is $@, "FAIL\n", 'Exception is thrown, so received fourth signal';
		POSIX::sigprocmask(&POSIX::SIG_BLOCK, undef, $old);
TODO:
	    {
		local $::TODO = "Needs investigation" if $^O eq 'VMS';
		ok $old->ismember(&POSIX::SIGUSR1), 'SIGUSR1 is still blocked';
	    }
	}

TODO:
    {
	local $::TODO = "Needs investigation" if $^O eq 'VMS';
	kill SIGUSR1, $$;
	is $gotit, 1, 'Haven\'t received fifth signal yet';
	POSIX::sigprocmask(&POSIX::SIG_UNBLOCK, $new, $old);
	ok $old->ismember(&POSIX::SIGUSR1), 'SIGUSR1 was still blocked';
    }
    is $gotit, 2, 'Received fifth signal';

    # test unsafe signal handlers in combination with exceptions
    my $action = POSIX::SigAction->new(sub { $gotit--, die }, POSIX::SigSet->new, 0);
    POSIX::sigaction(&POSIX::SIGALRM, $action);
    eval {
        alarm 1;
        my $set = POSIX::SigSet->new;
        POSIX::sigprocmask(&POSIX::SIG_BLOCK, undef, $set);
        is $set->ismember(&POSIX::SIGALRM), 0, "SIGALRM is not blocked on attempt $_";
        POSIX::sigsuspend($set);
    } for 1..2;
    is $gotit, 0, 'Received both signals';
}

SKIP: {
    skip("alarm cannot interrupt blocking system calls on $^O", 2)
	if ($^O eq 'MSWin32' || $^O eq 'VMS');
    # RT #88774
    # make sure the signal handler's called in an eval block *before*
    # the eval is popped

    $SIG{'ALRM'} = sub { die "HANDLER CALLED\n" };

    eval {
	alarm(2);
	select(undef,undef,undef,10);
    };
    alarm(0);
    is($@, "HANDLER CALLED\n", 'block eval');

    eval q{
	alarm(2);
	select(undef,undef,undef,10);
    };
    alarm(0);
    is($@, "HANDLER CALLED\n", 'string eval');
}
