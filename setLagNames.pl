#!/usr/bin/perl -w

##############################################################################
#
# Author
#   Bart Matthesius [BM]
#
# Description
#
# History
#   v0.001 [Bart Matthesius <bamatthe@cisco.com>] 10/04/2013 - Initial version
#
# WARNING:  This tool is the intellectual property of Cariden Technologies
# and is covered by the terms of the mutual non-disclosure agreement.
# The content of this script and the methods employed herein should not be
# shared with third parties except in a manner consistent with the NDA and
# master software license agreement if applicable.
#
# NOTE: Script needs to run BEFORE:
#          - demands are added
#          - matelivify.sh
###############################################################################
#          - ae0
#          - bundle-ethernet1
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

use Data::Dumper;
use Getopt::Long;
use Pod::Usage;use MATE;
use Cariden::Solutions qw(:TYPICAL);

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
sub Version;
sub DefineModifiers;
sub Capacities;

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

pod2usage(1) if $opt{help};
pod2usage(-exitstatus => 0, -verbose => 2) if $opt{man};

############
#Set some default options:
$opt{debug} = 1 if !defined $opt{debug};
$opt{verbosity} = 40 if !defined $opt{verbosity};
$opt{outPlan} = "out.txt" if !defined $opt{outPlan};

###############################################################################
# Define Var's:
###############################################################################
my $bin = "$ENV{'CARIDEN_HOME'}"."/bin";
my $inPlan = $opt{inPlan};
my $verbosity = $opt{verbosity};

###################################
#                                 #
#             MAIN                #
#                                 #
###################################

info("Program $0 has started");

############
# Create object for the plan file:
my $plan = read_plan_file("$inPlan");

############
# Create an object for several tables:
my $interfaces = $plan->getTable("<Interfaces>");
my $nodes = $plan->getTable("<Nodes>");
my $circuits = $plan->getTable("<Circuits>");
my $ports = $plan->getTable("<Ports>");
my $namedpathhops = $plan->getTable("<NamedPathHops>");
my $interfaceipaddresses = $plan->getTable("<InterfaceIPAddresses>");
my $plotlayoutelements = $plan->getTable("<PlotLayoutElements>");
my $actualpathhops = $plan->getTable("<ActualPathHops>");

############
# each row in nodes:
my @n_rows = $nodes->get_rows_where();
foreach my $n_row (@n_rows) {
  my $port = 0;
  my $n_name = $n_row->get_value('Name');
  my $n_vendor = $n_row->get_value('vendor');
  # each interface on the current node: 
  if (!defined $n_vendor) { 
    info("Couldn't determine Vendor for node $n_name. moving on.");
    next;
  }
  my @i_rows = $interfaces->get_rows_where({'Node'=>$n_name});
  foreach my $i_row (@i_rows) {
    my $i_interface = $i_row->get_value('Interface');
    my $i_capacity = $i_row->get_value('Capacity');
    # rename aggregation interfaces based on vendor. This assumes the default prefix as applied by the "Bundle parallel circuits" addon:
    if ($i_interface =~ /bundle-/) {
      my $newIfName = $i_interface;
      if ($n_vendor eq 'Cisco') {
        $newIfName =~ s/bundle-/Bundle-Ether/g;
        info("Found Lag $i_interface on Cisco device $n_name, changing 'bundle-' to 'Port-channel'");
      } elsif ($n_vendor eq 'Juniper') {
        $newIfName = $newIfName . '.0';
        $newIfName =~ s/bundle-/ae/g;
        info("Found Lag $i_interface on Juniper device $n_name, changing 'bundle-' to 'ae'");
      } else {
        info("Found Lag $i_interface but could not determine Venodor. Moving on.");
      }
      if ($newIfName ne $i_interface) {
        my @rows;
        $interfaces->setEntry($i_row,'Interface',$newIfName);
        @rows = $circuits->get_rows({'NodeA'=>$n_name, 'InterfaceA'=>$i_interface});
        foreach my $row (@rows) {
          $circuits->setEntry($row,'InterfaceA',$newIfName);
        }
        @rows = $circuits->get_rows({'NodeB'=>$n_name, 'InterfaceB'=>$i_interface});
        foreach my $row (@rows) {
          my $c_tag = $row->get_value('Tags');
          $circuits->setEntry($row,'InterfaceB', $newIfName) if (!defined $c_tag || $c_tag eq "");
          $circuits->setEntry($row,'Tags', "boo" . $newIfName) if (!defined $c_tag || $c_tag eq "");
        }
        @rows = $plotlayoutelements->get_rows({'ElementNode'=>$n_name, 'ElementInterface'=>$i_interface});
        foreach my $row (@rows) {
          $plotlayoutelements->setEntry($row,'ElementInterface',$newIfName);
        }
        @rows = $namedpathhops->get_rows({'Node'=>$n_name, 'Interface'=>$i_interface});
        foreach my $row (@rows) {
          $namedpathhops->setEntry($row,'Interface',$newIfName);
        }
        @rows = $actualpathhops->get_rows({'Node'=>$n_name, 'Interface'=>$i_interface});
        foreach my $row (@rows) {
          $actualpathhops->setEntry($row,'Interface',$newIfName);
        }
        @rows = $interfaceipaddresses->get_rows({'Node'=>$n_name, 'Interface'=>$i_interface});
        foreach my $row (@rows) {
          $interfaceipaddresses->setEntry($row,'Interface',$newIfName);
        }
        @rows = $ports->get_rows({'Node'=>$n_name, 'Interface'=>$i_interface});
        foreach my $row (@rows) {
          $ports->setEntry($row,'Interface',$newIfName);
        }
      }
    }
  }
}

############
## Remove 'boo' identifier
my $plan_str =  $plan->to_string();
$plan_str    =~ s/boo//gixmso;
$plan        =  read_plan_file(\$plan_str);

# Write the new plan file:
write_plan_file($plan, $opt{outPlan});

info("Program $0 has ended");
exit 0;

###################################
#
# SUB's
#
###################################

sub Version {
  print STDERR "$SCRIPT_NAME - v$VERSION\n";
  exit;
}

=head1 SYNOPSIS

setIFNames.pl [options]

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

B<setIfNames.pl> does the following:

=head1 TODO

=over 8

=item * Nothing

=back

=cut
