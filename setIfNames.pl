#!/usr/bin/perl -w

##############################################################################
#
# Author
#   Bart Matthesius [BM]
#
# Description
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
# NOTE: Script needs to run BEFORE:
#          - demands are added
#          - ports / port ccts are added
#          - matelivify.sh 
# Script doesn't rename lags:
#          - ae0
#          - bundle-ethernet1
#          - Port-channel1
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

use Getopt::Long;
use MATE;
use Cariden::Solutions qw(:TYPICAL);
use Data::Dumper;

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
           'overwrite-all=s' => \$opt{overwrite},
           'man'         => \$opt{man},
           'Version'     => \&Version,
           )
    or pod2usage(2);

pod2usage(1) if $opt{help};
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
$opt{overwrite} = 'true' if !defined $opt{overwrite};

###############################################################################
# Define Var's:
###############################################################################
my $bin = "$ENV{'CARIDEN_HOME'}"."/bin";
my $TABLE_REPLACE = "\"$bin/table_replace\"";
my $DMD_DEDUCT = "\"$bin/dmd_deduct\"";
my $inPlan = $opt{inPlan};
my $verbosity = $opt{verbosity};
my $capacities = defineCapacities();

###################################
#                                 #
#             MAIN                #
#                                 #
###################################

notice("Program $0 has started");
debug(Dumper $capacities);

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
  my $card = 0;
  my $slot = 0;
  my $port = 0;
  my $n_name = $n_row->get_value('Name');
  my $n_vendor = $n_row->get_value('vendor');
  # each interface on the current node: 
  if (!defined $n_vendor) { 
    debug ("Couldn't determine Vendor for node $n_name. moving on.");
    next;
  }
print "Processing Node: $n_name\n";
  my @i_rows = $interfaces->get_rows_where({'Node'=>$n_name});
  foreach my $i_row (sort {$a->to_string() cmp $b->to_string()} @i_rows) {
    my $i_interface = $i_row->get_value('Interface');
    my $i_capacity = $i_row->get_value('Capacity');
    my $i_tags = $i_row->get_value('Tags') || '';
    # Unless specifically requested, only overwrite MD 'to_' interface names:
    next if $i_interface !~ /to_/ && $opt{overwrite} ne 'true';
    if (!defined $i_capacity) { 
      debug ("{$n_name|$i_interface} doesn't have a capacity configured. moving on.");
      next;
    }

    my @linerates = keys %{$capacities->{$n_vendor}};
    foreach my $linerate ( sort @linerates ) {
      my $ifPrefix = $capacities->{$n_vendor}{$linerate};

      # we'll attempt to match if the capacity is approximately right. Here we use a 10% margin:
      my $margin = $linerate / 10;
      if (int($i_capacity) > ($linerate - $margin) && int($i_capacity) < ($linerate + $margin)) {
        my @rows;
        my $newIfName;
        $newIfName = 'boo' . $ifPrefix . $card . "/" . $slot . "/" . $port;
        # We'll give the Juniper logical interfaces a trailing .0 in their name
        # unless they are tagged to be part of a LAG later on, in which case we
        # will keep the name without a .0 so they don't have crappy Ports entries later
        if ($n_vendor =~ /juniper/i && $i_tags !~ /LAG/) { $newIfName = $newIfName . '.0'; }

        debug("Determined new interface name to be $newIfName (was $i_interface)");
print "	Setting $newIfName\n";
        # some very basic card/slot/port determination:
        $port++;
        if ($port > 4) { $port = 0; $slot++; }
        if ($slot > 2) { $slot = 0; $card++; }

        # Set the interface name in the Interfaces table:
        $interfaces->setEntry($i_row,'Interface',$newIfName);

        # Translate this interface entry in the Circuits table
	# Only one of the two below loops will execute since the interface is 
	# either the A side or the B side of the circuit but not both.
        @rows = $circuits->get_rows({'NodeA'=>$n_name, 'InterfaceA'=>$i_interface});
        foreach my $row (@rows) {
          $circuits->setEntry($row,'InterfaceA',$newIfName);
        }
        @rows = $circuits->get_rows({'NodeB'=>$n_name, 'InterfaceB'=>$i_interface});
        foreach my $row (@rows) {
          $circuits->setEntry($row,'InterfaceB',$newIfName);
        }


        # Set the Port interface:
        @rows = $ports->get_rows({'Node'=>$n_name, 'Interface'=>$i_interface});
        foreach my $row (@rows) {
          $ports->setEntry($row,'Interface',$newIfName);
        }

        # Fix PlotLayoutElements:
        @rows = $plotlayoutelements->get_rows({'ElementNode'=>$n_name, 'ElementInterface'=>$i_interface});
        foreach my $row (@rows) {
          $plotlayoutelements->setEntry($row,'ElementInterface',$newIfName);
        }

        # NamedPathHops:
        @rows = $namedpathhops->get_rows({'Node'=>$n_name, 'Interface'=>$i_interface});
        foreach my $row (@rows) {
          $namedpathhops->setEntry($row,'Interface',$newIfName);
        }

        # ActualPathHops:
        @rows = $actualpathhops->get_rows({'Node'=>$n_name, 'Interface'=>$i_interface});
        foreach my $row (@rows) {
          $actualpathhops->setEntry($row,'Interface',$newIfName);
        }

        # InterfaceIPAddresses:
        @rows = $interfaceipaddresses->get_rows({'Node'=>$n_name, 'Interface'=>$i_interface});
        foreach my $row (@rows) {
          $interfaceipaddresses->setEntry($row,'Interface',$newIfName);
        }
        debug ("{$n_name|$i_interface}'s capacity [$i_capacity] fits within the $linerate margin\n");
      } else {
        debug ("{$n_name|$i_interface}'s capacity [$i_capacity] doesn't fit within the $linerate margin\n");
      }
    }
    debug("node: $n_name - vendor: $n_vendor - int: $i_interface - capacity: $i_capacity\n");
  }
}

## Remove 'boo' identifier
my $plan_str =  $plan->to_string();
$plan_str    =~ s/boo//gixmso;
$plan        =  read_plan_file(\$plan_str);

############
# Write the new plan file:
write_plan_file($plan, $opt{outPlan});

notice("Program $0 has ended");



###################################
#
# SUB's
#
###################################

sub defineCapacities {
  my $hashref;
  $hashref->{'Cisco'}->{100} = 'FastEthernet';
  $hashref->{'Cisco'}->{1000} = 'GigabitEthernet';
  $hashref->{'Cisco'}->{10000} = 'TenGigE';
  $hashref->{'Cisco'}->{100000} = 'HundredGigE';
  $hashref->{'Cisco'}->{34} = 'Serial';
  $hashref->{'Cisco'}->{45} = 'Serial';
  $hashref->{'Cisco'}->{155} = 'POS';
  $hashref->{'Cisco'}->{622} = 'POS';
  $hashref->{'Cisco'}->{2488} = 'POS';
  $hashref->{'Cisco'}->{40000} = 'POS';
  $hashref->{'Juniper'}->{100} = 'fe-';
  $hashref->{'Juniper'}->{1000} = 'ge-';
  $hashref->{'Juniper'}->{10000} = 'xe-';
  $hashref->{'Juniper'}->{100000} = 'et-';
  $hashref->{'Juniper'}->{45} = 't3-';
  $hashref->{'Juniper'}->{34} = 'e3-';
  $hashref->{'Juniper'}->{155} = 'so-';
  $hashref->{'Juniper'}->{622} = 'so-';
  $hashref->{'Juniper'}->{2488} = 'so-';
  $hashref->{'Juniper'}->{40000} = 'so-';
  return $hashref;
}

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
