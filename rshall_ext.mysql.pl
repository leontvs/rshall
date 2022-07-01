#!/usr/bin/perl -w
#
# rshall_ext.mysql - Extract host info from MySQL DB for rshall use.
#
# Copyright (c) 2008 Occam's Razor. All rights reserved.
#
# See the LICENSE file distributed with this code for restrictions on its use
# and further distribution.
# Original distribution available at <http://www.occam.com/tools/>.
#
# $Id: rshall_ext.mysql.pl,v 1.1 2010/04/23 01:39:21 leonvs Exp $
#

use strict;

use DBI;

# global variables
my $DEBUG = 0;
my $progname = $0; $progname =~ s/.*\///;
my $dbType = "mysql";
my $dbName = "database";
my $dbHost = "localhost";
my $dbPort = "3306";
my $dbUser = "ro_user";
my $dbPass = "passwd";
my $db = "DBI:$dbType:$dbName:$dbHost:$dbPort";

my $dbh = DBI->connect($db, $dbUser, $dbPass,
		{ PrintError => 0, AutoCommit => 1 }) or
	report("ERR", "Couldn't connect to $db: $DBI::errstr");

# This example uses a table named "systems" with fields as given in the SELECT
# statement below.
my $sth = $dbh->prepare("
	SELECT host,os,os_rel,make,model,loc,comments
	FROM systems ORDER BY loc,host") or
	report("ERR", "Couldn't read from $db: $DBI::errstr");

$sth->execute or report("ERR", "Couldn't read from $db: $DBI::errstr");

while (my ($host, $os, $os_rel, $make, $model, $loc, $comments) = $sth->fetchrow_array) {
	# Output fields are separated by (one or more) tabs, and every field
	# must have a non-tab character in it.
	$comments ||= "?";	# default if comments field is empty
	print "$host\t$os $os_rel\t$make $model\t$loc\t$comments\ty\n";
}

$dbh->disconnect;

sub report {
	my ($severity, $message) = @_;

	if	($severity eq "ERR")	{ die "$progname: $message\n"; }
	elsif	($severity eq "WARN")	{ warn "$progname: $message\n"; }
	elsif	($severity eq "INFO")	{ print "$progname: $message\n"; }
	elsif	($severity eq "DEBUG")	{ warn "$progname: DEBUG: $message\n"
						if $DEBUG; }
	else	{ die "$progname: Undefined error. $message\n"; }
}
