#!/usr/bin/perl -w
#
# rshall - Run command on all servers.
#
# Copyright (c) 1998-2015 Occam's Razor. All rights reserved.
#
# See the LICENSE file distributed with this code for restrictions on its use
# and further distribution.
# Original distribution available at <http://www.occam.com/tools/>.
#
# $Id: rshall.pl,v 14.3 2015/11/02 02:15:12 leonvs Exp $
#
# TODO
#	multiple -s, -m, -c arguments
#		impossible w/ Getopt::Std?
#	get scp to report copy progress?
#	check .my.cnf for user/pass
#	output options for SQL mode? - vertical, tab-delimited, no headings
#	in canConnect(), do a DBI ping if $mode eq "SQL"
#	move some functions to external utility module?
#

use strict;
use POSIX ":sys_wait_h";		# for WNOHANG

use Getopt::Std;
our ($opt_h, $opt_V, $opt_d, $opt_f, $opt_l, $opt_v, $opt_t, $opt_n, $opt_r, $opt_1, $opt_F, $opt_D, $opt_L, $opt_s, $opt_S, $opt_m, $opt_M, $opt_w, $opt_W, $opt_c, $opt_C);

# global variables
my $DEBUG = 0;
my $progname;
my $mode;					# rshall, cpall, sqall switch
my $COMPACT = 0;				# compact output
my $outBase;					# send output to files
my $DIFFS = 0;					# discard common lines
my $SUMLINES = 0;				# summarize by line
my $maxLines = 0;				# discard common lines over this
my %lineCount = ();				# used for DIFFS/SUMLINES modes
my %results = ();				# used for DIFFS mode
my %lines = ();					# used for SUMLINES mode
my $connTimeout = 10;				# default SSH connection timeout
my $maxForks;
my $numForks = 0;
my $ROOT = 0;
my $hostFile = "/usr/local/etc/systems";	# default config file
my $command;
my $copyDest;
my @copyList = ();
my @host = ();
my $hostFieldLen = 0;
my @pid = ();
my $retVal = 0;					# returns last bad exit code

my $rshCmd = "/usr/bin/rsh";
my $rcpCmd = "/usr/bin/rcp -pr";
my $sshCmd = "/usr/bin/ssh -q";
my $scpCmd = "/usr/bin/scp -qpr";
my $sqlCmd = "/usr/bin/mysql";
my $sudoCmd = "/usr/bin/sudo";

setup();
foreach (@host) { processHost($_); }
if ($DIFFS) {
	foreach my $host (sort keys %results) {
		my $result;
		foreach my $l (@{$results{$host}}) {
			$result .= $l if $lineCount{$l} <= $maxLines;
		}
		$result and printOut($host, $result);
	}
} elsif ($SUMLINES) {
	foreach my $l (sort keys %lines) {
		if ($lineCount{$l} <= $maxLines) {
			# Separate hostnames with spaces or newlines.
			my $joint = $COMPACT ? " " : "\n";
			my $hosts = join $joint, @{$lines{$l}};
			$hosts .= "\n";
			chomp $l;
			printOut($l, $hosts);
		}
	}
}
# Wait for all child processes before exiting main program.
foreach (@pid) { waitpid $_, 0; }
report("DEBUG", "Exit code is $retVal.");
exit(($retVal & 0x7F) ? ($retVal|0x80) : $retVal >> 8);

sub setup {
	$progname = $0; $progname =~ s/.*\///;

	$mode = "CMD";		# Default is to run command on remote hosts.
	$mode = "COPY" if $progname =~ /^cpall/;
	$mode = "SQL" if $progname =~ /^sqall/;
	report("DEBUG", "Mode is $mode.");

	my $VERSION = "$progname 14.3\n";

	my $USAGE = <<EOF;
$VERSION
usage:	$progname { -h | -V }
	$progname [-d] [-f filename] [match_option match_arg]... -l [-v]
	$progname [-d] [-f filename] [match_option match_arg]...
		[-t timeout] [-n max_conns] [-r]
EOF

	if ($mode eq "COPY") {
		$USAGE .= <<EOF;
		pathname [pathname]...
EOF
	} else {
		$USAGE .= <<EOF;
		[-1 | -F base_path] [[-D | -L] max_lines] command
EOF
	}

	$USAGE .= <<EOF;

	-h: Prints this usage statement and exits.
	-V: Prints version number and exits.
	-d: Enables debugging output.
	-f: Selects file with host info. Defaults to $hostFile.
	-l: Lists matching hosts, without executing remote commands.
	-v: When listing hosts, prints associated info.
	-t: Connection timeout, in seconds. Defaults to $connTimeout.
	-n: Maximum simultaneous connections. Defaults to no limit (0).
		Setting this to 1 forces serialized connections.
	-r: Makes connections as root (using sudo), instead of as calling user.

	Match options are used to restrict which hosts are listed or contacted.
	The arguments to these options are used in case-insensitive substring
	matches. Match options include:

	-s: Includes hosts that match operating system name and/or version.
	-S: Excludes hosts that match operating system name and/or version.
	-m: Includes hosts that match hardware model.
	-M: Excludes hosts that match hardware model.
	-w: Includes hosts that match location.
	-W: Excludes hosts that match location.
	-c: Includes hosts that match comments.
	-C: Excludes hosts that match comments.

EOF

	if ($mode eq "COPY") {
		$USAGE .= <<EOF;
	pathname: The files or directories to copy to the hosts. If there is
		more than one pathname argument, the final argument is the
		destination on the remote host. If there is only one argument,
		the source is copied to the same location on the remote host.
EOF
	} else {
		$USAGE .= <<EOF;
	-1: Produces output in a compact format, suitable for commands that
		generate single-line output.
	-F: Instead of printing to standard output, sends output to individual
		files named by host, as "\<base_path\>\<hostname\>".
	-D: Show differences; discard lines appearing more than max_lines times.
	-L: Display by line; discard lines appearing more than max_lines times.
	command: Command to execute on hosts. No need for quotes, unless you
		include shell metacharacters.
EOF
	}

	getopts('hVdf:lvt:n:r1F:D:L:s:S:m:M:w:W:c:C:') or die $USAGE;
	$opt_h and die $USAGE;
	$opt_V and die $VERSION;

	$opt_d and $DEBUG++;

	# For some reason, if these aren't explicitly set to something, then
	# they stop matching once a specified option is matched. Weird.
	# So set them to something (".") that will match anything.
	$opt_s ||= ".";
	$opt_m ||= ".";
	$opt_w ||= ".";
	$opt_c ||= ".";

	# Set the defaults to something unlikely to match.
	$opt_S ||= "NOMATCH";
	$opt_M ||= "NOMATCH";
	$opt_W ||= "NOMATCH";
	$opt_C ||= "NOMATCH";

	unless ($opt_l) {
		if ($opt_t) {
			$opt_t =~ /^\d+$/
				or report("ERR", "Timeout must be an integer.");
			$connTimeout = $opt_t;
		}
		$sshCmd .= " -o ConnectTimeout=$connTimeout";
		$scpCmd .= " -o ConnectTimeout=$connTimeout";
		$sqlCmd .= " --connect_timeout=$connTimeout";

		if ($opt_n) {
			$opt_n =~ /^\d+$/
				or report("ERR", "Max conns must be an integer.");
			$maxForks = $opt_n;
		}

		if ($mode eq "COPY") {
			# Always use compact output format for copy mode.
			$COMPACT++;

			$copyDest = pop @ARGV or die $USAGE;
			isValidPathname($copyDest)
				or invalidate($copyDest, "pathname");
			@copyList = @ARGV;
			foreach my $path (@copyList) {
				isValidPathname($path)
					or invalidate($path, "pathname");
			}
		} else {
			# Only one of these should be set.
			$opt_1 and $opt_F and die $USAGE;
			$opt_1 and $COMPACT++;
			$sqlCmd .= $COMPACT ? " -Bs" : " -t";
			if ($opt_F) {
				$outBase = $opt_F;
				isValidPathname($outBase)
					or invalidate($outBase, "pathname");
				# Create directory if needed.
				if ($outBase =~ /\//) {
					my $outDir = $outBase;
					$outDir =~ s/\/[^\/]*$//;
					-d $outDir or mkdir $outDir, 0700
						or report("ERR",
							"Can't create $outDir.");
				}
			}
			# Only one of these should be set.
			$opt_D and $opt_L and die $USAGE;
			# If either is 0, it will have no effect.
			if ($opt_D) {
				$DIFFS++;
				$maxLines = $opt_D;
			}
			if ($opt_L) {
				$SUMLINES++;
				$maxLines = $opt_L;
			}
			if ($maxLines) {
				report("DEBUG", "Max lines is $maxLines.");
				$maxLines =~ /^\d+$/
					or report("ERR",
						"Max lines must be an integer.");
			}
			$command = join " ", @ARGV or die $USAGE;
 			report("DEBUG", "Command is $command.");
 			# Escape common shell metacharacters.
 			$command =~ s/([;|<>*?`"])/\\$1/g;
			# Don't escape single quotes in SQL commands.
			# Single quotes in SQL commands must be escaped on the
			# command line.  :(
 			$command =~ s/(['])/\\$1/g unless $mode eq "SQL";
 			report("DEBUG", "Command is $command.");
		}
		
		# Make sure sudo won't need to prompt for a password during the
		# loop on hosts, or things get ugly.
		$opt_r and $ROOT++ and system "$sudoCmd /bin/echo";
	}

	if ($opt_f) {
		$hostFile = $opt_f;
		isValidPathname($hostFile) or invalidate($hostFile, "pathname");
	}
	getHosts($hostFile);

	# Determine longest hostname for cleaner output.
	foreach (@host) {
		my ($hostname) = split /\t+/;
		if (length $hostname > $hostFieldLen) {
			$hostFieldLen = length $hostname;
			report("DEBUG", "Longest hostname is $hostname.");
		}
	}
	# Make room for colon and space following hostname.
	$hostFieldLen += 2;

	# Keep count of active child processes.
	$SIG{CHLD} = \&trackForks;
}

sub getHosts {
	my $hostFile = shift;
	my $progdir = $0; $progdir =~ s/\/[^\/]+$//;
	report("DEBUG", "Executable directory is $progdir.");

 	# Use rshall_ext or readinfo if available (i.e., if in same directory).
	# If -f specified, don't use rshall_ext.
 	if (-x "$progdir/rshall_ext" and !$opt_f) {
 		open HOSTLIST, "$progdir/rshall_ext |"
 			or report("ERR", "Can't exec $progdir/rshall_ext.");
 	} elsif (-x "$progdir/readinfo") {
 		open HOSTLIST, "$progdir/readinfo -P -N -i $hostFile host os hw loc comment ssh |"
 			or report("ERR",
				"Can't exec $progdir/readinfo on $hostFile.");
	} else {
		open HOSTLIST, $hostFile or report("ERR", "Can't read $hostFile.");
	}
	while (<HOSTLIST>) {
		push @host, $_ unless /^#/;
	}
	close HOSTLIST;
}

sub trackForks {
	while ((my $pid = waitpid(-1, WNOHANG)) > 0) {
		$? and $retVal = $?;
		# Decrement number of active children.
		if ($maxForks) {
			--$numForks;
			report("DEBUG",
				"$$: $numForks forks after receiving SIGCHLD.");
		}
	}

	# Reinstall signal handler.
	$SIG{CHLD} = \&trackForks;
}

sub processHost {
	my $hostData = shift;
	chomp $hostData;
	my ($host, $os, $hw, $loc, $comment, $SSH) = split /\t+/, $hostData;
	my $pid;
	my $argument;
	my $result;

	isValidHostname($host)
		or (report("WARN", "Invalid hostname: $host.") and return);

	if ($os =~ /$opt_s/i and $os !~ /$opt_S/i
		and $hw =~ /$opt_m/i and $hw !~ /$opt_M/i
		and $loc =~ /$opt_w/i and $loc !~ /$opt_W/i
		and $comment =~ /$opt_c/i and $comment !~ /$opt_C/i) {

		if ($opt_l) {
			# Print all info in verbose mode, else just hostname.
			print $opt_v ? "$hostData" : "$host";
			print "\n";
			return;
		}

		if ($maxForks) {
			report("DEBUG", "$numForks forks prior to fork.");
			$numForks++;
			sleep 1 while ($numForks > $maxForks);
		}

		if ($mode eq "COPY") {
			# Copy files to host.
			if (scalar @copyList) {
				# If any file arguments are left, then last arg
				# is a remote destination, and others are local
				# source files.
				$argument = "@copyList $host:$copyDest";
			} else {
				# If there was only one file argument, then
				# remote destination is same as local source.
				$argument = "$copyDest $host:$copyDest";
			}
		} else {
			# Run command on host.
			$argument = "$command";
		}
		report("DEBUG", "Argument is $argument.");

		# Disable strict refs to use variable filehandles.
		no strict 'refs';
		# Use pipe to pass data back to parent for DIFFS/SUMLINES modes.
		# Need different pipe for each child.
		my $readFH = "READER_$host";
		my $writeFH = "WRITER_$host";
		pipe $readFH, $writeFH or
			report("ERR", "Can't open pipe for parent and child.");

		FORK:
		if ($pid = fork) {
			# Parent process: Keep track of child PIDs to wait on.
			push @pid, $pid;
			close $writeFH;
			if ($maxLines) {
				# Read data from child.
				my @result = <$readFH>;
				foreach my $l (@result) {
					$lineCount{$l}++;
					push @{$lines{$l}}, $host if $SUMLINES;
				}
				@{$results{$host}} = @result if $DIFFS;
			}
			close $readFH;
		} elsif (defined $pid) {
			# Child process: Execute remote command, print result.
			$SIG{CHLD} = 'DEFAULT';
			close $readFH;
			$result = rdoit($host, $argument, $SSH, $mode, $ROOT);
			if ($maxLines) {
				# Write data to parent.
				print $writeFH $result;
				close $writeFH;
			} else {
				printOut($host, $result);
			}
			exit(($retVal & 0x7F) ? ($retVal|0x80) : $retVal >> 8);
		} elsif ($! =~ /No more processes/) {
			sleep 3; redo FORK;
		} else {
			report("WARN", "Can't fork for host $host: $!");
			--$numForks;
		}
	}
}

sub rdoit {
	my ($host, $argument, $SSH, $mode, $ROOT) = @_;
	my ($rsh, $rcmd);
	my $result;

	$SSH ||= "y";
	$rsh = ($SSH =~ /^[nN]/) ? "$rshCmd" : "$sshCmd";

	if ($mode eq "COPY") {
		$rcmd = ($SSH =~ /^[nN]/) ? "$rcpCmd" : "$scpCmd";
		$rcmd .= " $argument";
	} elsif ($mode eq "SQL") {
		$rcmd = "$sqlCmd -h $host -e \"$argument\"";
	} else {
		$rcmd = "$rsh $host $argument";
	}

	if ($ROOT) {
		$rsh = "$sudoCmd $rsh";
		$rcmd = "$sudoCmd $rcmd";
	}

	report("DEBUG", "Command is $rcmd.");

	if (canConnect($host, $rsh)) {
		$result = `$rcmd 2>&1`;
		$? and $retVal = $?;	# set exit code if non-zero
	} else {
		$result = "Can't connect.\n";
		$retVal = 1;		# set non-zero exit code
	}

	return $result;
}

sub printOut {
	my $host = shift;
	my $result = shift;

	if ($outBase) {
		# Use variable filehandle, or else get warnings about closing
		# filehandles that have already been closed.
		# Disable strict refs to use variable filehandle.
		no strict 'refs';
		my $outFile = "$outBase$host";
		my $outFH = "OUT_$host";
		printf "%-${hostFieldLen}s", "$host:";
		if (open $outFH, ">$outFile") {
			print $outFH "$result";
			close $outFH;
			print "\n";
		} else {
			report("WARN", "Can't write $outFile.");
		}
	} elsif ($COMPACT) {
		printf "%-${hostFieldLen}s", "$host:";
		print "$result";
		# Newline, unless one is already there.
		$result =~ /\n$/ or print "\n";
	} else {
		print "##### $host #####\n";
		print "$result\n";
	}
}

sub isValidPathname {
	my $pathname = shift;

	# Pathname should include only slashes, alphanumerics, and a few other
	# kinds of characters. This may be too restrictive, but better safe
	# than sorry.
	$pathname =~ /^[\/\w\.\-\+]+$/ or return 0;

	return 1;
}

sub isValidHostname {
	my $hostname = shift;

	# Hostname should include only alphanumerics (including underscores),
	# hyphens, and dots, and begin with an alphanumeric.
	$hostname =~ /^\w[\w\-\.]*$/ or return 0;

	# Hostname should correspond to a valid IP address.
	gethostbyname $hostname or return 0;

	return 1;
}

sub invalidate {
	my ($var, $name) = @_;
	report("ERR", "$var is not a valid $name");
}

sub canConnect {
	my ($host, $rsh) = @_;
	return unix("$rsh $host /bin/echo 1>/dev/null 2>&1");
}

sub unix {
	# UNIX system calls generally return 0 for success, while Perl treats 0
	# as false. Need to return negation of system call return value.
	my $command = shift;
	return ! system $command;
}

sub report {
	my ($severity, $message) = @_;

	if	($severity eq "ERR")	{ die "$progname: $message\n"; }
	elsif	($severity eq "WARN")	{ warn "$progname: $message\n"; }
	elsif	($severity eq "INFO")	{ print "$progname: $message\n"; }
	elsif	($severity eq "DEBUG")	{ warn "$progname: DEBUG: $message\n"
						if $DEBUG; return 1; }
	else	{ die "$progname: Undefined error. $message\n"; }
}
