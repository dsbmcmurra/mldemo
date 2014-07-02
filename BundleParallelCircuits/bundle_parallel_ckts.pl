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


use Cariden::Solutions qw(:TYPICAL);
use Cariden::Solutions::MATE::Report qw(:ALL);
use Cariden::Solutions::Constants qw($EMPTY_STRING $SINGLE_DASH $NEWLINE_RE);
our $ADDON_NAME = 'Bundle Parallel Circuits';
our $VERSION = '1.1.1';
exit main();
sub main {
	my $app = application(
		meta_information({
			is_addon    => 1,
			name        => $ADDON_NAME,
			description => 'Create bundled interfaces based on node-parallel circuits from user selected interfaces.\\nMove constituent interfaces to ports table and circuits to PortCircuits table.',
		}),
		app_flags(
			required_flags(
				flag('plan-file', {data_type=>'srcplan', description=>'Input plan file'}),
				flag('out-file',  {data_type=>'wrtfile', description=>'Output plan file'}),
				flag('interface-list-file', {addon_prompt=>'Interface Selection', addon_widget=>'TableSelection', addon_table=>'Interfaces', data_type=>'srcfile'})
			),
			optional_flags(
				flag('bundled-if-prefix', {
					data_type    => 'string',
					addon_prompt => 'Name prefix for new bundled interfaces created.',
					default      => 'bundle-',
					order        => 4,
				}),
				flag('interface-tag', {
					data_type    => 'string',
					addon_prompt => 'Optional interface tag used to select candidates for bundling.',
					order        => 5,
				}),
				flag('igp-metrics', {
					order        => 6,
					addon_prompt =>'IGP metrics for bundled interfaces',
					data_type    =>'string',
					addon_widget =>'DropDown',
					default      =>'Choose min',
					allow        =>['Choose min', 'Require equal'],
				}),
				flag('te-metrics', {
					order        => 7,
					addon_prompt =>'TE metrics for bundled interfaces',
					data_type    =>'string',
					addon_widget =>'DropDown',
					default      =>'Choose min',
					allow        =>['Choose min', 'Require equal'],
				}),
			),
		),
	) or fatal('Error while constructing application meta-data');
	my $args = read_command_line($app) or fatal('Could not process command line arguments');
	my $plan = read_plan_file($args->{'plan-file'}) or fatal('Could not read plan-file');
	my $report_target  = ($args->{'out-file'} || $args->{'report-dir'}) or fatal();
	progress('20');
	my ($bundle_groups, $tot_ifs) = find_bundle_groups($args, $plan);
    progress('60');
	my $results = create_bundles($bundle_groups, $tot_ifs, $plan, $args);
	progress('80');
	my $sections = report_sections($results, $args);

	write_plan_file($plan, $args->{'out-file'}) or fatal('Could not write out-file');
    progress('90');
	make_report($report_target, $sections, $ADDON_NAME) or fatal();
    progress('100');
	return 0;
}

sub find_bundle_groups {
	trace();
	my $args = shift;
	my $plan = shift;
	my $candidates    = {};

    my $selected_interfaces_tbl = $args->{'interface-list-file'} ? read_plan_file($args->{'interface-list-file'})->get_table('<Interfaces>') : $plan->get_table('<Interfaces>');

	my $if_tag = $args->{'interface-tag'};
	my @selected_if_rows = $args->{'interface-tag'} ? $selected_interfaces_tbl->get_rows_where({Tags=>qr/(\A|;)$if_tag(;|\Z)/xms}) : $selected_interfaces_tbl->rows();

	my $circuits_tbl = $plan->get_table('<Circuits>');
	my $if_tbl = $plan->get_table('<Interfaces>');
	my $tot_ifs = 0;

	my $igp_metric_req = $args->{'igp-metrics'};
	my $te_metric_req  = $args->{'te-metrics'};

	foreach my $selected_interfaces_tbl_row (sort @selected_if_rows) {
		++$tot_ifs;
		my $node = $selected_interfaces_tbl_row->get_value('Node');
		my $interface = $selected_interfaces_tbl_row->get_value('Interface');
		my $igpmetric = $selected_interfaces_tbl_row->get_value('IGPMetric');
		my $temetric = $selected_interfaces_tbl_row->get_value('TEMetric') || $igpmetric;
		my $resvbw = $selected_interfaces_tbl_row->get_value('ResvBW');

		my $ckt_row;
		my $remote_node;
		my $remote_if;
		if (($ckt_row) = $circuits_tbl->get_rows_where({NodeA=>$node, InterfaceA=>$interface})) {
			$remote_node = $ckt_row->get_value('NodeB');
			$remote_if   = $ckt_row->get_value('InterfaceB');
		}
		else {
			($ckt_row) = $circuits_tbl->get_rows_where({NodeB=>$node, InterfaceB=>$interface}) or next;
			$remote_node = $ckt_row->get_value('NodeA');
			$remote_if   = $ckt_row->get_value('InterfaceA')
		}
		my $bw = $selected_interfaces_tbl_row->get_value('Capacity') || $ckt_row->get_value('Capacity') || 'na';
		my $ckt = join q{::}, $ckt_row->get_value('NodeA'), $ckt_row->get_value('InterfaceA');
		my $node_pair = defined $candidates->{join q{::}, $node, $remote_node} ? join q{::}, $node, $remote_node : join q{::}, $remote_node, $node;

		my $bundle_key = form_bundle_key($if_tbl, $igpmetric, $temetric, $bw, $remote_node, $remote_if, $args);

		$candidates->{$node_pair}{$bundle_key}{'circuits'}{$ckt}{'nodes'}{$node} = $interface;

		(not defined $candidates->{$node_pair}{$bundle_key}{'igpmetric'}{$node} or $candidates->{$node_pair}{$bundle_key}{'igpmetric'}{$node} > $igpmetric) and $candidates->{$node_pair}{$bundle_key}{'igpmetric'}{$node} = $igpmetric;
		(not defined $candidates->{$node_pair}{$bundle_key}{'temetric'}{$node}  or $candidates->{$node_pair}{$bundle_key}{'temetric'}{$node}  > $temetric)  and $candidates->{$node_pair}{$bundle_key}{'temetric'}{$node}  = $temetric;

		$candidates->{$node_pair}{$bundle_key}{'resvbw'}{$node} ||= 0;
		if (not defined $resvbw or $candidates->{$node_pair}{$bundle_key}{'resvbw'}{$node} eq 'na') {
			$candidates->{$node_pair}{$bundle_key}{'resvbw'}{$node} = 'na';
		}
		else {
			$candidates->{$node_pair}{$bundle_key}{'resvbw'}{$node} += $resvbw;
		}

		$candidates->{$node_pair}{$bundle_key}{'reference_if_key'}{$node} ||= join q{::}, $node, $interface;
	}
	my $bundle_groups = evaluate_candidates($candidates, $plan, $args);

	return ($bundle_groups, $tot_ifs);
}

sub form_bundle_key {
	trace();
	my $if_tbl      = shift;
	my $igpmetric   = shift;
	my $temetric    = shift;
	my $bw          = shift;
	my $remote_node = shift;
	my $remote_if   = shift;
	my $args        = shift;

	my $igp_metric_req = $args->{'igp-metrics'};
	my $te_metric_req  = $args->{'te-metrics'};

	my ($remote_if_row) = $if_tbl->get_rows_where({Node=>$remote_node, Interface=>$remote_if});
	my $remote_if_igp_metric = $remote_if_row->get_value('IGPMetric');
	my $remote_if_te_metric = $remote_if_row->get_value('TEMetric') || $remote_if_igp_metric;
	my $igp_metric_key = $igp_metric_req ne 'Require equal' ? $SINGLE_DASH : $igpmetric <= $remote_if_igp_metric ? join q{-}, $igpmetric, $remote_if_igp_metric : join q{-}, $remote_if_igp_metric, $igpmetric;
	my $te_metric_key  = $te_metric_req  ne 'Require equal' ? $SINGLE_DASH : $temetric  <= $remote_if_te_metric  ? join q{-}, $temetric, $remote_if_te_metric   : join q{-}, $remote_if_te_metric, $temetric;
	my $bundle_key = join q{::}, $bw, $igp_metric_key, $te_metric_key;
	return $bundle_key;
}

sub evaluate_candidates {
	trace();
	my $candidates = shift;
	my $plan       = shift;
	my $args       = shift;

	my $ports_tbl = $plan->get_table('<Ports>');

	foreach my $node_pair (sort keys %{ $candidates }) {
		foreach my $bundle_key (sort keys %{ $candidates->{$node_pair} }) {
			my ($bw) = split m/[:]{2}/xms, $bundle_key;
			$bw eq 'na' and $candidates->{$node_pair}{$bundle_key}{'reject'} = 1 and next;
			my $number_of_parallel_ckts = keys %{ $candidates->{$node_pair}{$bundle_key}{'circuits'} };
			($number_of_parallel_ckts < 2 and $candidates->{$node_pair}{$bundle_key}{'reject'} = 1 and next) or $candidates->{$node_pair}{$bundle_key}{'reject'} = 0;
			foreach my $ckt (sort keys %{ $candidates->{$node_pair}{$bundle_key}{'circuits'} }) {
				my $number_of_interfaces = keys %{ $candidates->{$node_pair}{$bundle_key}{'circuits'}{$ckt}{'nodes'} };
				if ($number_of_interfaces < 2) {
					$candidates->{$node_pair}{$bundle_key}{'circuits'}{$ckt}{'reject'} = 1;
					debug("Rejected Circuit $ckt due to only 1 interface");
					if(--$number_of_parallel_ckts < 2) {
						$candidates->{$node_pair}{$bundle_key}{'reject'} = 1;
						debug("Rejected $node_pair,$bundle_key due to insufficient interfaces");
						last;
					}
					next;
				}
				foreach my $node (sort keys %{ $candidates->{$node_pair}{$bundle_key}{'circuits'}{$ckt}{'nodes'} }) {
					my $if = $candidates->{$node_pair}{$bundle_key}{'circuits'}{$ckt}{'nodes'}{$node};
					if($ports_tbl->get_rows_where({Node=>$node, Interface=>$if})) {  # Check to see if this Interface we are about to bundle already has a port mapped to it.  If so, reject whole circuit.
						$candidates->{$node_pair}{$bundle_key}{'circuits'}{$ckt}{'reject'} = 1;
						--$number_of_parallel_ckts < 2 and $candidates->{$node_pair}{$bundle_key}{'reject'} = 1;
						last;
					}
					$candidates->{$node_pair}{$bundle_key}{'circuits'}{$ckt}{'reject'} = 0;
				}
			}
		}
	}
    return $candidates;
}

sub create_bundles {
	trace();
	my $bundle_groups = shift;
	my $tot_ifs       = shift;
	my $plan          = shift;
	my $args          = shift;
	my $bundled_if_num = {};
	my $results = {
		'num_bundles'     => 0,
		'num_ifs_bundled' => 0,
		'tot_ifs'         => $tot_ifs,
	};

	my $interfaces_tbl = $plan->get_table('<Interfaces>');
	foreach my $node_pair (sort keys %{ $bundle_groups }) {
		my $bundled_if_metrics = {};
		my @nodes = split m/[:]{2}/xms, $node_pair;
		foreach my $bundle_key (sort keys %{ $bundle_groups->{$node_pair} }) {
			my ($bw) = split m/[:]{2}/xms, $bundle_key;
			$bundle_groups->{$node_pair}{$bundle_key}{'reject'} == 1 and next;
			$results->{'num_bundles'} += 2;
			foreach my $node (@nodes) {
				$bundled_if_metrics->{$node} = {
					'igpmetric' => $bundle_groups->{$node_pair}{$bundle_key}{'igpmetric'}{$node},
					'temetric'  => $bundle_groups->{$node_pair}{$bundle_key}{'temetric'}{$node},
					'resvbw'    => $bundle_groups->{$node_pair}{$bundle_key}{'resvbw'}{$node},
				};
			}
			my $bundle_data = add_bundled_interfaces_and_circuit($plan, $bundled_if_num, \@nodes, $bundled_if_metrics, $bundle_groups->{$node_pair}{$bundle_key}{'reference_if_key'}, $args);
			foreach my $ckt (sort keys %{ $bundle_groups->{$node_pair}{$bundle_key}{'circuits'} }) {
				$bundle_groups->{$node_pair}{$bundle_key}{'circuits'}{$ckt}{'reject'} == 1 and next;
				$results->{'num_ifs_bundled'} +=2;
				convert_circuit_to_port_circuit($ckt, $plan);
				foreach my $node (sort keys %{ $bundle_groups->{$node_pair}{$bundle_key}{'circuits'}{$ckt}{'nodes'} }) {
					my $if = $bundle_groups->{$node_pair}{$bundle_key}{'circuits'}{$ckt}{'nodes'}{$node};
					my $bundle_if_name = $bundle_data->{$node};
					convert_if_to_port($node, $if, $bw, $bundle_if_name, $ckt, $plan);
				}
			}
		}
	}
	return $results;
}

sub add_bundled_interfaces_and_circuit {
	trace();
	my $plan               = shift;
	my $bundled_if_num     = shift;
	my $nodes              = shift;
	my $bundled_if_metrics = shift;
	my $ref_if_key         = shift;
	my $args               = shift;

	my $circuits_tbl = $plan->get_table('<Circuits>');
	my $if_tbl = $plan->get_table('<Interfaces>');

	my $bundle_data = {};
	my ($node_a, $node_b, $interface_a, $interface_b);
	foreach my $node (@{ $nodes }) {
		my $igpmetric = $bundled_if_metrics->{$node}{'igpmetric'};
		my $temetric  = $bundled_if_metrics->{$node}{'temetric'};
		my $resvbw    = $bundled_if_metrics->{$node}{'resvbw'} ne 'na' ? $bundled_if_metrics->{$node}{'resvbw'} : undef;
		my ($ref_node, $ref_if) = split m/[:]{2}/xms, $ref_if_key->{$node};
		my ($ref_if_row) = $if_tbl->get_rows_where({Node=>$ref_node, Interface=>$ref_if});
		my $resv_bw_perc = $ref_if_row->get_value('ResvBWPercent');
		defined $resv_bw_perc and $resv_bw_perc = sprintf '%.2f', $resv_bw_perc;
		my $frr_enabled  = $ref_if_row->get_value('FRREnabled');
		my $aff          = $ref_if_row->get_value('Affinities');
		my $polgrp       = $ref_if_row->get_value('PolicyGroup');
		my $te_enabled   = $ref_if_row->get_value('TEEnabled');
		(defined $bundled_if_num->{$node} and ++$bundled_if_num->{$node}) or $bundled_if_num->{$node} = 0;
		my $bundled_if_name_prefix = $args->{'bundled-if-prefix'};
		my $if_name = $bundled_if_name_prefix . $bundled_if_num->{$node};
		my $new_bundled_if_row = $if_tbl->append();
		$new_bundled_if_row->set_values({
				Node          =>$node,
				Interface     =>$if_name,
				IGPMetric     =>$igpmetric,
				TEMetric      =>$temetric,
				ResvBW        =>$resvbw,
				ResvBWPercent =>$resv_bw_perc,
				FRREnabled    =>$frr_enabled,
				Affinities    =>$aff,
				PolicyGroup   =>$polgrp,
				TEEnabled     =>$te_enabled,
		});
		$bundle_data->{$node} = $if_name;
		(defined $interface_a and $interface_b = $if_name) or $interface_a = $if_name;
		(defined $node_a and $node_b = $node) or $node_a = $node;
	}
	my $new_bundled_circuit_row = $circuits_tbl->append();
	my $bundled_circuit_name = $node_a . q{(} . $interface_a . q{)-} . $node_b . q{(} . $interface_b . q{)};
	$new_bundled_circuit_row->set_values({Name=>$bundled_circuit_name, NodeA=>$node_a, InterfaceA=>$interface_a, NodeB=>$node_b, InterfaceB=>$interface_b});
	return $bundle_data;
}

sub convert_circuit_to_port_circuit {
	trace();
	my $ckt  = shift;
	my $plan = shift;

    my $circuits_tbl = $plan->get_table('<Circuits>');
	my $port_ckts_tbl = $plan->get_table('<PortCircuits>');
	my ($node_a, $if_a) = split m/[:]{2}/xms, $ckt;
	my ($ckt_row) = $circuits_tbl->get_rows_where({NodeA=>$node_a, InterfaceA=>$if_a});
	my $node_b = $ckt_row->get_value('NodeB');
	my $if_b = $ckt_row->get_value('InterfaceB');
	my $ckt_name = $ckt_row->get_value('Name');
	my $active = $ckt_row->get_value('Active');
	my $l1_ckt = $ckt_row->get_value('L1CircuitName');
	my $l1_node_a = $ckt_row->get_value('L1CircuitNodeA');
	my $l1_node_b = $ckt_row->get_value('L1CircuitNodeB');
	my $new_port_ckt_row = $port_ckts_tbl->append();
	$new_port_ckt_row->set_values({
		Name           =>$ckt_name,
		NodeA          =>$node_a,
		PortA          =>$if_a,
		NodeB          =>$node_b,
		PortB          =>$if_b,
		Active         =>$active,
		L1CircuitName  =>$l1_ckt,
		L1CircuitNodeA =>$l1_node_a,
		L1CircuitNodeB =>$l1_node_b,
	});

	convert_circuit_srlg_to_port_circuit($node_a, $if_a, $node_b, $if_b, $plan);

	$circuits_tbl->delete_row($ckt_row);
	return;
}

sub convert_circuit_srlg_to_port_circuit {
	trace();
	my $node_a = shift;
	my $if_a   = shift;
	my $node_b = shift;
	my $if_b   = shift;
	my $plan   = shift;

	my $srlg_ckts_tbl = $plan->get_table('<SRLGCircuits>');
	my $srlg_port_ckts_tbl = $plan->get_table('<SRLGPortCircuits>');
	my @srlg_ckt_rows = $srlg_ckts_tbl->get_rows_where({NodeA=>$node_a, InterfaceA=>$if_a}) or return;
	while (@srlg_ckt_rows) {
		my $srlg_ckt_row = shift @srlg_ckt_rows;
		my $srlg_port_ckt_row = $srlg_port_ckts_tbl->append();
		my $srlg = $srlg_ckt_row->get_value('SRLG');
		$srlg_port_ckt_row->set_values({SRLG=>$srlg, NodeA=>$node_a, PortA=>$if_a, NodeB=>$node_b, PortB=>$if_b});
		$srlg_ckts_tbl->delete_row($srlg_ckt_row);
	}

	return;
}

sub convert_if_to_port {
	trace();
	my $node           = shift;
	my $if_name        = shift;
	my $bw             = shift;
	my $bundle_if_name = shift;
	my $ckt            = shift;
	my $plan           = shift;

	my $if_tbl = $plan->get_table('<Interfaces>');
	my ($if_row) = $if_tbl->get_rows_where({Node=>$node, Interface=>$if_name});
	my $desc = $if_row->get_value('Description');
	my $tags = $if_row->get_value('Tags');

	# Must look for Port Circuit active status since the Circuit has already been converted to a Port Circuit
	my $port_circuits_tbl = $plan->get_table('<PortCircuits>');
	my ($node_a, $if_a) = split m/[:]{2}/xms, $ckt;
	my ($port_ckt_row) = $port_circuits_tbl->get_rows_where({NodeA=>$node_a, PortA=>$if_a});
	my $active = $port_ckt_row->get_value('Active');

	my $ports_tbl = $plan->get_table('<Ports>');
	my $new_port_row = $ports_tbl->append();
	$new_port_row->set_values({Node=>$node,Port=>$if_name, Capacity=>$bw, Interface=>$bundle_if_name, Active=>$active, Description=>$desc, Tags=>$tags});

	move_interface_traffic_to_bundled_if($node, $if_name, $bundle_if_name, $plan);
	convert_interface_ip_address_to_bundled_if($node, $if_name, $bundle_if_name, $plan);
	convert_interface_queues_to_bundled_if($node, $if_name, $bundle_if_name, $plan);
	convert_plotlayout_if_to_bundled_if($node, $if_name, $bundle_if_name, $plan);
	adjust_named_path_hops($node, $if_name, $bundle_if_name, $plan);

	$if_tbl->delete_row($if_row);
	return;
}

sub adjust_named_path_hops {
	trace();
	my $node           = shift;
	my $if_name        = shift;
	my $bundle_if_name = shift;
	my $plan           = shift;
	my $named_pth_hops_tbl = $plan->get_table('<NamedPathHops>') or return;
	my @affected_rows      = $named_pth_hops_tbl->get_rows_where({Node=>$node,Interface=>$if_name}) or return;
	foreach my $row (@affected_rows) {
		$row->set_values({Interface=>$bundle_if_name});
	}
	return;
}

sub move_interface_traffic_to_bundled_if {
	trace();
	my $node           = shift;
	my $if_name        = shift;
	my $bundle_if_name = shift;
	my $plan           = shift;

	my $if_traff_tbl = $plan->get_table('InterfaceTraffic');
	my @if_rows = $if_traff_tbl->get_rows_where({Node=>$node, Interface=>$if_name}) or return;
	foreach my $row (@if_rows) {
		my $traffic_level = $row->get_value('TrafficLevel');
		my $queue = $row->get_value('Queue');
		my ($bundled_if_row) = $if_traff_tbl->get_rows_where({Node=>$node, Interface=>$bundle_if_name, TrafficLevel=>$traffic_level, Queue=>$queue});
		if (not defined $bundled_if_row) {
			$bundled_if_row = $if_traff_tbl->append();
			$bundled_if_row->set_values({Node=>$node, Interface=>$bundle_if_name, TrafficLevel=>$traffic_level, Queue=>$queue});
		}
		my $bundle_if_traff_meas = $bundled_if_row->get_value('TraffMeas') || 0;
		my $if_traff_meas = $row->get_value('TraffMeas') || 0;
		$bundle_if_traff_meas += $if_traff_meas;
		$bundled_if_row->set_values({TraffMeas=>$bundle_if_traff_meas});
		$if_traff_tbl->delete_row($row);
	}
	return;
}

sub convert_interface_ip_address_to_bundled_if {
	trace();
	my $node           = shift;
	my $if_name        = shift;
	my $bundle_if_name = shift;
	my $plan           = shift;

	my $if_ip_tbl = $plan->get_table('InterfaceIPAddresses') or return;
	my ($if_row) = $if_ip_tbl->get_rows_where({Node=>$node, Interface=>$if_name}) or return;
	my ($bundled_if_row) = $if_ip_tbl->get_rows_where({Node=>$node, Interface=>$bundle_if_name}) or ($if_row->set_values({Interface=>$bundle_if_name}) and return);
    $if_ip_tbl->delete_row($if_row);

    return;
}

sub convert_plotlayout_if_to_bundled_if {
	trace();
	my $node           = shift;
	my $if_name        = shift;
	my $bundle_if_name = shift;
	my $plan           = shift;

	my $plot_layout_elements_tbl = $plan->get_table('PlotLayoutElements') or return;
	my ($row) = $plot_layout_elements_tbl->get_rows_where({ElementNode=>$node, ElementInterface=>$if_name}) or return;
	my ($bundled_if_row) = $plot_layout_elements_tbl->get_rows_where({ElementNode=>$node, ElementInterface=>$bundle_if_name}) or ($row->set_values({ElementInterface=>$bundle_if_name}) and return);
    $plot_layout_elements_tbl->delete_row($row);

    return;
}

sub convert_interface_topology_to_bundled_if {
	trace();
	my $node           = shift;
	my $if_name        = shift;
	my $bundle_if_name = shift;
	my $plan           = shift;

	my $if_topo_tbl = $plan->get_table('InterfaceTopologies') or return;
	my ($row) = $if_topo_tbl->get_rows_where({Node=>$node, Interface=>$if_name}) or return;
	my ($bundled_if_row) = $if_topo_tbl->get_rows_where({Node=>$node, Interface=>$bundle_if_name}) or ($row->set_values({Interface=>$bundle_if_name}) and return);
    $if_topo_tbl->delete_row($row);

    return;
}

sub convert_interface_queues_to_bundled_if {
	trace();
	my $node           = shift;
	my $if_name        = shift;
	my $bundle_if_name = shift;
	my $plan           = shift;

	my $if_ip_tbl = $plan->get_table('InterfaceQueues') or return;
	my @if_rows = $if_ip_tbl->get_rows_where({Node=>$node, Interface=>$if_name});
	if ($if_ip_tbl->get_rows_where({Node=>$node, Interface=>$bundle_if_name})) {  # Check to see if we have already converted one of the interfaces to the bundled if.  If so, just delete these.
		foreach (@if_rows) { $if_ip_tbl->delete_row($_); }
	    return;
	}
	map { $_->set_values({Interface=>$bundle_if_name}) } @if_rows; # Convert the IF entries to the bundled IF

    return;
}

sub report_sections {
	trace();
	my $results = shift;
	my $args = shift;

	my $tot_ifs             = $results->{'tot_ifs'};
	my $num_ifs_bundled     = $results->{'num_ifs_bundled'};
	my $num_bundles_created = $results->{'num_bundles'};
	my $summary_content = join $EMPTY_STRING,
	    "Total Number of Interfaces Evaluated:            $tot_ifs\n",
		"Number of Input Interfaces Successfully Bundled: $num_ifs_bundled\n",
		"Number of Bundled Interfaces Created:            $num_bundles_created\n",
	;

	my $summary         = {name=>'Report Summary', type=>'TEXT', data=>$summary_content};
	my $sections        = [$summary];

	if($args->{'return-config-file'}) {
		my @cols = qw(Property Value);
		my $return_config_file = MATE::File->new();
		my $addon_return_config_table = $return_config_file->append('<AddOnReturnConfig>');
		$addon_return_config_table->extend_columns(\@cols);
		my $row = $addon_return_config_table->append();
		$row->set_values({Property=>'ShowReport', Value=>$ADDON_NAME});
		$row = $addon_return_config_table->append();
		$row->set_values({Property=>'ShowReportSection', Value=>'Report Summary'});
		write_plan_file($return_config_file, $args->{'return-config-file'})
	}

	return $sections;
}

__END__

