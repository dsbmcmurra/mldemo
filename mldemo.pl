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

use File::Spec::Functions qw(catfile file_name_is_absolute);
use FindBin;
use Cariden::Solutions qw(:TYPICAL);
use Cariden::Solutions::Constants qw($EMPTY_STRING $SINGLE_DASH $NEWLINE_RE);
use Cariden::Solutions::Time qw(epoch_to_cariden adjust_time cariden_to_epoch);
use File::Which qw(which);
our $VERSION = '2.0.0';
my $SNAP_TIME = '';
my $ML_SNAP_TIME = '';
my $NOW       = time;
exit main();
sub main {
	my $app = application(
		meta_information({
		}),
		app_flags(
			required_flags(
			),
			optional_flags(
				flag('config-file',      {data_type=>'srcplan',      default=>catfile($FindBin::Bin, 'default_config_file.txt')}),
				flag('prepare-planfile', {data_type=>'boolean',      default=>'true'}),
				flag('plan-file',        {data_type=>'srcplan',      default=>catfile($FindBin::Bin, 'default_plan_file.txt')}),
				flag('out-file',         {data_type=>'wrtplan'}),
				flag('reset-archive',    {data_type=>'boolean',      default=>'true'}),
				flag('generate-data',    {data_type=>'boolean',      default=>'true'}),
				flag('start-date',       {data_type=>'cariden_time', default=>epoch_to_cariden(adjust_time($NOW, 'week', '-4'))}),
				flag('stop-date',        {data_type=>'cariden_time', default=>epoch_to_cariden($NOW)}),
				flag('snap-frequency',   {data_type=>'integer',      default=>'900'}),
				flag('dry-run',          {data_type=>'boolean',      default=>'false'}),
				flag('rand-seed',        {data_type=>'integer',      default=>0}),
				flag('report-date',      {data_type=>'integer',      default=>0, hidden=>1}),
			),
		),
	) or fatal('Invalid meta-data, check program source');
	my $args   = read_command_line($app) or fatal('Could not process command-line arguments');
	my $config = read_config_file($args);
	my $plan   = prepare_planfile($args, $config);
	reset_archive($args, $config, $plan);
	generate_data($args, $config, $plan);
	return 0;
}

sub read_config_file {
	trace();
	my $args = shift;

	my $filename = $args->{'config-file'};
	my $config   = read_plan_file($filename) or fatal("Could not load config-file $filename");

	my $has_arg_var = qr/\$arg[{]([^}]+)[}]/xmsoi;
	my $has_env_var = qr/\$env[{]([^}]+)[}]/xmsoi;
	my $has_ml_bin  = qr/\$[{]mlbin[}]/xmso;

	foreach my $table ($config->tables()) {
		foreach my $row ($table->rows()) {
			foreach my $column ($table->column_names()) {
				my $original_value = $row->get_value($column);
				my $changed_value  = $original_value;
				defined $original_value or next;

				while (
					$changed_value =~ $has_arg_var
					or $changed_value =~ $has_env_var
					or $changed_value =~ $has_ml_bin
				) {
					if ($changed_value =~ $has_arg_var) {
						my $key = $1;
						exists $args->{$key} or fatal("No such argument as $key");
						defined $args->{$key} or fatal("Argument $key has an undefined value");

						my $replace = $args->{$key};
						debug("replacing '\$arg{$key}' with '$replace'");
						$changed_value =~ s/\$arg[{]$key[}]/$replace/xmsg;
					}

					if ($changed_value =~ $has_env_var) {
						my $key = $1;
						exists $ENV{$key} or fatal("No such environment variable as $key");
						defined $ENV{$key} or fatal("Environment variable $key has an undefined value");

						my $replace = $ENV{$key};
						debug("replacing '\$env{$key}' with '$replace'");
						$changed_value =~ s/\$env[{]$key[}]/$replace/xmsg;
					}

					if ($changed_value =~ $has_ml_bin) {
						my $bin = $FindBin::Bin;
						debug("replacing '\${mlbin}' with '$bin'");
						$changed_value =~ s/\$[{]mlbin[}]/$bin/xmsg;
					}
				}

				if ($changed_value ne $original_value) {
					$row->set_value($column=>$changed_value);
				}
			}
		}
	}

	return $config;
}

sub prepare_planfile {
	trace();
	my $args   = shift;
	my $config = shift;

	if (not $args->{'prepare-planfile'}) {
		debug('prepare-planfile step turned off, assuming -plan-file is already prepared');
		my $plan = read_plan_file($args->{'plan-file'}) or fatal();
		return $plan;
	}

	info('preparing planfile');
	my $stdout     = run_commands($config, '<PreparePlanfileSteps>', $args);

	my $plan;
	if ($args->{'dry-run'}) {
		$stdout = $args->{'plan-file'};
		$plan = read_plan_file($stdout) or fatal('Could not read prepared plan file into memory');
	}
	else{
		$plan = MATE::File->new([split $NEWLINE_RE, $stdout]);
	}
	
	if (my $out_file = $args->{'out-file'}) {
		my $history = $args->{'report-date'} ? { time => (scalar localtime $args->{'report-date'}) } : undef;
		my $options = $history ? { history => $history } : undef;
		write_plan_file($plan, $out_file, $options) or error("Could not save prepared plan file to $out_file");
	}

	return $plan;
}

sub run_commands {
	trace();
	my $config   = shift;
	my $tname    = shift;
	my $args     = shift;
	my $tmp_init = shift;

	my $running_buffer = $tmp_init || $EMPTY_STRING;

	$config->has_table($tname) or fatal("config-file has no $tname table");
	my $table = $config->get_table($tname);
	$table->sort_rows(sub { $a->get_value('Order') <=> $b->get_value('Order') });
	my @rows = $table->rows() or return error("No steps defined in $tname");

	foreach my $step (@rows) {
		my $command   = $step->get_value('Command');
		my $arguments = get_arguments($config, $step->get_value('ArgTable'), $args);
		my $stdin     = $step->get_value('STDIN');
		my $stdout    = $step->get_value('STDOUT');
		my $stderr    = $step->get_value('STDERR');

		if (defined $stdin and $stdin eq $SINGLE_DASH) {
			$stdin = \$running_buffer;
		}

		if (defined $stdout and $stdout eq $SINGLE_DASH) {
			$stdout = \$running_buffer;
		}

		maybe_command($args->{'dry-run'}, $command, $arguments, {stdin=>$stdin, stdout=>$stdout, stderr=>$stderr});
	}

	return $running_buffer;
}

sub get_arguments {
	trace();
	my $config = shift;
	my $tname  = shift;
	my $args   = shift;

	$config->has_table($tname) or fatal("config-file has no $tname table");
	my $table = $config->get_table($tname);

	my @arguments = ();
	my $has_snap_time = qr/\$[{]snaptime[}]/xmso;
	my $has_ml_snap_time = qr/\$[{]mlsnaptime[}]/xmso;
	foreach my $row ($table->rows()) {
		foreach my $cname (qw(Key Value)) {
			my $value = $row->get_value($cname);
			defined $value or next;

			if ($value =~ $has_snap_time) {
				defined $SNAP_TIME or fatal('Snap time is not defined yet');
				debug("replacing '\${snaptime}' with '$SNAP_TIME'");
				$value =~ s/\$[{]snaptime[}]/$SNAP_TIME/xmsg;
			}
			if ($value =~ $has_ml_snap_time) {
				defined $ML_SNAP_TIME or fatal('ML Snap time is not defined yet');
				debug("replacing '\${mlsnaptime}' with '$ML_SNAP_TIME'");
				$value =~ s/\$[{]mlsnaptime[}]/$ML_SNAP_TIME/xmsg;
			}

			push @arguments, $value;
		}
	}

	return [@arguments];
}

sub maybe_command {
	trace();
	my $dry_run   = shift;
	my $command   = shift;
	my $arguments = shift;
	my $options   = shift;

	my $crdn_root = $ENV{'CARIDEN_ROOT'} or fatal('CARIDEN_ROOT environment variable not defined');
	my $ml_bin    = $FindBin::Bin;
	my $in_mate   = qr/\A$crdn_root/xmso;
	my $in_mlbin  = qr/\A$ml_bin/xmso;
	my $abs       = file_name_is_absolute($command) ? $command : which($command);
	($abs and -e $abs and -x $abs) or fatal("Found no such command as $command");

	$dry_run and return notice("$command @{ $arguments }");

	my $string = "$command ";
	foreach my $arg (@$arguments){
		$string .= "$arg ";
	}
	$string .= "\n";
	info($string);

	if ($abs =~ $in_mate or $abs =~ $in_mlbin) {
		mate_command($command, $arguments, $options) or fatal("Failure detected while running $command");
		return 1;
	}

	system_command($command, $arguments, $options) or fatal("Failure detected while running $command");
	return 1;
}

sub reset_archive {
	trace();
	my $args   = shift;
	my $config = shift;
	my $plan   = shift;

	$args->{'reset-archive'} or return debug('reset-archive step turned off, skipping');

	info('resetting archive');
	run_commands($config, '<ResetArchiveSteps>', $args, $plan->to_string());

	return 1;
}

sub generate_data {
	trace();
	my $args   = shift;
	my $config = shift;
	my $plan   = shift;

	$args->{'generate-data'} or return debug('generate-data step turned off, skipping');

	($args->{'snap-frequency'} and $args->{'snap-frequency'} > 0) or fatal('snap-frequency must be a positive integer');

	info(sprintf 'generating data from %s to %s', $args->{'start-date'}, $args->{'stop-date'});
	my $stop_epoch = cariden_to_epoch($args->{'stop-date'});
	$SNAP_TIME     = $args->{'start-date'};
	$ML_SNAP_TIME  = snaptime_to_mldnaptime($SNAP_TIME);
	my $snap_epoch = cariden_to_epoch($SNAP_TIME);
	my $snap_count = int (($stop_epoch - $snap_epoch) / $args->{'snap-frequency'});
	debug(sprintf "snap time: $snap_epoch, snap stop: $stop_epoch, snap frequency: %s, snap count: $snap_count", $args->{'snap-frequency'});
	while (cariden_to_epoch($SNAP_TIME) < $stop_epoch) {
		info("generating data for $SNAP_TIME");
		run_commands($config, '<GenerateDataSteps>', $args, $plan->to_string());
		$SNAP_TIME    = adjust_time($SNAP_TIME, 'second', $args->{'snap-frequency'});
		$SNAP_TIME   =~ m/(\d\d)(\d\d)(\d\d)[_](\d\d)(\d\d)/xsmoi;
		$ML_SNAP_TIME = snaptime_to_mldnaptime($SNAP_TIME);
		$snap_epoch   = cariden_to_epoch($SNAP_TIME);
		debug("snap time: $snap_epoch");
	}

	return 1;
}

sub snaptime_to_mldnaptime {
	trace();
	my $snap_time = shift;
	$snap_time       =~ m/(\d\d)(\d\d)(\d\d)[_](\d\d)(\d\d)/xsmoi;
        my $ml_snap_time =  "20$1-$2-$3T$4:$5:00";

	return $ml_snap_time;
}


__END__

