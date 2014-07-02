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
use Cariden::Solutions::Constants qw($EMPTY_STRING);
use Cariden::Solutions::Time qw(cariden_to_epoch);
use Tie::Cycle::Sinewave;
use Const::Fast qw(const);
use Data::Dumper;
our $VERSION = '1.1.1';
const(my $SECONDS_PER_DAY    => 86_400);
const(my $MINUTES_PER_DAY    => 1440);
const(my $MINUTES_PER_HOUR   => 60);
const(my $WEEKEND_MULTIPLIER => 1.14);
const(my $MAX_METRIC         => 65_000);
const(my $SUNDAY             => 0);
const(my $SATURDAY           => 6);
exit main();
sub main {
	my $app = application(
		meta_information({}),
		app_flags(
			required_flags(
				flag('plan-file',  {data_type=>'srcplan'}),
				flag('out-file',   {data_type=>'wrtplan'}),
				flag('start-date', {data_type=>'cariden_time'}),
				flag('snap-date',  {data_type=>'cariden_time'}),
			),
			optional_flags(
				flag('demands-file',{data_type=>'srcplan'}),
				flag('state-file',                  {data_type=>'wrtfile'}),
				flag('seed',                        {data_type=>'integer', default=>0}),
				flag('growth-trend',                {data_type=>'integer', default=>'1000'}),
				flag('cycle-min',                   {data_type=>'real',    default=>'0.4'}),
				flag('cycle-max',                   {data_type=>'real',    default=>'2.0'}),
				flag('demand-variance',             {data_type=>'real',    default=>'0.1'}),
				flag('spike-frequency',             {data_type=>'integer', default=>'400'}),
				flag('spike-floor',                 {data_type=>'real',    default=>'0.5'}),
				flag('spike-variance',              {data_type=>'real',    default=>'2'}),
				flag('spike-duration',              {data_type=>'integer', default=>'5'}),
				flag('node-fail-frequency',         {data_type=>'integer', default=>'1200'}),
				flag('node-fail-duration',          {data_type=>'integer', default=>'5'}),
				flag('circuit-fail-frequency',      {data_type=>'integer', default=>'800'}),
				flag('circuit-fail-duration',       {data_type=>'integer', default=>'5'}),
				flag('troublesome-tag-impact',      {data_type=>'integer', default=>'6'}),
				flag('port-circuit-fail-frequency', {data_type=>'integer', default=>'100'}),
				flag('interface-change-frequency',  {data_type=>'integer', default=>'1600'}),
			),
		),
	) or fatal();
	my $args    = read_command_line($app) or fatal();
	$args->{'seed'} and srand $args->{'seed'};

	my $plan    = read_plan_file($args->{'plan-file'}) or fatal();
	#$plan       = read_in_demands($plan, $args->{'demands-file'});

	my $state   = get_state($args);
	my $summary = {};
	scale_demands($plan, $state, $args);
	my $failed_nodes = fail_nodes($plan, $state, $args, $summary);
	my $failed_ckts  = fail_circuits($plan, $state, $args, $summary);
	my $failed_ports = fail_port_circuits($plan, $state, $args, $summary);
	my $fails        = {nodes=>$failed_nodes, circuits=>$failed_ckts, portcircuits=>$failed_ports};
	my $changed_ints = change_interface_metrics($plan, $state, $args, $fails, $summary);
	save_state($state, $summary, $args->{'state-file'});
	write_plan_file($plan, $args->{'out-file'}) or fatal();
	return 0;
}

sub read_in_demands{
	trace();
	my $plan        = shift;
	my $demand_file = shift;
	-e $demand_file or return $plan;

	my $d_pln       = read_plan_file($demand_file);
	my $demand_tbl  = $d_pln->get_table('<Demands>');
	my $d_trff_tbl  = $d_pln->get_table('<DemandTraffic>');

	if( $plan->has_table( '<Demands>')       ){ $plan->set_table('<Demands>', $demand_tbl); }
	else{ $plan->append(  '<Demands>', $demand_tbl); }

	if( $plan->has_table( '<DemandTraffic>') ){  $plan->set_table('<DemandTraffic>', $d_trff_tbl); }
	else{ $plan->append(  '<DemandTraffic>', $d_trff_tbl); }

	return $plan;
}

sub get_state {
	trace();
	my $args = shift;

	my ($old_state, $new_state);

	if ($args->{'state-file'}) {
		$new_state = MATE::File->new();
		$new_state->append('<Demands>')->extend_columns([qw(Name Source Destination ServiceClass Intervals Var)]);
		$new_state->append('<Nodes>')->extend_columns([qw(Name Intervals)]);
		$new_state->append('<Circuits>')->extend_columns([qw(NodeA InterfaceA NodeB InterfaceB Intervals)]);
		$new_state->append('<Summary>')->extend_columns([qw(Name Value)]);

		if (-e $args->{'state-file'}) {
			$old_state = read_plan_file($args->{'state-file'}) or fatal();
		}
		else {
			warning(sprintf 'state-file %s does not exist, starting new state file', $args->{'state-file'});
			$old_state = $new_state->clone();
		}
	}

	my $state = $old_state ? [$old_state, $new_state] : undef;
	return $state;
}

sub scale_demands {
	trace();
	my $plan  = shift;
	my $state = shift;
	my $args  = shift;

	my $traffic_base = get_traffic_value($args);
	my $demand_traffic = $plan->get_table('<DemandTraffic>');
	foreach my $demand ($demand_traffic->rows()) {
		my $traffic       = $demand->get_value('Traffic');
		my $name          = $demand->get_value('Name');
		my $source        = $demand->get_value('Source');
		my $destination   = $demand->get_value('Destination');
		my $service_class = $demand->get_value('ServiceClass');
		my $demand_key    = {Name=>$name, Source=>$source, Destination=>$destination, ServiceClass=>$service_class};

		my $variance = rand $args->{'demand-variance'};
		my $spike    = (int rand $args->{'spike-frequency'}) == 0;
		if ($spike) {
			$variance = $args->{'spike-floor'} + rand $args->{'spike-variance'};
			info("Traffic spike on $source");
		}

		if ($state) {
			my ($old_state, $new_state) = @{ $state };

			my $intervals = 0;

			if (my ($old_demand) = $old_state->get_table('<Demands>')->get_rows_where($demand_key)) {
				$intervals = $old_demand->get_value('Intervals') - 1;
				$variance  = $old_demand->get_value('Var');
			}

			if ($spike) {
				$intervals ||= int rand $args->{'spike-duration'};
			}

			if ($intervals > 0) {
				## no critic(ValuesAndExpressions::ProhibitCommaSeparatedStatements);
				# This actually isn't a set of comma-delimitted statements.
				$new_state->get_table('<Demands>')->append()->set_values({ %{ $demand_key }, Intervals=>$intervals, Var=>$variance });
				## use critic(ValuesAndExpressions::ProhibitCommaSeparatedStatements);
			}
		}

		$traffic *= (1 + $variance) * $traffic_base;
		$demand->set_value(Traffic=>$traffic);
	}

	return 1;
}

sub get_traffic_value {
	trace();
	my $args = shift;

	# We want this curve to trend up over time, and this is what the $args->{'day'} 
	# variable is for. We'll use it to gradually scale traffic up.
	# The scaling is some random value between 0 and X/'growth-trend' where X is the day number.
	# This will trend up over time since the statistical likelyhood of a large
	# number increases.
	my $start_time = cariden_to_epoch($args->{'start-date'});
	my $snap_time  = cariden_to_epoch($args->{'snap-date'});
	my $day        = int ( ( $snap_time - $start_time ) / $SECONDS_PER_DAY ) + 1;
	my $growth     = rand $day / $args->{'growth-trend'};

	## no critic(Miscellanea::ProhibitTies);
	# Using tie is okay when the object is only used locally.
	tie my $cycle, 'Tie::Cycle::Sinewave', {
		min    => $args->{'cycle-min'} + $growth,
		max    => $args->{'cycle-max'} + $growth,
		period => $MINUTES_PER_DAY,
	};
	## use critic(Miscellanea::ProhibitTies);

	my (undef, $minute, $hour, undef, undef, undef, $wday) = localtime $snap_time;
	my $minute_of_day  = $hour * $MINUTES_PER_HOUR + $minute;
	my @traffic_values = map { $cycle } 0 .. $minute_of_day;
	my $traffic_value  = pop @traffic_values;

	# Make weekends a bit busier.
	my $is_weekend = ($wday == $SUNDAY or $wday == $SATURDAY);
	$is_weekend and $traffic_value *= $WEEKEND_MULTIPLIER;

	return $traffic_value;
}

sub fail_nodes {
	trace();
	my $plan    = shift;
	my $state   = shift;
	my $args    = shift;
	my $summary = shift;

	my $failed = {};
	foreach my $node ($plan->get_table('<Nodes>')->rows()) {
		my $name      = $node->get_value('Name');
		my $frequency = $args->{'node-fail-frequency'};
		my $value     = (int rand $frequency);
		my $fail;

		if($value){$fail = 0}
		else{$fail = 1}

		my $intervals = $fail ? 1 : 0;

		if ($state) {
			my ($old_state, $new_state) = @{ $state };

			$intervals = 0;

			if (my ($old_node) = $old_state->get_table('<Nodes>')->get_rows_where({Name=>$name})) {
				$intervals = $old_node->get_value('Intervals') - 1;
				if ($intervals <= 0) {
					$intervals = 0;
					$fail      = 0;
					++$summary->{'NodesUp'};
				}
			}

			if ($fail) {
				$intervals ||= int rand $args->{'node-fail-duration'};
			}

			if ($intervals > 0) {
				$new_state->get_table('<Nodes>')->append()->set_values({Name=>$name, Intervals=>$intervals});
			}
		}

		if ($fail) {
			info("Failing node $name");
			$node->set_value(Active=>'F');
			$failed->{$name} = 1;
			++$summary->{'NodesDown'};
		}
	}

	return $failed;
}

sub fail_circuits {
	trace();
	my $plan    = shift;
	my $state   = shift;
	my $args    = shift;
	my $summary = shift;

	my $failed   = {};
	my $circuits = $plan->get_table('<Circuits>');
	my $has_tags = $circuits->has_column('Tags');
	my $frequency = $args->{'circuit-fail-frequency'};

	foreach my $circuit ($circuits->rows()) {
		my $node_a      = $circuit->get_value('NodeA');
		my $int_a       = $circuit->get_value('InterfaceA');
		my $node_b      = $circuit->get_value('NodeB');
		my $int_b       = $circuit->get_value('InterfaceB');
		my $circuit_key = {NodeA=>$node_a, InterfaceA=>$int_a, NodeB=>$node_b, InterfaceB=>$int_b};

		my $tags      = $has_tags ? ($circuit->get_value('Tags') || $EMPTY_STRING) : $EMPTY_STRING;
		if ($tags =~ /troublesome/xmsoi) {
			$frequency = int ($frequency / $args->{'troublesome-tag-impact'});
		}

		my $value = (int rand $frequency);
		my $fail;
		if($value){$fail = 0}
		else{$fail = 1}

		my $intervals = $fail ? 1 : 0;

		if ($state) {
			my ($old_state, $new_state) = @{ $state };

			$intervals = 0;

			if (my ($old_circuit) = $old_state->get_table('<Circuits>')->get_rows_where($circuit_key)) {
				$intervals = $old_circuit->get_value('Intervals') - 1;

				if ($intervals <= 0) {
					$fail = 0;
					$intervals = 0;
					++$summary->{'CircuitsUp'};
				}
			}

			if ($failed) {
				$intervals ||= int rand $args->{'circuit-fail-duration'};
			}

			if ($intervals > 0) {
				## no critic(ValuesAndExpressions::ProhibitCommaSeparatedStatements);
				# This isn't two statements separated by a comma, but perlcritic cannot tell the difference.
				$new_state->get_table('<Circuits>')->append()->set_values({ %{ $circuit_key }, Intervals=>$intervals });
				## use critic(ValuesAndExpressions::ProhibitCommaSeparatedStatements);
			}
		}

		if ($fail) {
			info("Failing circuit $node_a/$int_a->$node_b/$int_b");
			$circuit->set_value(Active=>'F');
			$failed->{$node_a}{$int_a} = 1;
			$failed->{$node_b}{$int_b} = 1;
			++$summary->{'CircuitsDown'};
		}
	}

	return $failed;
}

sub fail_port_circuits {
	trace();
	my $plan    = shift;
	my $state   = shift;
	my $args    = shift;
	my $summary = shift;

	my $failed   = {};
	my $circuits = $plan->get_table('<PortCircuits>');
	my $has_tags = $circuits->has_column('Tags');
	foreach my $circuit ($circuits->rows()) {
		my $frequency = $args->{'circuit-fail-frequency'};
		my $tags      = $has_tags ? ($circuit->get_value('Tags') || $EMPTY_STRING) : $EMPTY_STRING;
		if ($tags =~ /troublesome/xmsoi) {
			$frequency = int ($frequency / $args->{'troublesome-tag-impact'});
		}

		my $fail = (int rand $frequency) == 0;
		if ($fail) {
			info('Failing a port circuit');
			$circuit->set_value(Active=>'F');
		}
	}

	return $failed;
}

sub change_interface_metrics {
	trace();
	my $plan    = shift;
	my $state   = shift;
	my $args    = shift;
	my $fails   = shift;
	my $summary = shift;

	my $changed = {};
	foreach my $interface ($plan->get_table('<Interfaces>')->rows()) {
		my $node   = $interface->get_value('Node');
		my $name   = $interface->get_value('Interface');
		my $metric = $interface->get_value('IGPMetric');

		# First, if the interface's node or circuit is down, shut down this interface.
		if (exists $fails->{'nodes'}{$node} or exists $fails->{'circuits'}{$node}{$name}) {
			$interface->set_value(NetIntOperStatus=>'down');
			next; # Metric won't matter, skip.
		}

		my $change = int rand $args->{'interface-change-frequency'};

		if ($change <= 0) {
			info("Costing out interface $node/$name");
			$interface->set_value(IGPMetric=>$MAX_METRIC);
			$changed->{$node}{$name} = 1;
			++$summary->{'MetricChange'};
			next;
		}

		if ($change <= 1) {
			info("Metric change on interface $node/$name");
			$metric *= 2;
			$interface->set_value(IGPMetric=>$metric);
			$changed->{$node}{$name} = 1;
			++$summary->{'MetricChange'};
		}
	}

	return $changed;
}

sub save_state {
	trace();
	my $state    = shift or return;
	my $summary  = shift;
	my $filename = shift;

	$state = $state->[1];
	foreach my $key (keys %{ $summary }) {
		$state->get_table('<Summary>')->append()->set_values({Name=>$key, Value=>$summary->{$key}});
	}

	write_plan_file($state, $filename, undef, 'quiet') or return error();

	return 1;
}

