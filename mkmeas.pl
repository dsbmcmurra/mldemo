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
$SQL = qq(UPDATE Ports SET TraffMeas = (SELECT TraffMeas FROM PortTraffic WHERE Ports.Node = PortTraffic.Node AND Ports.Port = PortTraffic.Port));
system ("$MATE_SQL -file \"$TABFILE\" -out-file \"$TABFILE\" -sql \"$SQL\" -verbosity 10");

my $plan = new MATE::File("$TABFILE");

# ------ End Input Section ----------

# We may want to track state - ie: have the last run affect this one
# # If so, the state information is in the -state-file
print "[$SCRIPT_NAME] Getting Network State...\n";
#my $TRACKSTATE = 0;
#if (exists($arg{'-state-file'}) && -f $arg{'-state-file'}) {
#   $TRACKSTATE = 1;
#}
my $TRACKSTATE = 1;
my ($state,$stateSum,%summary);
#my $STATE = $arg{'-state-file'};
my $STATE = '/opt/cariden/bin/nvsdemo/bin/state.txt';
if ($TRACKSTATE) {
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
   print "\tNodesup:\t$nodesup\n\tNodesdown:\t$nodesdown\n\tCktsup:\t$circsup\n\tCktsdown:\t$circsdown\n\tMetrics: $metrics\n";     
   foreach my $r ($nodes->getRows) {
      my $vendor = $nodes->getEntry($r,'Vendor');
      next unless defined($vendor);
      my $cpu1 = $nodes->getEntry($r,'NetIntRE0CPU5m');
      my $ram1 = $nodes->getEntry($r,'NetIntRE0Mem');
      my $cpu2 = $nodes->getEntry($r,'NetIntRE1CPU5m');
      my $ram2 = $nodes->getEntry($r,'NetIntRE1Mem');
      print "ORIGCPU:\t$cpu1\n";     
      if (defined($cpu1)) { 
      $cpu1 = int $cpu1 
	    + $nodesup 
	    + $nodesdown  
	    + ($cpu1 * ( ($circsup / 10)  + ($circsdown / 10) + $metrics) / 100);
      print "NEWCPU: \t$cpu1\n";
       #if ($cpu1 > 100) { $cpu1 = 100 };
       if ($cpu1 > 100) { $cpu1 = 95 + int rand(5) };
      $nodes->setEntry($r,'NetIntRE0CPU5m',$cpu1);
      }
       if (defined($ram1)) { 
       print "ORIG_MEM:\t$ram1\n";     
       $ram1 = int $ram1 
             + $nodesup 
             + $nodesdown  
             + ($ram1 *  ($circsup  + $circsdown + $metrics) / 1000);
       
       if ($ram1 > 100) { $ram1 = 95 + int rand(5) };
       $nodes->setEntry($r,'NetIntRE0Mem',$ram1);
       print "NEW_RAM: \t$ram1\n";
      }
      if (defined($cpu2)) { 
       $cpu2 = int $cpu2 
             + $nodesup 
             + $nodesdown  
             + ($cpu2 * ( ($circsup / 10) + ($circsdown / 10) + $metrics) / 100);
       if ($cpu2 > 100) { $cpu2 = 95 + int rand(5) };
       $nodes->setEntry($r,'NetIntRE1CPU5m',$cpu2);
      }
      if (defined($ram2)) { 
       $ram2 = int $ram2 
             + $nodesup 
             + $nodesdown  
             + ($ram2 *  ($circsup + $circsdown + $metrics) / 1000);
       #if ($ram2 > 100) { $ram2 = 99 };
       if ($ram2 > 100) { $ram2 = 95 + int rand(5) };
       $nodes->setEntry($r,'NetIntRE1Mem',$ram2);
      }
   }
}

# We have to go through the model and copy the simulated traffic over to 
# measured, with some random variability introduced.  And we will randomly
# drop measurements too (though very rarely).
# For LSPs, we will copy the simulated path to the Actual, except when we 
# randomly don't.
print "[$SCRIPT_NAME] Building Indices...\n";
my $interfaces = $plan->getTable("<Interfaces>");
my %interfaceLookup = ();
foreach my $r ($interfaces->getRows) {
   my $node = $interfaces->getEntry($r,'Node');
   my $int = $interfaces->getEntry($r,'Interface');
   $interfaceLookup{"$node $int"} = $r;
}

my $netintInterfaces = $plan->getTable("<NetIntInterfaces>");
my %netIntInterfaceLookup = ();
foreach my $r ($netintInterfaces->getRows) {
   my $node = $netintInterfaces->getEntry($r,'Node');
my $int = $netintInterfaces->getEntry($r,'Interface');
   $netIntInterfaceLookup{"$node $int"} = $r;
}
my $intTraff = $plan->getTable("<InterfaceTraffic>");
my %intTraffLookup = ();
foreach my $r ($intTraff->getRows) {
   my $node = $intTraff->getEntry($r,"Node");
   my $int = $intTraff->getEntry($r,"Interface");
   my $q = $intTraff->getEntry($r,"Queue");
   if (!defined($q)) {$q = ''};
   $intTraffLookup{"$node $int $q"} = $r;
}
my $netIntIntTraff = $plan->getTable("<NetIntInterfaceTraffic>");
my %netIntIntTraffLookup = ();
foreach my $r ($netIntIntTraff->getRows) {
   my $node = $netIntIntTraff->getEntry($r,"Node");
   my $int = $netIntIntTraff->getEntry($r,"Interface");
   my $q = $netIntIntTraff->getEntry($r,"Queue");
   if (!defined($q)) {$q = ''};
   $netIntIntTraffLookup{"$node $int $q"} = $r;
}
print "[$SCRIPT_NAME] Pre-caching interface traffic...\n";
my %traffCache = ();
foreach my $r ($interfaces->getRows) {
   my $node = $interfaces->getEntry($r,"Node");
   my $int = $interfaces->getEntry($r,"Interface");
   my $q = $interfaces->getEntry($r,"Queue");
   if ($q eq 'All') { $q = '' };
   my $traff = $interfaces->getEntry($r,"TraffSim");
   # If there is no simulated traffic, treat it as 0 because it's probably down.
   if (!defined($traff)) {$traff = 0;}
   $traffCache{"$node $int $q"} = $traff;
}

print "[$SCRIPT_NAME] Looping through interfaces...\n";
foreach my $r ($netintInterfaces->getRows) {
   my $node = $netintInterfaces->getEntry($r,"Node");
   my $int = $netintInterfaces->getEntry($r,"Interface");
   my $mainInt=undef;
   my $mainIntTraffRow=undef;
#   $mainInt = $int if defined $int =~ /^Bundle-Ether|^ae/; 
#   $mainInt =~ s/\.0//g;
   if ($int =~ /(.*)\.0$/) {
      $mainInt = $1;
   }
   elsif (exists($interfaceLookup{"$node ${int}.0"})) {
      # We process the physical interfaces as a part of the logical interface
      # So if this itteration is for a physical interface that has a logical one
      # We need to skip
      next;
   }
   my $q = ''; #$interfaces->getEntry($r,"Queue");
   if ($q eq 'All') { $q = '' };
   my $cap = $netintInterfaces->getEntry($r,"Capacity");

   my $IntRow = $interfaceLookup{"$node $int"};
   #my $MainIntRow = $netIntInterfaceLookup{"$node $mainInt"};
   my $traffRow = $intTraffLookup{"$node $int $q"};
   my $netIntTraffRow = $netIntIntTraffLookup{"$node $int $q"};
   if (defined($mainInt)) {
      $mainIntTraffRow = $netIntIntTraffLookup{"$node $mainInt $q"};
      if (!defined($mainIntTraffRow)) {
         print "WARNING: Could not find a traffic entry for $node $mainInt\n";
      }
   }
   elsif ($int =~ /(.*)\.0$/) {
      print "WARNING: $node $int is a logical interface but can't find its physical\n";
   }

   my ($remoteNode, $remoteInt);
   if (defined $IntRow) {
      $remoteNode = $interfaces->getEntry($IntRow,"RemoteNode");
      $remoteInt = $interfaces->getEntry($IntRow,"RemoteInterface");
   }

   # If the plan file doesn't contain a traffic entry for this interface
   # we will create one but only for L3 interfaces
   if (!defined($traffRow) && defined($remoteNode)) {
      $traffRow = $intTraff->appendRow;
      $intTraff->setEntry($traffRow,'Node',$node);
      $intTraff->setEntry($traffRow,'Interface',$int);
      $intTraff->setEntry($traffRow,'Queue',$q);
      $intTraffLookup{"$node $int $q"} = $traffRow;
   }
#
   # If the plan file doesn't contain a netint traffic entry for this interface
   # we will create one. 
   if (!defined($netIntTraffRow)) {
      $netIntTraffRow = $netIntIntTraff->appendRow;
      $netIntIntTraff->setEntry($netIntTraffRow,'Node',$node);
      $netIntIntTraff->setEntry($netIntTraffRow,'Interface',$int);
      $netIntIntTraff->setEntry($netIntTraffRow,'Queue',$q);
      $netIntIntTraffLookup{"$node $int $q"} = $netIntTraffRow;
   }
   if (defined($mainInt) && !defined($mainIntTraffRow)) {
      $mainIntTraffRow = $netIntIntTraff->appendRow;
      $netIntIntTraff->setEntry($mainIntTraffRow,'Node',$node);
      $netIntIntTraff->setEntry($mainIntTraffRow,'Interface',$mainInt);
      $netIntIntTraff->setEntry($mainIntTraffRow,'Queue',$q);
      $netIntIntTraffLookup{"$node $mainInt $q"} = $mainIntTraffRow;
   }
   # Check the interface for OperStatus of down and if we see it, copy to 
   # netint
   #  Brian 4/9/14 - changed lookup from NetIntInterfaces Table to Interfaces Table
#   my $oper = $netintInterfaces->getEntry($r,'NetIntOperStatus');
   my $interfaces = $plan->getTable('<Interfaces>');
   my ($int_row)  = $interfaces->get_rows_where({Node => $node, Interface => $int});
   my $oper       = $int_row ? $int_row->get_value('NetIntOperStatus') : undef;

   if (defined($oper) && $oper eq 'down') {
      if (exists($netIntInterfaceLookup{"$node $int"})) {
         $netintInterfaces->setEntry($netIntInterfaceLookup{"$node $int"},
                                     'NetIntOperStatus','down');
      }
   }
   my $traff;
   if (defined $IntRow) { 
      $traff = $interfaces->getEntry($IntRow,"TraffSim");
   }
   # If there is no simulated traffic, treat it as 0 because it's probably down.
   if (!defined($traff)) {$traff = 0;}

   # Grab inbound traffic from remote interface
   my $intraff = 0;
   if (defined $remoteNode) {
      if (exists($traffCache{"$remoteNode $remoteInt $q"})) {
         $intraff = $traffCache{"$remoteNode $remoteInt $q"};
      }
   }
   my $traffOut;
   # If traffOut is undefined, try to get it from the NetInt table
   if (!defined($traffOut)) {
      $traffOut = $netIntIntTraff->getEntry($netIntTraffRow,
                                          'TraffMeas');
   }
   my $traffIn = $netIntIntTraff->getEntry($netIntTraffRow,
                                             'NetIntInTraffMeas');

   # Since we are setting measurements, we need to make them consistent
   # with capacity.  So let's keep track of that.
   my $overOut = 0; # The amount by which outbound traffic exceeds capacity
   if ($traff > $cap) { $overOut = $traff - $cap; $traff = $cap; }
   my $overIn = 0; # The amount by which inbound traffic exceeds capacity
   if ($intraff > $cap) { $overIn = $intraff - $cap; $intraff = $cap;}

   # We avoid division by 0 errors here by catching the case.
   # Also, we try to be smart about setting netint values - if the link is down
   # we try to represent a spike in drops.
   if ($traff == 0) { # This tests for sim traffic = 0
      if ($netIntIntTraff->hasColumn('NetIntDropPacketsOut')) {
         # Dropped packets would be whatever we were dropping before plus
         # whatever we were measuring before (at minimum)
         my $x = $netIntIntTraff->getEntry($netIntTraffRow,'NetIntPacketsOut');
         if (defined($x)) {
          my $dropped = $netIntIntTraff->getEntry($netIntTraffRow,'NetIntDropPacketsOut');
          if (!defined $dropped) { $dropped = 0; }
          $x = $x + $dropped;
          $netIntIntTraff->setEntry($netIntTraffRow,'NetIntDropPacketsOut',$x) if defined $IntRow;
         }
      }
      if ($netIntIntTraff->hasColumn('NetIntDropTraffOut')) {
         # Dropped traffic would be whatever we were dropping before plus
         # whatever we were measuring before (at minimum)
         my $x = $netIntIntTraff->getEntry($netIntTraffRow,'TraffMeas');
         if (defined($x)) {
          if ($x eq '') { $x = 0; }
          my $dropped = $netIntIntTraff->getEntry($netIntTraffRow,'NetIntDropTraffOut');
          if (!defined $dropped) { $dropped = 0; }
          if ($dropped eq'') { $dropped = 0; }
          $x = $x + $dropped;
          $netIntIntTraff->setEntry($netIntTraffRow,'NetIntDropTraffOut',$x) if defined $netIntTraffRow;
          $netIntIntTraff->setEntry($mainIntTraffRow,'NetIntDropTraffOut',$x) if defined $mainIntTraffRow;
         }
      }
      $interfaces->setEntry($IntRow,'TraffMeas','0') if defined $IntRow;
      $netIntIntTraff->setEntry($netIntTraffRow,'TraffMeas','0');
      if ($netIntIntTraff->hasColumn('NetIntPacketsOut')) {
         $netIntIntTraff->setEntry($netIntTraffRow,'NetIntPacketsOut','0');
         $netIntIntTraff->setEntry($mainIntTraffRow,'NetIntPacketsOut','0') if defined $mainIntTraffRow;
      }
   }
   # Else, determine the ratio between simulated and measured traffic and
   # use it to scale the measured values accordingly.
   else { # We have simulated traffic on the interface
      my $outRatio = $traffOut / $traff;
      if (!$outRatio) { $outRatio = 1; }
      $interfaces->setEntry($IntRow,'TraffMeas',$traff); # if defined $IntRow;

      $netIntIntTraff->setEntry($netIntTraffRow,'TraffMeas',$traff);
      $netIntIntTraff->setEntry($mainIntTraffRow,'TraffMeas',$traff) if defined $mainIntTraffRow;

      $intTraff->setEntry($traffRow,'TraffMeas',$traff) if defined $traffRow;
      if ($netIntIntTraff->hasColumn('NetIntPacketsOut')) {
         my $x = $netIntIntTraff->getEntry($netIntTraffRow,'NetIntPacketsOut');
         if (defined($x)) {
            $x = $x / $outRatio;
         }
         else { $x = ''; }
         $netIntIntTraff->setEntry($netIntTraffRow,'NetIntPacketsOut',$x) if defined $netIntTraffRow;
         $netIntIntTraff->setEntry($mainIntTraffRow,'NetIntPacketsOut',$x) if defined $mainIntTraffRow;
      }
      if ($netIntIntTraff->hasColumn('NetIntDropPacketsOut')) {
         my $x = $netIntIntTraff->getEntry($netIntTraffRow,'NetIntDropPacketsOut') || 0;
         if (defined($x)) {
            $x = $x / $outRatio;
            if ($overOut) { # The interface is congested. Must count extra drops
               # Must figure out average packet size
               my $mbps = $interfaces->getEntry($IntRow,'TraffMeas');
               my $pps  = $netIntIntTraff->getEntry($netIntTraffRow,'NetIntPacketsOut');
               if (($pps eq '0') || ($pps == undef)) { next; }

			   my $mbpp  = $mbps / $pps; # Number of packets per megabit
			   my $drops = $overOut / $mbpp;
               $x = $x + ($drops);
            }
         }
         else { $x = ''; }
         $netIntIntTraff->setEntry($netIntTraffRow,'NetIntDropPacketsOut',$x) if defined $netIntTraffRow;
         $netIntIntTraff->setEntry($mainIntTraffRow,'NetIntDropPacketsOut',$x) if defined $mainIntTraffRow;
      }
      if ($netIntIntTraff->hasColumn('NetIntDropTraffOut')) {
         my $x = $netIntIntTraff->getEntry($netIntTraffRow,'NetIntDropTraffOut');
         if (defined($x)  && $x ne "") {
            $x = $x / $outRatio;
            if ($overOut) { # The interface is congested. Must count extra drops
               $x = $x + $overOut;
            }
         }
         else { $x = ''; }
         $netIntIntTraff->setEntry($netIntTraffRow,'NetIntDropTraffOut',$x) if defined $netIntTraffRow;
         $netIntIntTraff->setEntry($mainIntTraffRow,'NetIntDropTraffOut',$x) if defined $mainIntTraffRow;
      }
   }

   # Now check inbound traffic
   if ($intraff == 0 || !defined($intraff)) {
      $netIntIntTraff->setEntry($netIntTraffRow,'NetIntInTraffMeas','0') if defined $netIntTraffRow;
      $netIntIntTraff->setEntry($netIntTraffRow,'NetIntPacketsIn','0') if defined $netIntTraffRow;
      $netIntIntTraff->setEntry($netIntTraffRow,'NetIntErrorPacketsIn','0') if defined $netIntTraffRow;
      $netIntIntTraff->setEntry($mainIntTraffRow,'NetIntInTraffMeas','0') if defined $mainIntTraffRow;
      $netIntIntTraff->setEntry($mainIntTraffRow,'NetIntPacketsIn','0') if defined $mainIntTraffRow;
      $netIntIntTraff->setEntry($mainIntTraffRow,'NetIntErrorPacketsIn','0') if defined $mainIntTraffRow;
   }
   else {
      my $inRatio;
      if (defined($traffIn)) { 
       $inRatio = $traffIn / $intraff;
       if (!$inRatio) { $inRatio = 1;}
       $netIntIntTraff->setEntry($netIntTraffRow,'NetIntInTraffMeas',$intraff) if defined $IntRow;
       $netIntIntTraff->setEntry($mainIntTraffRow,'NetIntInTraffMeas',$intraff) if defined($mainIntTraffRow);
       if ($netIntIntTraff->hasColumn('NetIntPacketsIn')) {
         my $x = $netIntIntTraff->getEntry($netIntTraffRow,'NetIntPacketsIn');
         if (defined($x)) {
            $x = $x / $inRatio;
         }
         else { $x = ''; }
         $netIntIntTraff->setEntry($netIntTraffRow,'NetIntPacketsIn',$x) if defined $IntRow;
         $netIntIntTraff->setEntry($mainIntTraffRow,'NetIntPacketsIn',$x) if defined $mainIntTraffRow;
       }
       if ($netIntIntTraff->hasColumn('NetIntErrorPacketsIn')) {
         my $x = $netIntIntTraff->getEntry($netIntTraffRow,'NetIntErrorPacketsIn') if defined $IntRow;
         if  (defined($x) && $x ne "" && defined($inRatio)) {
            $x = $x / $inRatio;
         }
         else { $x = ''; }
         $netIntIntTraff->setEntry($netIntTraffRow,'NetIntErrorPacketsIn',$x) if defined $IntRow;
         $netIntIntTraff->setEntry($mainIntTraffRow,'NetIntErrorPacketsIn',$x) if defined $mainIntTraffRow;
       }
      }
   }
   # We want to set stats from the sub-if to the main if
   # This doesn't work!
#   if ($int =~ /\.0/ && $netIntIntTraff->hasColumn('NetIntPacketsOut')) {
#     my $packets = $netIntIntTraff->getEntry($netIntTraffRow,'NetIntPacketsOut');
#     my $traff = $netIntIntTraff->getEntry($netIntTraffRow,'NetIntPacketsOut');
#     if (defined($mainIntTraffRow)) {
#        $netIntIntTraff->setEntry($mainIntTraffRow,'NetIntPacketsOut',$packets);
#        $netIntIntTraff->setEntry($mainIntTraffRow,'TraffMeas',$traff);
#     }
#     else {
#        print "WARNING: Couldn't find a main Int entry for interface $node $int\n";
#     }
#   }   

}



# For LSPs, its quite simple.  Just copy traff sim
print "[$SCRIPT_NAME] Setting LSP traffic...\n";
my $lsps = $plan->getTable("<LSPs>");
my $lspTraff = $plan->getTable("<lspTraffic>");
my %lspTraffLookup = ();
foreach my $r ($lspTraff->getRows) {
   my $src = $lspTraff->getEntry($r,"Source");
   my $name = $lspTraff->getEntry($r,"Name");
   $lspTraffLookup{"$src $name"} = $r;
}
foreach my $r ($lsps->getRows) {
   my $src = $lsps->getEntry($r,'Source');
   my $name = $lsps->getEntry($r,'Name');
   my $traff = $lsps->getEntry($r,'TraffSim');
   my $lspTraffRow = $lspTraffLookup{"$src $name"};
   next unless (defined $lspTraffRow);
   $lspTraff->setEntry($lspTraffRow,'TraffMeas',$traff);
}

# Ports are more complicated.  Since we don't simulate traffic through ports,
# we have to set the altered measured traffic of a port to an even slice of
# the traffic that is being simulated through the interface.
# In order to try to make this more realistic, we will try to actually scale
# the measured traffic on a port by a factor which is derived by comparing
# it to the average simulated traffic on the interface
# This should be changed to using the pre-modified measured traffic on the link
print "[$SCRIPT_NAME] Processing LAG members...\n";
my $ports = $plan->getTable("<ports>");
my $portTraff = $plan->getTable("<portTraffic>");
my %portTraffLookup = ();
my %portChannelLookup = ();

# First make sure we can look up the row for the port traffic
# We should already have a way to look up the traffic row for
# that port's InterfaceTraffic and NetIntInterfaceTraffic
foreach my $r ($portTraff->getRows) {
   my $node = $portTraff->getEntry($r,"Node");
   my $port = $portTraff->getEntry($r,"Port");
   my $q = '';
#RB#   my $portTraff = $portTraff->getEntry($r,"TraffMeas");
   $portTraffLookup{"$node $port $q"} = $r;
}


foreach my $r ($ports->getRows) {
   my $node = $ports->getEntry($r,'Node');
   my $port = $ports->getEntry($r,'Port');
   my $active = $ports->getEntry($r,"Active");
   my $parent = $ports->getEntry($r,'Interface');
   my $tags = $ports->getEntry($r,'Tags');
   next unless defined($parent);
   # keep track of all the members of each LAG
   push(@{$portChannelLookup{"$node $parent"}},$r);
}

# Each port gets the same share of traffic unless the LAG has 
# been tagged as an imbalanced  LAG, in which case it will have 
# some randomization applied.
foreach my $key (keys(%portChannelLookup)) {
   my ($node,$parent) = split(/ /,$key);
   my $q = '';
   my $numPorts = @{$portChannelLookup{$key}};
   my $parentRow = $interfaceLookup{"$node $parent"};
   if (!defined($numPorts) || !defined($parentRow)) {
      print "WARNING: Something went wrong processing LAG $key\n";
      next;
   }
   my $parentTag = $parentRow->get_value('Tags') || '';
   my $traffRow = $intTraffLookup{"$node $parent $q"};
   if (!defined($traffRow)) {
      print "WARNING: Can't find traffic for $node $parent !!!\n";
   }
   my $parentTraff = $traffRow->get_value('TraffMeas');
   next unless defined($parentTraff);
   my $i=0;
   my $avgPort = $parentTraff / $numPorts; # Average traffic per port
   # Process each port on a per-LAG interface basis
   foreach my $portRow (@{$portChannelLookup{$key}}) {
      my $node = $portRow->get_value('Node');
      my $port = $portRow->get_value('Port');
      my $traff = 0;
      # If this is a special imbalanced LAG, use the imbalancer to get traff
      if ($parentTag =~ /LagImbalance/i) {
         my $factor = (Imbalancer($numPorts))[$i];
         $traff = $factor * $parentTraff;
         $i++;
      }
      # Else it gets an equal share of traffic
      else { $traff = $avgPort; }

      # Now that we have the value we want, we just need to make sure
      # we set it everywhere.
      my $portTraffRow = $portTraffLookup{"$node $port $q"};
      $portTraffRow->set_value('TraffMeas',$traff); 
      my $portNetIntTraffRow = $netIntIntTraffLookup{"$node $port $q"};
      $portNetIntTraffRow->set_value('TraffMeas',$traff); 
   }
}

# In order to get the right traffIn values for the port channels we
# must go through the port circuits.
my $portCircuits = $plan->get_table('<PortCircuits>');
foreach my $r ($portCircuits->getRows) {
   my $nodeA = $r->get_value('NodeA');
   my $portA = $r->get_value('PortA');
   my $nodeB = $r->get_value('NodeB');
   my $portB = $r->get_value('PortB');
   my $q = '';
   my $portTraffRowA = $portTraffLookup{"$nodeA $portA $q"}; 
   my $portNetIntTraffRowA = $netIntIntTraffLookup{"$nodeA $portA $q"}; 
   my $traffA = $portTraffRowA->get_value('TraffMeas');
   my $portTraffRowB = $portTraffLookup{"$nodeB $portB $q"}; 
   my $portNetIntTraffRowB = $netIntIntTraffLookup{"$nodeB $portB $q"}; 
   my $traffB = $portTraffRowB->get_value('TraffMeas');
   $portNetIntTraffRowA->set_value('NetIntInTraffMeas',$traffB);
   $portNetIntTraffRowB->set_value('NetIntInTraffMeas',$traffA);
}

# Get rid of demands 
$plan->delete_table("<Demands>");
$plan->delete_table("<DemandTraffic>");

# ---- Output Section -------
$PLNFILE = $arg{'-out-file'};
$TABFILE = "";
if ($PLNFILE =~ /\.pln$/) {
   $TABFILE = $PLNFILE . "-" . time() . "-tmp.txt";
   $plan->print($TABFILE);
   system ("\"$MATE_IMPORT\" -plan-file \"$TABFILE\" -out-file \"$PLNFILE\"");
   push(@cleanup,$TABFILE);
}
else { $plan->print($PLNFILE); }

foreach my $f (@cleanup) { unlink("$f"); }

exit;

# This subroutine basically returns a random set of numbers which add up to 1.
# The number of values to use/return is passed as an argument
# The returned set is applied to port channels so that each of them will have
# a random share of the LAG's total traffic.  To keep things from being too
# chaotic, the list is sorted before being returned.
sub Imbalancer {
   my $num = shift;
   return unless defined($num);
   my @ar=();
   my @dist=();

   my $sum=0;
   for (my $i=1; $i <= $num; $i++) {
        my $val = rand;
        push(@ar,$val);
        $sum += $val;
   }

   for (my $i=1; $i <= $num; $i++) {
        my $val = $ar[$i -1] / $sum;
	push(@dist,$val);
   }
   return(sort {$b<=>$a} @dist);
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
