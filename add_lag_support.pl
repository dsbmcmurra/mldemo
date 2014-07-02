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

use File::Spec::Functions qw(catfile rel2abs splitpath);
use Cariden::Solutions qw(:TYPICAL);
use Cariden::Solutions::Constants qw($EMPTY_STRING $SINGLE_TAB $NEWLINE_RE $SINGLE_DASH);
use Cariden::Solutions::MATE::TableExtract qw(table_extract);
use Const::Fast qw(const);
our $VERSION = '1.0.0';

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
	my $extract    = table_extract($args->{'plan-file'}, [qw(Interfaces Ports)]) or fatal();
	my $interfaces = $extract->get_table('<Interfaces>');
	my $ports      = $extract->get_table('<Ports>');
	add_lag_support($plan, $interfaces, $ports); 
	write_plan_file($plan, $args->{'out-file'}) or fatal();

	return 0;
}

sub add_lag_support{
	trace();
	my $plan       = shift;
	my $interfaces = shift;
	my $ports      = shift;

	my $port_traffic = $plan->get_table('<PortTraffic>');
	my @port_rows    = $ports->rows();
	foreach my $port_row (@port_rows){
		my $node  = $port_row->get_value('Node');
		my $port  = $port_row->get_value('Port');
		$port_traffic->append()->set_values({
			Node => $node,
			Port => $port,
		});
	}

	## Below sets PortTraffic (Lag member) traffic equal to the total lag logical traffic divided by the number of lag members:
## BEGIN;
## CREATE TEMP TABLE TMP AS SELECT count(P.Interface) AS NumLagMembers, I.Node AS Node, I.Interface AS Interface, P.Port AS Port, I.TraffSim AS TotalLagTraff, 0 AS LagTraff FROM Attached.Interfaces AS I,Ports AS P WHERE P.Node = I.Node AND I.Interface = P.Interface GROUP BY I.Node, P.Port;
## UPDATE tmp SET NumLagMembers = (SELECT COUNT(Ports.Port) FROM Ports GROUP BY Node, Interface);
## UPDATE tmp SET LagTraff = CAST(TotalLagTraff AS INTEGER) / NumLagMembers;
## UPDATE PortTraffic SET TraffMeas = (SELECT LagTraff FROM tmp WHERE tmp.Node = PortTraffic.Node AND tmp.Port = PortTraffic.Port);
## DROP TABLE tmp;
## COMMIT;
	foreach my $port_traff_row ( $plan->get_table('<PortTraffic>')->rows() ){
		my $node = $port_traff_row->get_value('Node');
		my $port = $port_traff_row->get_value('Port');

		my ($port_row)      = $ports->get_rows_where({'Node'=>$node, 'Port'=>$port});
		my $int             = $port_row->get_value('Interface');
		my ($int_row)       = $interfaces->get_rows_where({'Node'=>$node, 'Interface'=>$int});

		my $total_lag_traff = $int_row->get_value('TraffSim');
		my $num_lag_members = $ports->get_rows_where({'Node'=>$node, 'Interface'=>$int});

		my $lag_traff = $total_lag_traff / $num_lag_members;
		$port_traff_row->set_value('TraffMeas'=> $lag_traff);
	}


	## Now that the Ports and PortTraffic tables are sorted we can update into NetInt:
	my $net_int_interfaces = $plan->get_table('NetIntInterfaces');
	foreach my $port_row ($ports->rows()) {
		my $node     = $port_row->get_value('Node');
		my $capacity = $port_row->get_value('Capacity');
		my $port     = $port_row->get_value('Port');
		$port       =~ s/[.]0//xmsoig;

		$net_int_interfaces->append()->set_values({
			Node        => $node,
			Interface   => $port,
			PolicyGroup => 'Default',
			Capacity    => $capacity,
		});
	}

	## INSERT INTO NetIntInterfaceTraffic (Node, Interface, TrafficLevel, Queue, TraffMeas) SELECT Node, Port,TrafficLevel, Queue, TraffMeas FROM PortTraffic;
	my $net_int_interface_traffic_table = $plan->get_table('NetIntInterfaceTraffic');
	foreach my $port_traff_row ( $port_traffic->rows() ){
		my $node       = $port_traff_row->get_value('Node');
		my $port       = $port_traff_row->get_value('Port');
		my $traff_lvl  = $port_traff_row->get_value('TrafficLevel');
		my $queue      = $port_traff_row->get_value('Queue');
		my $traff_meas = $port_traff_row->get_value('TraffMeas');

		$net_int_interface_traffic_table->append()->set_values({
			Node         => $node,
			Interface    => $port,
			TrafficLevel => $traff_lvl,
			Queue        => $queue,
			TraffMeas    => $traff_meas,
		});
	}

	## Create interface entries in NetIntInterfaceTraffic:
	foreach my $row ( $interfaces->rows() ){
		my $node        = $row->get_value('Node');
		my $interface   = $row->get_value('Interface');
		my $traff_sim   = int($row->get_value('TraffSim'));
		my $packets_out = int($traff_sim * 1000000 / 4608);

		$net_int_interface_traffic_table->append()->set_values({
			Node              => $node,
			Interface         => $interface,
			TraffMeas         => $traff_sim,
			NetIntInTraffMeas => 0,
			NetIntPacketsOut  => $packets_out,
			NetIntPacketsIn   => 0,
		});
	}

	## Some additional updates to set lag related columns. This is needed to ensure the context menu's and Interface Type assignment works ok:
	## WARNING: the order in which these are applied matters!!
	foreach my $nii ($net_int_interfaces->rows()) {
		my $node = $nii->get_value('Node');
		my $int  = $nii->get_value('Interface');

		if($nii->get_value('Interface') =~ qr'^Port-chan|^Bundle-|^ae[0-9]'){
			$nii->set_value(Aggregated=>'T');
		}
		else{
			$nii->set_value(Aggregated=>'F');
		}

		my $matching_ports_row = $ports->get_rows_where([{'Node'=>$node},{'Port'=>$int}]);
		## Confusing line is confusing here is the original SQL
		## UPDATE NetIntInterfaces SET Type = 'L3' WHERE Interface REGEXP '\.0$|^Port-chan|^Bundle-' AND Node || Interface NOT IN (SELECT Node || Port FROM Ports);
		if($matching_ports_row eq 0) {
			$nii->set_value(Type=>'L1');
		}
		elsif( $nii->get_value('Interface') =~ qr'\.0$|^Port-chan|^Bundle-' ){
			$nii->set_value(Type=>'L3');
		}
		else{
			$nii->set_value(Type=>'L1');
		}

		## --LAG OnTopOf:
		my ($port_row) = $ports->get_rows_where({Node=>$node, Interface=>$int});
		if($nii->get_value('Interface') =~ qr'[.]0' and $port_row){
			my $port   = $port_row->get_value('Port');
			$nii->set_value(OnTopOf=>$port);
		}
		else{
			$nii->set_value(OnTopOf=>undef);
		}

		## --Ind. OnTopOf:
		my ($other_nii_row) = $net_int_interfaces->get_rows_where({Node=>$node, Interface=>$int});
		if($other_nii_row and $nii->get_value('Interface') =~ qr'[.]0' and $nii->get_value('Type') eq 'L3'){
			my $other_int   = $other_nii_row->get_value('Interface');
			$other_int =~ s/[.]0//;
			$nii->set_value(OnTopOf=>$other_int);
		}
		else{
			$nii->set_value(OnTopOf=>undef);
		}

		## --AggregatedInside for Lag Members:
		my @matches = $ports->get_rows_where({Node=>$node, Port=>qr/$int/xms});
		my $ai;
		my $port;
		foreach my $row (@matches){
			$port_row = $row;
			$port = $row->get_value('Port');
			$port eq $int and last;
			$port =~ s/[.]0//xsmoig;
			$port eq $int and last;
			$port = '';
		}
		if( $port ){
			$ai = $port_row->get_value('Interface');
			$ai =~ s/[.]0//xmsoig;
			$nii->set_value(AggregatedInside=>$ai);
		}
	}


	## --Set interfaces and NetInInterfaces.Capacity where needed:
## UPDATE Interfaces SET Capacity = (SELECT CapacitySim FROM Attached.Interfaces AS a WHERE Interfaces.Node = a.Node AND Interfaces.Interface = a.Interface) WHERE Capacity IS NULL;
	foreach my $int ( $plan->get_table('<Interfaces>')->rows() ){
		$int->get_value('Capacity') and next;
		my ($other_int) = $interfaces->get_rows_where({Node=>$int->get_value('Node'), Interface=>$int->get_value('Interface')}) or next;
		$int->set_value('Capacity'=>$other_int->get_value('CapacitySim'));
	}
## UPDATE NetIntInterfaces SET Capacity = (SELECT CapacitySim FROM Attached.Interfaces AS a WHERE NetIntInterfaces.Node = a.Node AND NetIntInterfaces.Interface = a.Interface) WHERE Capacity IS NULL;
	foreach my $nii ( $net_int_interfaces->rows() ){
		$nii->get_value('Capacity') and next;
		my ($other_int) = $interfaces->get_rows_where({Node=>$nii->get_value('Node'), Interface=>$nii->get_value('Interface')}) or next;
		$nii->set_value('Capacity'=>$other_int->get_value('CapacitySim'));
	}

## UPDATE NetIntInterfaces SET Capacity = (SELECT CapacitySim FROM Attached.Interfaces AS a WHERE NetIntInterfaces.Node = a.Node AND NetIntInterfaces.Interface = REPLACE(a.Interface, '.0', '')) WHERE Capacity IS NULL;
	foreach my $nii ( $net_int_interfaces->rows() ){
		$nii->get_value('Capacity') and next;
		my $interface   = $nii->get_value('Interface');
		$interface =~ s/\.0//g;
		my ($other_int) = $interfaces->get_rows_where({Node=>$nii->get_value('Node'), Interface=>$interface}) or next;
		$nii->set_value('Capacity'=>$other_int->get_value('CapacitySim'));
	}

}

__END__

