#!/usr/bin/perl
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

use File::Spec::Functions qw(catfile);
use Cariden::Solutions qw(:TYPICAL);
use Cariden::Solutions::Constants qw($EMPTY_STRING $SINGLE_TAB $NEWLINE_RE $SINGLE_DASH);
use Cariden::Solutions::MATE::TableExtract qw(table_extract);
use Const::Fast qw(const);
our $VERSION = '1.0.0';
const(my $MILLION => 1_000_000);
const(my $DIVISOR => 4608);
const(my $MAGIC_NUMBER => $MILLION / $DIVISOR); # XXX Ask Rached or Bart what this number means.
exit main();
sub main {
	my $app = application(
		meta_information({}),
		app_flags(
			required_flags(
				flag('plan-file', {data_type=>'srcplan'}),
				flag('out-file',  {data_type=>'wrtfile'}),
			),
		),
	) or fatal();
	my $args = read_command_line($app) or fatal();
	my $plan       = read_plan_file($args->{'plan-file'}) or fatal();
	my $extract    = table_extract($args->{'plan-file'}, [qw(Interfaces Ports LSPs)]) or fatal();
	my $interfaces = $extract->get_table('<Interfaces>');
	my $lsps       = $extract->get_table('<LSPs>');
	my $ports      = $extract->get_table('<Ports>');

	## --Copy Lag logical traffic to Lag physical:
## UPDATE NetIntInterfaceTraffic SET NetIntInTraffMeas = (SELECT CAST(TraffSim AS INTEGER) FROM Attached.Interfaces AS a WHERE NetIntInterfaceTraffic.Node = a.RemoteNode AND (NetIntInterfaceTraffic.Interface = a.RemoteInterface OR REPLACE(NetIntInterfaceTraffic.Interface, '.0', '') = a.RemoteInterface));
	my $niit = $plan->get_table('<NetIntInterfaceTraffic>');
	foreach my $row ($niit->rows()) {
		my $node = $row->get_value('Node');
		my $int  = $row->get_value('Interface');

		my $alt_int     =  $int;
		$alt_int        =~ s/[.]0//xsmoig;
		my ($interface) =  $interfaces->get_rows_where({RemoteNode => $node, RemoteInterface => [$int, $alt_int]}) or next;
		my $traff_sim   =  $interface->get_value('TraffSim');

		$row->set_values({NetIntInTraffMeas => $traff_sim});
	}

## INSERT INTO NetIntInterfaceTraffic (Node, Interface, TraffMeas, NetIntInTraffMeas, NetIntPacketsOut, NetIntPacketsIn) SELECT Node, REPLACE(Interface, '.0', ''), TraffMeas, NetIntInTraffMeas, NetIntPacketsOut, NetIntPacketsIn FROM NetIntInterfaceTraffic  WHERE Interface REGEXP '\.0';
	foreach my $row ($niit->rows()) {
		my $node     = $row->get_value('Node');
		my $int      = $row->get_value('Interface');
		$int =~ m/[.]0/xsmo or next;

		my $new_int= $int;
		$new_int  =~ s/[.]0//xsmoig;

		my $traff_meas    = $row->get_value('TraffMeas');
		my $nii_traffmeas = $row->get_value('NetIntInTraffMeas');

		$niit->append()->set_values({
			Node              => $node,
			Interface         => $new_int,
			TraffMeas         => $traff_meas,
			NetIntInTraffMeas => $nii_traffmeas,
		});
	}
## --Set NetIntPacketsIn:
## UPDATE NetIntInterfaceTraffic SET NetIntPacketsIn = CAST(NetIntInTraffMeas * 1000000 / 4608 AS INTEGER), NetIntPacketsOut = CAST(TraffMeas * 1000000 / 4608 AS INTEGER);
	foreach my $row ($niit->rows()) {
		my $traff_meas    = $row->get_value('TraffMeas');
		my $nii_traffmeas = $row->get_value('NetIntInTraffMeas');
		my $packets_in    = $nii_traffmeas ? int($nii_traffmeas * 1000000 / 4608) : undef;
		my $packets_out   = $traff_meas    ? int($traff_meas    * 1000000 / 4608) : undef;

		$row->set_values({
			NetIntPacketsIn  => $packets_in,
			NetIntPacketsOut => $packets_out,
		});
	}

	## --Set the interface descriptions:
## UPDATE Interfaces SET Description = (SELECT 'To ' || RemoteNode || ' ' || RemoteInterface FROM Attached.Interfaces as a WHERE Interfaces.Node = a.Node AND Interfaces.Interface = a.Interface);
	my $local_interfaces = $plan->get_table('<Interfaces>');
	foreach my $row ($local_interfaces->rows()) {
		my $node        = $row->get_value('Node');
		my $int         = $row->get_value('Interface');
		my ($other_row) = $interfaces->get_rows_where({Node=>$node, Interface=>$int});
		my $remote_node = $other_row->get_value('RemoteNode');
		my $remote_int  = $other_row->get_value('RemoteInterface');
		my $description = "To $remote_node $remote_int";
		$row->set_value(Description => $description);
	}

## UPDATE NetIntInterfaces SET Description = (SELECT Description FROM Interfaces WHERE Interfaces.Node = NetIntInterfaces.Node AND Interfaces.Interface = NetIntInterfaces.Interface);
	foreach my $row ($plan->get_table('<NetIntInterfaces>')->rows()) {
		my $node        = $row->get_value('Node');
		my $int         = $row->get_value('Interface');
### XXX get_rows where not getting
		my ($other_row) = $local_interfaces->get_rows_where({Node=>$node, Interface=>$int}) or next;
		my $description = $other_row->get_value('Description');
		$row->set_value(Description => $description);
	}


	## --Let's not use cct names:
	foreach my $row ($plan->get_table('<Circuits>')->rows()) {
		$row->set_value(Name => undef);
	}




	## --Set errors and discards. randonly select 1 / 50 ccts to error or discard, then update a random value:
	foreach my $row ($plan->get_table('NetIntInterfaceTraffic')->rows()) {
		if(rand(50) <= 1){
			$row->set_value(NetIntDropPacketsOut => int(rand(5)+5));
		}
		if(rand(50) <= 1){
			$row->set_value(NetIntErrorPacketsIn => int(rand(5)+5));
		}
	}


	## --And finally, set admin & operstatus to 'up':
	foreach my $row ($plan->get_table('<NetIntInterfaces>')->rows()) {
		$row->set_values({NetIntAdminStatus=>'up', NetIntOperstatus=>'up'});
	}

	write_plan_file($plan, $args->{'out-file'}) or fatal();

	return 0;
}
