#!/usr/bin/perl -W
# Rached Blili (rached@Cariden.com)
#
# WARNING:  This tool is the intellectual property of Cariden Technologies
# and is covered by the terms of the mutual non-disclosure agreement.
# The content of this script and the methods employed herein should not be
# shared with third parties except in a manner consistent with the NDA and
# master software license agreement if applicable.


## ------------------- Setup ------------------------
use strict;

use File::Basename;
use FindBin;
use lib dirname($0);
use Sinewave;
use Data::Dumper;

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
my $MATE_EXPORT = "\"$bin/table_extract\"";
my $MATE_SQL = "\"$bin/mate_sql\"";
my $SQL = '';

# Files that must be cleaned up later
my @cleanup = ();
my $SCRIPT_NAME = basename($0);


# ================================ BEGIN ======================================

# The specified plan file might be in tab or pln format.  If it is a pln file
# it must be exported so we can open it with MATE::File
#if ($PLNFILE =~ /\.pln$/) {

   $TABFILE = $PLNFILE . "-" . time() . "-tmp.txt";
   push(@cleanup,$TABFILE);
print "[$SCRIPT_NAME] Exporting...\n";
   system ("$MATE_EXPORT -plan-file \"$PLNFILE\" -out-file \"$TABFILE\" -verbosity 10");
#}
#else { $TABFILE = $PLNFILE ; }
#RB#print "[$SCRIPT_NAME] Ports.TraffMeas is not exported. applying workaround...\n";

my $plan = new MATE::File("$TABFILE");

# ------ End Input Section ----------

# We may want to track state - ie: have the last run affect this one
# # If so, the state information is in the -state-file
print "[$SCRIPT_NAME] Getting Network State...\n";
my ($state,$stateSum,%summary);
my $STATE = '/opt/cariden/bin/nvsdemo/bin/state.txt';
#if ($TRACKSTATE) {
$state = new MATE::File("$STATE");
$stateSum = $state->getTable('<Summary>');
%summary = ();
foreach my $r ($stateSum->getRows) {
   my $name = $stateSum->getEntry($r,'Name');
   my $val = $stateSum->getEntry($r,'Value');
   $summary{$name} = $val;
   }
print "[$SCRIPT_NAME] Processing Node CPU and MEM...\n";
my $nodes = $plan->getTable('<Nodes>');
my $nodesup = $summary{'NodesUp'} || 0;
my $nodesdown = $summary{'NodesDown'} || 0;
my $circsup = $summary{'CircuitsUp'} || 0;
my $circsdown = $summary{'CircuitsDown'} || 0;
my $metrics = $summary{'MetricChange'} || 0;
foreach my $r ($nodes->getRows) {
    my $vendor = $nodes->getEntry($r,'Vendor');
    next unless defined($vendor);
    my $cpu1 = $nodes->getEntry($r,'NetIntRE0CPU5m');
    my $cpu1new;
    my $ram1 = $nodes->getEntry($r,'NetIntRE0Mem');
    my $cpu2 = $nodes->getEntry($r,'NetIntRE1CPU5m');
    my $ram2 = $nodes->getEntry($r,'NetIntRE1Mem');
      #if (defined($cpu1)) { 
    print "cpu: $cpu1\n";
    $cpu1new = int $cpu1 * 2;
	#$cpu1new = int $cpu1 
        #     + $nodesup 
         #    + $nodesdown  
          #   + ($cpu1 * ( ($circsup + $circsdown + $metrics) / 100));
    print "newcpu: $cpu1new\n";
    $nodes->setEntry($r,'NetIntRE0CPU5m',$cpu1new);
      #}
      if (defined($ram1)) { 
       $ram1 = int $ram1 
             + $nodesup 
             + $nodesdown  
             + ($ram1 * ( ($circsup + $circsdown + $metrics) / 100));
       $nodes->setEntry($r,'NetIntRE0Mem',$ram1);
      }
      if (defined($cpu2)) { 
       $cpu2 = int $cpu2 
             + $nodesup 
             + $nodesdown  
             + ($cpu2 * ( ($circsup + $circsdown + $metrics) / 100));
       $nodes->setEntry($r,'NetIntRE1CPU5m',$cpu2);
      }
      if (defined($ram2)) { 
       $ram2 = int $ram2 
             + $nodesup 
             + $nodesdown  
             + ($ram2 * ( ($circsup + $circsdown + $metrics) / 100));
       $nodes->setEntry($r,'NetIntRE1Mem',$ram2);
      }
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
