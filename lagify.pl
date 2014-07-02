#!/usr/bin/perl -w

##############################################################################
#
# Author
#   Bart Matthesius [BM]
#
# History
#   v0.001 [Bart Matthesius <bamatthe@cisco.com>] 09/02/2013 - Initial version
#
# WARNING:  This tool is the intellectual property of Cariden Technologies
# and is covered by the terms of the mutual non-disclosure agreement.
# The content of this script and the methods employed herein should not be
# shared with third parties except in a manner consistent with the NDA and
# master software license agreement if applicable.
#
###############################################################################

###############################################################################
# Libs
###############################################################################

# Cariden Technologies, Inc. Confidential Information
#
# NOTE: This tool is the intellectual property of Cariden Technologies, Inc.,
# and is provided to you solely under the terms of the Cariden Master Software
# License Agreement (MSLA) or, if applicable, the license agreement between
# Cariden and your company. As such, the content of this script and the methods
# employed herein should not be shared with third parties except in a manner
# consistent with the terms of those agreements. By using this tool you agree
# fully to those terms.
#
# Copyright (c) 2012 Cariden Technologies, Inc.. All rights reserved.

use 5.008000;
use strict;
use warnings;
use English qw(-no_match_vars);
use File::Basename;
use File::Spec::Functions qw(splitpath splitdir catdir catpath catfile updir);
use FindBin;

# XXX These next few subs and the BEGIN block are only needed for Solutions packages that
# XXX are intended to be supported on any platform and/or any environment. For custom
# XXX applications designed for running only on a single environment, then feel free to
# XXX hardcode where ROOT and HOME libraries can be found. It is /much/ easier.
# XXX
# XXX eg, Strip out the portability code and just do this instead:
# XXX use lib '/opt/cariden/software/mate/current/lib/perl';
# XXX use lib '/opt/cariden/lib/perl';
sub _running_from_in_addons {
	my $bin_dir = $FindBin::Bin;
	my ($vol, $dirs, $file) = splitpath($bin_dir, 'no file');
	my @dirs = splitdir($dirs);
	my $bool = grep { $_ eq 'addons' } @dirs;
	return $bool;
}

sub _derive_env_from_addons_dir {
	if (not $ENV{'CARIDEN_HOME'}) {
		my $bin_dir = $FindBin::Bin;
		my ($vol, $dirs, $file) = splitpath($bin_dir, 'no file');
		my @dirs = splitdir($dirs);

		while (@dirs) {
			pop @dirs;
			my $dir      = catdir(@dirs);
			my $mate     = catfile($dir, 'mate');
			my $mate_exe = catfile($dir, 'mate.exe');

			if (-x $mate or -x $mate_exe) {
				$ENV{'CARIDEN_HOME'} ||= catpath($vol, $dir, q{});
				last;
			}
		}

		$ENV{'CARIDEN_HOME'} or die "Could not find MATE Design current release directory\n";
	}

	if (not $ENV{'CARIDEN_ROOT'}) {
		my ($vol, $dirs, $file) = splitpath($ENV{'CARIDEN_HOME'}, 'no file');
		my @dirs = splitdir($dirs);

		while (@dirs) {
			pop @dirs;
			my $dir      = catdir(@dirs);
			my $perl_dir = catdir($dir, 'lib', 'perl');
			my $perl_lib = catpath($vol, $perl_dir, q{});

			if (-d $perl_lib) {
				$ENV{'CARIDEN_ROOT'} ||= catpath($vol, $dir, q{});
				last;
			}
		}
	}

	return 1;
}

sub _find_first_release_in {
	my $release_path = shift;
	my @subdirs      = grep { -d $_ } glob catfile($release_path, q{*}) or return;
	my @releases     = grep { -e catfile($_, 'mate') or -e catfile($_, 'mate.exe') } @subdirs or return;
	my @sorted       = sort @releases;
	my $latest       = pop @sorted;
	$ENV{'CARIDEN_HOME'} ||= $latest;
	return 1;
}

sub _derive_env_from_root_bin {
	if (not $ENV{'CARIDEN_ROOT'}) {
		my $bin_dir = $FindBin::Bin;
		my ($vol, $dirs, $file) = splitpath($bin_dir);
		my @dirs = splitdir($dirs);
		pop @dirs;
		$dirs = catdir(@dirs);
		$ENV{'CARIDEN_ROOT'} ||= catpath($vol, $dirs, q{});
	}

	if (not $ENV{'CARIDEN_HOME'}) {
		my $releases     = catdir($ENV{'CARIDEN_ROOT'}, 'releases');
		my $apps_mate    = catdir($ENV{'CARIDEN_ROOT'}, 'apps', 'mate');
		my $releases_dir = -e $releases ? $releases : -e $apps_mate ? $apps_mate : $ENV{'CARIDEN_ROOT'};

		my $current_release = catdir($ENV{'CARIDEN_ROOT'}, 'current_release');
		my $apps_mate_curr  = catdir($apps_mate, 'current');
		my $current_dir     = -e $current_release ? $current_release : -e $apps_mate_curr ? $apps_mate_curr : undef;

		if ($current_dir) {
			-l $current_dir and $current_dir = readlink $current_dir;
			$ENV{'CARIDEN_HOME'} ||= $current_dir;
		}
		else {
			_find_first_release_in($releases_dir) or die "Could not find any MATE Design installation directory\n";
		}
	}

	return 1;
}

sub _lib_perl {
	my $base = shift;

	defined $base or return;
	length $base  or return;
	-d $base      or return;

	my $lib = catdir($base, 'lib', 'perl');
	-d $lib or return;

	return $lib;
}

my @LIBS;
BEGIN {
	# XXX HERE THERE BE DEMONS! Do not change this code unless you know what you are doing!
	# Ideal:
	# $ENV{'CARIDEN_ROOT'} points to the user's installation directory.
	# $ENV{'CARIDEN_HOME'} points to the directory where the current release of MATE Design is located.
	# If that isn't the case we may have one of two scenarios:
	# We are either in CARIDEN_ROOT/bin, in which case:
	# Installer setup from MATE 5.3+:
	# CARIDEN_HOME = CARIDEN_ROOT/sfw/mate/current
	# Or typical manual setup from MATE 5.2-:
	# CARIDEN_HOME = CARIDEN_ROOT/current_release
	# Or, we might be CARIDEN_HOME/addons/<N sub-dirs>/
	# In which case, CARIDEN_HOME can be easily derived by working upwards
	# and CARIDEN_ROOT can be guessed at by working up from that.

	if ((not exists $ENV{'CARIDEN_ROOT'}) or (not exists $ENV{'CARIDEN_HOME'})) {
		if (_running_from_in_addons()) {
			_derive_env_from_addons_dir();
		}
		else {
			_derive_env_from_root_bin();
		}
	}

	# XXX The order of the libs we add is a little delicate:
	# library directories that are added using 'use lib' are
	# searched in /reverse/ order. So, whatever comes last will
	# be used before what is added first. What we want is to
	# add the script directory itself to take precedence over
	# everything else so that addons can use whatever versions
	# of libraries they are bundled with. Next, we want the
	# CARIDEN_ROOT/lib/perl directory to be searched so that
	# the overall Cariden installation can overide versions of
	# modules that are found in CARIDEN_HOME/lib/perl, which
	# should be searched before anything else that comes with
	# the interpreter. If the above subs couldn't find either
	# CARIDEN_HOME nor CARIDEN_ROOT, then a desperate attempt
	# to is made by including the lib/perl directory parellel
	# to the script's location instead.
	foreach my $dir ($ENV{'CARIDEN_ROOT'}, $ENV{'CARIDEN_HOME'}) {
		my $lib = _lib_perl($dir) or next;
		push @LIBS, $lib;
	}

	if (not @LIBS and my $lib = _lib_perl(catdir($FindBin::Bin, updir()))) {
		push @LIBS, $lib;
	}

	unshift @LIBS, $FindBin::Bin;
}
$EVAL_ERROR and die $EVAL_ERROR;
use lib @LIBS;
# XXX This is the end of the portability code.

use MATE;
use Cariden::Solutions qw(:TYPICAL !debug);
use Getopt::Long;
use Pod::Usage;

# Set Script name & dir variables:
BEGIN {
  use File::Basename;
  use Cwd qw(abs_path);
  use vars qw($VERSION $SCRIPT_NAME $SCRIPT_DIR);
  $VERSION = sprintf('%d.%03d', q$Revision: 0.001 $ =~ m#(\d+)\.(\d+)#);
  $SCRIPT_NAME = basename($0);
  $SCRIPT_DIR = abs_path(dirname($0));
}

###############################################################################
# Define subs
###############################################################################
sub debug;
sub Version;
sub getIfType;

###############################################################################
# Command line options & Usage:
###############################################################################

my %opt;

Getopt::Long::Configure("no_ignore_case");
GetOptions('debug=i'     => \$opt{debug},
           'help|?'      => \$opt{help},
           'verbosity=i' => \$opt{verbosity},
           'plan-file=s' => \$opt{inPlan},
           'out-file=s' => \$opt{outPlan},
           'man'         => \$opt{man},
           'Version'     => \&Version,
           )
    or pod2usage(2);

pod2usage(1) if ($opt{help} || !defined $opt{inPlan});
pod2usage(-exitstatus => 0, -verbose => 2) if $opt{man};

############
# Check that the source plan file:
if (! -r $opt{inPlan} || $opt{inPlan} !~ /.*\.(txt)$/) {
  print "ERROR: could not read plan file or wrong file format. Aborting.\n";
  pod2usage(1);
};

############
#Set some default options:
$opt{debug} = 1 if !defined $opt{debug};
$opt{verbosity} = 40 if !defined $opt{verbosity};
$opt{outPlan} = "out.txt" if !defined $opt{outPlan};

###############################################################################
# Define Var's:
###############################################################################
my $bin = "$ENV{'CARIDEN_HOME'}"."/bin";
my $MATE_SQL = "$bin/mate_sql";
my $inPlan = $opt{inPlan};
my $outPlan = $opt{outPlan};
my $verbosity = $opt{verbosity};

###################################
#                                 #
#             MAIN                #
#                                 #
###################################

debug(1, "Program $0 has started");

############
# Create object for the plan file. NOTE: we need tyo use the outFile as it's already been modified by mate_sql!
my $plan = read_plan_file("$inPlan");

############
# I think it makes sense to do things on a per-node basis. So, the script will loop through a list of all nodes, and get a list of interfaces
# for each of those nodes, rather than simply get all nodes.
my $nodes= $plan->getTable("<Nodes>");

############
# Create an object for the NetIntInterface table:
my $netintinterfaces = $plan->getTable("<NetIntInterfaces>");

############
# Create an object for the Ports table:
my $ports = $plan->getTable("<Ports>");

############
# each row in nodes:
my @n_rows = $nodes->get_rows_where();
foreach my $n_row (@n_rows) {
  my $netintindex = 1;
  my $n_name = $n_row->get_value('Name');
  my $n_vendor = $n_row->get_value('Vendor') || 'unknown';

  ############
  # each row in netintinterfaces:
  my @i_rows = $netintinterfaces->get_rows_where({'Node'=>$n_name});
  foreach my $i_row (@i_rows) {
    my $i_node = $i_row->get_value('Node');
    my $i_interface = $i_row->get_value('Interface');
    my $lagmember = $i_row->get_value('AggregatedInside');
    # For Juniper, L3 interfaces are identified by .0.
    # For Cisco, any interface that is not a LAG member is L3 (since we previously got rid of all unconnected interfaces)
    if ($i_interface =~ /\.\d+$/ || ($n_vendor =~ /cisco/i && !defined($lagmember))) {
      $netintinterfaces->setEntry($i_row,'Type','L3');
    } else {
      $netintinterfaces->setEntry($i_row,'Type','L1');
    }
    my $ifType = getIfType($i_interface);
    if ($ifType != 0) { 
      $netintinterfaces->setEntry($i_row,'NetIntType',$ifType);
    }
    $netintinterfaces->setEntry($i_row,'NetIntIndex',$netintindex);
    $netintindex++;
  }
}


############
# Write the new plan file:
write_plan_file($plan, $opt{outPlan}) or fatal();

debug(1, "Program $0 has ended");

END {
	exit 0;
}

###################################
#
# SUB's
#
###################################

#try to find the appropriate ifType value for the interface. Only the most common ones:
sub getIfType {
  my $ifName = shift;
  my $ifType = 0;
  # Ethernet types:
  if ($ifName =~ /(ge-|fe-|xe-|et-x|GigE|Ethernet)/) {
    if ($ifName =~ /(\.\d+)$/) {
      $ifType = 135;
    } else {
      $ifType = 6;
    }
  }
  # POS:
  if ($ifName =~ /^POS/) {
    $ifType = 171;
  }
  # SONET:
  if ($ifName =~ /^so-/) {
    if ($ifName =~ /(\.\d+)$/) {
      $ifType = 92;
    } else {
      $ifType = 39;
    }
  }
  # LSI:
  if ($ifName =~ /^lsi/i) {
    if ($ifName =~ /(\.\d+)$/) {
      $ifType = 53;
    } else {
      $ifType = 150;
    }
  }
  # aggregated ethernet:
  if ($ifName =~ /^(ae\d+|port-channel)/i) {
    $ifType = 161;
  }
  return $ifType;
}

sub Version {
  print STDERR "$SCRIPT_NAME - v$VERSION\n";
  exit;
}

sub debug {
  my $level = shift;
  return if $level > $opt{debug};
  my $message = join(' ',@_);
  chomp $message;
  my $date = gmtime();
  printf STDERR "%s [%3.3d]: %s\n", $date, $level, $message;
}

=head1 SYNOPSIS

template.pl [options]

 Options:
   -help            brief help message
   -man             full documentation
   -debug n         the higher n is the more info you will see (5)
   -Version         Prints version info and exits

=head1 OPTIONS

=over 8

=item B<-help>

Print a brief help message and exits.

=item B<-man>

Prints the manual page and exits.

=item B<-debug i>

default: 1

Give program flow information. The higher the value the more info is provided. 0 is silent (no debugging info).

=back

=head1 DESCRIPTION

B<lagify.pl> will, where it can, set the following in the NetIntInterfaces table:

  -set a unique (per node) NetIntIndex
  -set NetIntType to the IfType (see the IF-MIB)
  -set Type to either L1 or L3
  -set Aggregated to T or F
  -set AggregatedInside to the relevant interface
  -set OnTopOf to the relevant interface

=head1 TODO

=over 8

=item * Nothing

=back

=cut
