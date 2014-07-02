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
#
# 6.04.14 - Brian McMurray added changes to support changes to the ml_insert_plan
# Schema WRT to Interface IPAddresses.
#
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
use Sinewave;

# Just in case the env variable is not defined, try not to break.
BEGIN {
   if (! $ENV{'CARIDEN_HOME'}) {$ENV{'CARIDEN_HOME'} = "$FindBin::Bin/..";}
}

use lib $ENV{"CARIDEN_HOME"}."/lib/perl";
use MATE qw(bin);

my %arg=();
while (@ARGV) {
   $arg{pop(@ARGV)} = pop(@ARGV);
}

if (! exists($arg{'-plan-file'}) ||
    exists($arg{'-help'}) ||
    ! exists($arg{'-out-file'}) ) { &Usage; }


if (! -f $arg{'-plan-file'} ) { &Usage; }

my $PLNFILE = $arg{'-plan-file'};
my $TABFILE = "";

# Directory where MATE tools are located.
my $bin = $ENV{"CARIDEN_HOME"}."/bin";
my $MATE_IMPORT = "\"$bin/mate_convert\"";
my $MATE_EXPORT = "\"$bin/mate_convert\"";

# Files that must be cleaned up later
my @cleanup = ();

# The loopback addr range to pick from
my $LoopbackNet = '147.202.18.0/24';
#
# # The address range for router-router interfaces
my $coreNet = '172.20.0.0/16';
#
# # The address range for edge networks
my $edgeNet = '10.100.0.0/19';

## ================================ BEGIN ======================================

# The specified plan file might be in tab or pln format.  If it is a pln file
# it must be exported so we can open it with MATE::File
if ($PLNFILE =~ /\.pln$/) {
   $TABFILE = $PLNFILE . "-" . time() . "-tmp.txt";
   push(@cleanup,$TABFILE);
print "Exporting...\n";
   system ("$MATE_EXPORT -plan-file \"$PLNFILE\" -out-file \"$TABFILE\"");
}
else { $TABFILE = $PLNFILE ; }

my $plan = read_plan_file("$TABFILE");

# ------ End Input Section ----------
my (@Loopbacks,@CoreLinks,@EdgeLinks);
my @lNets = &CarveNet($LoopbackNet,'/32');
shift(@lNets);pop(@lNets);
foreach my $chunk (@lNets) {
   my $addr = $$chunk[0];
   $addr =~ s/\/.*//;
   push(@Loopbacks,$addr);
}

my @eNets = &CarveNet($edgeNet,'/24');
foreach my $chunk (@eNets) {
   push(@EdgeLinks,$$chunk[1]);
}

my @iNets = &CarveNet($coreNet,'/30');
foreach my $chunk (@iNets) {
   push(@CoreLinks,($$chunk[0],$$chunk[1],$$chunk[2]));
}


my $as = $plan->getTable('<AS>');
my %asLookup;
foreach my $r ($as->getRows) {
   my $asn = $as->getEntry($r,'ASN');
   my $type = $as->getEntry($r,'Type');
   $asLookup{$asn} = $type;
}

my $nodes = $plan->getTable("<Nodes>");
my %nodeLookup;
my %nodeIpLookup;
foreach my $r ($nodes->getRows) {
   my $name = $nodes->getEntry($r,'Name');
   my $asn = $nodes->getEntry($r,'AS');
   next unless (!defined($asn) || $asLookup{$asn} eq 'internal');
   my $type = $nodes->getEntry($r,'Type');
   $nodeLookup{$name} = $type;
   next if ($type eq 'psn');
   my $addr = shift(@Loopbacks);
   $nodeIpLookup{$name} = $addr;
   $nodes->setEntry($r,'IpAddress',$addr);
   if (defined($asn)) {
      $nodes->setEntry($r,'BgpID',$addr);
   }
}
my %intLookup;
my $interfaces = $plan->getTable('<Interfaces>');
foreach my $r ($interfaces->getRows) {
   my $node = $interfaces->getEntry($r,'Node');
   my $interface = $interfaces->getEntry($r,'Interface');
   $intLookup{"$node $interface"} = $r;
}
my %netIntIntLookup;
my %netIntIndexLookup;
my $netIntInterfaces = $plan->getTable('<NetIntInterfaces>');
foreach my $r ($netIntInterfaces->getRows) {
   my $node = $netIntInterfaces->getEntry($r,'Node');
   my $nodeIp = $nodeIpLookup{$node};
   my $interface = $netIntInterfaces->getEntry($r,'Interface');
   my $netIntIndex = $netIntInterfaces->getEntry($r,'NetIntIndex'); 
$netIntIntLookup{"$node $interface"} = $r;
$netIntIndexLookup{"$nodeIp $interface"} = $netIntIndex;

}
my %intIPLookup;
my $interfaceIPs = $plan->getTable('<InterfaceIPAddresses>');
foreach my $r ($interfaceIPs->getRows) {
   my $node = $interfaceIPs->getEntry($r,'Node');
   my $interface = $interfaceIPs->getEntry($r,'Interface');
   $intIPLookup{"$node $interface"} = $r;
}
my %netIntIPLookup;
my $netIntIpAddresses = $plan->getTable('<NetIntIpAddresses>');
foreach my $r ($netIntIpAddresses->getRows) {
   my $nodeIp = $netIntIpAddresses->getEntry($r,'Node');
   my $interface = $netIntIpAddresses->getEntry($r,'Interface');
   my $netIntIndex = $netIntIpAddresses->getEntry($r,'NetIntIndex');   
$netIntIPLookup{"$nodeIp $interface"} = $r;
}

my $circuits = $plan->getTable('<Circuits>');
foreach my $r ($circuits->getRows) {
   my $nA = $circuits->getEntry($r,'NodeA');
   my $iA = $circuits->getEntry($r,'InterfaceA');
   my $nB = $circuits->getEntry($r,'NodeB');
   my $iB = $circuits->getEntry($r,'InterfaceB');
   my $AIp = $nodeIpLookup{$nA};
   my $BIp = $nodeIpLookup{$nB};
   my $AIndex = $netIntIndexLookup{"$AIp $iA"};
   my $BIndex = $netIntIndexLookup{"$BIp $iB"};
   $circuits->setEntry($r,'Name',shift(@CoreLinks));
   my $rowA = $intLookup{"$nA $iA"};
   my $rowB = $intLookup{"$nB $iB"};
   my $ipA = shift(@CoreLinks);
   my $ipB = shift(@CoreLinks);
   $interfaces->setEntry($rowA,'IpAddress',$ipA) unless !defined $rowA;
   $interfaces->setEntry($rowB,'IpAddress',$ipB) unless !defined $rowB;

   $rowA = $netIntIntLookup{"$nA $iA"};
   $rowB = $netIntIntLookup{"$nB $iB"};
   $netIntInterfaces->setEntry($rowA,'IpAddress',$ipA) unless !defined $rowA;
   $netIntInterfaces->setEntry($rowB,'IpAddress',$ipB) unless !defined $rowB;

   my $IProwA = $intIPLookup{"$nA $iA"};
   my $IProwB = $intIPLookup{"$nB $iB"};
   if (!defined($IProwA)) { $IProwA = $interfaceIPs->appendRow; }
   if (!defined($IProwB)) { $IProwB = $interfaceIPs->appendRow; }
   my ($a,$b) = split(/\//,$ipA);
   $interfaceIPs->setEntry($IProwA,'Node',$nA);
   $interfaceIPs->setEntry($IProwA,'Interface',$iA);
   $interfaceIPs->setEntry($IProwA,'IPv4Address',$a);
   $interfaceIPs->setEntry($IProwA,'IPv4PrefixLength',$b);
   ($a,$b) = split(/\//,$ipB);
   $interfaceIPs->setEntry($IProwB,'Node',$nB);
   $interfaceIPs->setEntry($IProwB,'Interface',$iB);
   $interfaceIPs->setEntry($IProwB,'IPv4Address',$a);
   $interfaceIPs->setEntry($IProwB,'IPv4PrefixLength',$b);
## BRIAN STUFF # 
#  We have to populate the NetintIpaddresses table
#  with Node (IP), IpAddress (of interface), NetintPrefixLength
#  and NetIntIndex, which must match the NetIntInterfaces.Netintindex column.
   $IProwA = $netIntIPLookup{"$AIp $iA"};
   $IProwB = $netIntIPLookup{"$BIp $iB"};
   #find the netintindexs of the Node / Interface pair
   my $netIntIndexA = $netIntIndexLookup{"$AIp $iA"}; 
   my $netIntIndexB = $netIntIndexLookup{"$BIp $iB"}; 
   if (!defined($IProwA)) { $IProwA = $netIntIpAddresses->appendRow; }
   if (!defined($IProwB)) { $IProwB = $netIntIpAddresses->appendRow; }
   ($a,$b) = split(/\//,$ipA);
   $netIntIpAddresses->setEntry($IProwA,'Node',$AIp);
   $netIntIpAddresses->setEntry($IProwA,'IPAddress',$a);
   $netIntIpAddresses->setEntry($IProwA,'NetIntIndex',$netIntIndexA);
   $netIntIpAddresses->setEntry($IProwA,'NetPrefixLength',$b);
   ($a,$b) = split(/\//,$ipB);
   $netIntIpAddresses->setEntry($IProwB,'Node',$BIp);
   $netIntIpAddresses->setEntry($IProwB,'IPAddress',$a);
   $netIntIpAddresses->setEntry($IProwB,'NetIntIndex',$netIntIndexB);
   $netIntIpAddresses->setEntry($IProwB,'NetPrefixLength',$b);
   }



# ---- Output Section -------
$PLNFILE = $arg{'-out-file'};
$TABFILE = "";
if ($PLNFILE =~ /\.pln$/) {
   $TABFILE = $PLNFILE . "-" . time() . "-tmp.txt";
   write_plan_file($plan, $TABFILE);
   system ("\"$MATE_IMPORT\" -plan-file \"$TABFILE\" -out-file \"$PLNFILE\"");
   push(@cleanup,$TABFILE);
}
else { write_plan_file($plan, $PLNFILE); }

foreach my $f (@cleanup) { unlink("$f"); }
exit;

sub CarveNet {
   my $net = shift;
   my $size = shift;
   $size =~ s/\///;
   my @chunks = ();
   my $i=0;
   my $x=0;
   my $slash32="11111111111111111111111111111111";

   my $startNet="";
   my ($network,$prefixLength,$addrsPerChunk);
   if ($net =~ /^([0-9]+\.[0-9]+\.[0-9]+\.[0-9]+)\/([0-9]+)/) {
      $network = &decIP2binIP($1);
      $prefixLength = $2;
      $startNet = &applymask($network,$prefixLength);
      $addrsPerChunk = 2 ** (32 - $size);
   }
   else {
      return(undef);
   }

   while (&applymask($network,$prefixLength) eq $startNet) {
    if ($x >= $addrsPerChunk) {
      $x=0;
      if (@{$chunks[$i]} == $addrsPerChunk) {$i++; }
      else { # If the last chunk was missing something, quit.
        pop(@chunks);
        last;
      }
    }
    #push(@{$chunks[$i]},&nnIP2dotIP(&bin2dec($network)) . " " .
    #                    &nnIP2dotIP(&bin2dec(&applymask($slash32,$size))));
    push(@{$chunks[$i]},&nnIP2dotIP(&bin2dec($network)) . "/$size");
    $x++;
    $network = (&dec2bin(&bin2dec($network) + 1));
   }
   if (@{$chunks[$i]} < $addrsPerChunk) { pop(@chunks); }
   return(@chunks);
}

sub dec2bin {
    my $str = unpack("B32", pack("N", shift));
    return $str;
}   


sub bin2dec {
    return unpack("N", pack("B32", substr("0" x 32 . shift, -32)));
}   
sub decIP2binIP {
        # split the address into its parts
        my @values=split(/\./,shift);
        my $binary="";
        # Take each part and convert it to an 8 bit binary
        foreach (@values) {
                # Append the parts to each other after conversion
                $binary .= (unpack("B8B8B8B8",pack("N",$_)))[3];
        }
        return($binary);
}

sub applymask {
        my ($addr,$mask) = @_;
        my @result=unpack("A$mask A*",$addr);
   my $res = sprintf("%-32s", $result[0]);
   $res =~ s/ /0/g;
        return($res);
}

sub nnIP2dotIP {
   my $addr = shift;
   use Socket;

   return(inet_ntoa(pack('N',$addr)));
}

sub Usage {
   print "Usage: $0 options\n";
   print "Required Options:\n";
   print "   -plan-file planfile.pln or tabfile.txt\n";
   print "   -out-file output.txt or outfile.pln\n";
   print "Optional Options:\n";
   print "      -help                : Display this message.\n\n";
   exit;
}

__END__
