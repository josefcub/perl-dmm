#!/usr/bin/perl -w
#==============================================================================
# Fluke 89-series Data Retrieval and Control Utility          
#------------------------------------------------------------------------------
#
# This is a utility for requesting data from a Fluke 89IV, 187/189, or 287/289.
#
# Options:
#
#  --csv       -c            Outputs meter data in CSV format
#  --debug     -d            Shows Debugging Output
#  --help      -h            This text
#  --interval  -i num        Takes a new reading every num seconds
#  --port      -p /dev/file  Reads from filename instead of the
#
#==============================================================================
use strict;
use warnings;
use bytes;
use Getopt::Long;
use Device::SerialPort;
use POSIX qw(strftime);

# Change these to change default behaviors
my $device = "/dev/ttyUSB0";
my $debug;

#========================================
# NOTHING BELOW THIS LINE NEEDS CHANGED.
#========================================

#=====================================
# Global variables and module
# definitions
#=====================================

my $csv;
my $help;
my $interval;
my $port;
my $screen;

# Set flags and options where needed
# from the command line.
GetOptions (

  "csv|c" => \$csv, 
  "debug|d" => \$debug,
  "help|h" => \$help,
  "interval|i=s" => \$interval,
  "port|p=s" => \$device,
  "screen|s" => \$screen,

) or die "Huh? Type\"$0 --help\" for help.\n";  #"

if ( $help ) { showhelp(); }

#======================================
# Hardware Initialization
#======================================

# It's important that everything be 8-bit bytes.  
binmode STDIN, ":bytes";
binmode STDOUT, ":unix";

$port = Device::SerialPort->new($device)
  or die "FATAL: Can't open $device: $!\n";
$port->databits(8);
$port->baudrate(9600);
$port->parity("none");
$port->stopbits(1);
$port->datatype('raw');
$port->dtr_active(0);
$port->rts_active(1);
$port->purge_all;
$port->purge_rx;
$port->purge_tx;

#======================================
# Subroutines
#======================================

#####
#
# showhelp - Show helpful message.
#
#####
sub showhelp {

print STDERR <<HELPDOC;

Fluke 89-series Data Retrieval and Control Utility          
-----------------------------------------------------------------

Usage:

$0 [OPTIONS]

Options:

  --csv       -c            Outputs meter data in CSV format
  --debug     -d            Shows Debugging Output
  --help      -h            This text
  --interval  -i num        Takes a new reading every num seconds
  --port      -p /dev/file  Reads from filename instead of the
                            default device, $device.

------------------------------------------------------------------

HELPDOC

exit 0;

}

#####
#
# getresponse - Get a response from the meter, if any.
# 
#####
sub getresponse {

  # We need time for the meter to respond.
  sleep 1;

  my ($count,$got)=$port->read(1);
  my $str = $got;
  my $cnt = $count;

  while ($count > 0) {

    ($count,$got)=$port->read(1);
    $str .= $got;
    $cnt += $count;

  }

  if ($debug) {
    print "DEBUG: Read $cnt bytes from input buffer.\n";
    my $debugstr=$str;
    $debugstr =~ s/([^?])/sprintf("%02X ",ord($1))/ge;
    print "DEBUG: Received: $debugstr\n"; 
  }

  my @outstr = split('', $str);

  return @outstr;
}

#####
#
# command - Send command, check status, return requested data.
#
#####
sub command {

  my $command = shift;

  $port->write("$command\r");
  $port->write_drain;
  my @retval = getresponse();

  my $returncode = shift @retval;
  shift @retval;

  if ( ! defined $returncode ) { die "FATAL: Is the meter connected, and turned on?\n"; }
  if ( $returncode > 0 ) {

    die "FATAL: Meter returned error code $returncode in response to command \"$command\".\n";

  } else {

    if ( $debug ) {
      print"DEBUG: command \"$command\" returned value $returncode.\n";
    }

} 

  return @retval;

}

#####
#
# getmeasurement   - Retrieve the primary measurement.
# printmeasurement - Pretty prints the retrieved measurement.
#
#####
sub getmeasurement {

 return(substr(join('', command("QM")), 3));

}

sub printmeasurement {

  my $measure = shift;

  # If it's CSV, let's give them what they want.
  if ( $csv ) {

    my @measure = (split ' ', $measure);
    my $lvalue = shift @measure;

    print "\"" . strftime("%D %T", localtime) . "\"," . $lvalue . ",\"@measure\"\n"

  } else {

    if ( $interval ) { 

      print `clear`; 
      print "------------------------\n";
      print sprintf("%20s","$measure\n");
      print "------------------------\n";
      print sprintf("%25s",strftime("%D %T", localtime) . "\n");

    } else {

      print strftime("%D %T", localtime) . "\t$measure\n";
 
    }

  }

}

#####
#
# getscreen   - Retrieve the primary measurement.
# printscreen - Pretty prints the retrieved measurement.
#
#####
sub getscreen {

  # Define these up front, we'll be returning them later.  
  my $privalue;
  my $priprefix = "";
  my $priunits = "";
  my $secvalue;
  my $secprefix = "";
  my $secunits = "";
  my $modes = "";

  # Retrieve a data frame and sanity check it.
  my @data = command("QD 0"); 
  if ( $data[0] ne "Q" || $data[1] ne "D" || $data[2] ne "," ) {
    die "FATAL:  This wasn't the measurement we were looking for: @data\n";
  }

  # Get our value, sign the integer, and scale it correctly.
  $privalue = unpack("N", pack("C4", ord($data[10]), ord($data[9]), ord($data[8]), ord($data[7])));
  if ( $debug ) {  print "DEBUG: Raw 1   : $privalue\n"; }

  # Apparently $data[11] and [17] are signed char.  Fix that.
  my $decimals;
  if ( ord($data[11]) > 127 ) { $decimals = ord($data[11]) - 127; } else { $decimals = ord($data[11]); }

  # Only sign and scale it if it's a valid number.
  #                OL                         LEADS                      OPEN
  if ($privalue == 1879048221 || $privalue == 1879048225 || $privalue == 1879048214) {
     $privalue = "\"Offline\"";
  } else {
    $privalue = unpack("s", pack("S", $privalue));
    $privalue = $privalue * 10 ** (-$decimals);
  }

  # Do the same for the secondary value, if any.
  $secvalue = unpack("N", pack("C4", ord($data[16]), ord($data[15]), ord($data[14]), ord($data[13])));
  if ( $debug ) {  print "DEBUG: Raw 2   : $secvalue\n"; }

  # Fix that here too.
  if ( ord($data[17]) > 127 ) { $decimals = ord($data[17]) - 127; } else { $decimals = ord($data[17]); }
  
  # Only sign and scale it if it's a valid number.
  #                OL                         LEADS                      OPEN                       NONE
  if ($secvalue == 1879048221 || $secvalue == 1879048225 || $secvalue == 1879048214 || $secvalue == 1879048193) {
     $secvalue = "\"N/A\"";
  } else {
    $secvalue = unpack("s", pack("S", $secvalue));
    $secvalue = $secvalue * 10 ** (-$decimals);
  }

  # Catch the knob position, for calculating units and such.
  my $knob = ord($data[37]);
  my $alt40 = ord($data[40]);

  if ( $debug ) { print "DEBUG: Knob is on " . $knob . "\n"; }

  # Settle the primary measurement unit prefix
  if ( ord($data[12]) == 253 ) { $priprefix = "μ" };
  if ( ord($data[12]) == 255 ) { $priprefix = "m" };
  if ( ord($data[12]) == 0 )   { $priprefix = "" };
  if ( ord($data[12]) == 1 )   { $priprefix = "k" };
  if ( ord($data[12]) == 2 )   { $priprefix = "M" };
 
  # Corner cases for the primary measurement prefix and unit
  if (($knob == 10 || $knob == 12) && (ord($data[12]) == 253)) { $priprefix="n"; } # nanoFarads
  if (($knob == 22) && (ord($data[12]) == 254)) { $priprefix="μ"; } # microAmps
  if ($knob > 64 && ord($data[12]) > 4) { $priprefix = ""; }

  # Settle the secondary measurement unit prefix
  if ( ord($data[18]) == 253 ) { $secprefix = "μ" };
  if ( ord($data[18]) == 255 ) { $secprefix = "m" };
  if ( ord($data[18]) == 0 )   { $secprefix = "" };
  if ( ord($data[18]) == 1 )   { $secprefix = "k" };
  if ( ord($data[18]) == 2 )   { $secprefix = "M" };

  if ( $debug ) { print "DEBUG: Raw primary prefix is " . ord($data[12]) . "\n"; }
  if ( $debug ) { print "DEBUG: Raw secondary  prefix is " . ord($data[18]) . "\n"; }

  # Corner cases for the secondary measurement prefix and unit
  if (($knob == 10 || $knob == 12) && (ord($data[18]) == 253)) { $secprefix="n"; }
  if (($knob == 22) && (ord($data[18]) == 254)) { $secprefix="μ"; } # microAmps
  if ($knob > 64 && ord($data[18]) > 4) { $secprefix = ""; }

  # Measurement units by knob position
  if ($knob == 0) { die "ERROR: Meter is in VIEW MEMORY mode.  Please change the knob and try again.\n"; }
  if ($knob == 1)   { $priunits = "V AC"; }
  if ($knob == 2)   { $priunits = "mV AC"; }
  if ($knob == 3)   { $priunits = "V DC"; }
  if ($knob == 4)   { $priunits = "mV DC"; }
  if ($knob == 5)   { $priunits = "V AC"; $secunits = "V DC"; }
  if ($knob == 6)   { $priunits = "mV AC"; $secunits = "mV DC"; }
  if ($knob == 9)   { $priunits = "Ω"; }
  if ($knob == 10)  { $priunits = "S"; }
  if ($knob == 11)  { $priunits = "Ω"; }
  if ($knob == 12)  { $priunits = "F"; }
  if ($knob == 13)  { $priunits = "V DC"; }
  if ($knob == 15)  { $priunits = "A AC"; }
  if ($knob == 16)  { $priunits = "A AC"; }
  if ($knob == 17)  { $priunits = "A DC"; }
  if ($knob == 18)  { $priunits = "A DC"; }
  if ($knob == 19)  { $priunits = "μA DC"; }
  if ($knob == 20)  { $priunits = "A AC"; $secunits = "A DC"; }
  if ($knob == 21)  { $priunits = "A AC"; $secunits = "A DC"; }
  if ($knob == 22)  { $priunits = "μA AC"; $secunits = "μA DC"; }
  if ($knob == 26)  { $priunits = "°C"; }
  if ($knob == 27)  { $priunits = "°F"; }
  if ($knob == 65)  { $priunits = "Hz"; $secunits = "V AC"; }
  if ($knob == 66)  { $priunits = "Hz"; $secunits = "V AC"; }
  if ($knob == 130) { $priunits = "% Duty Cycle"; $secunits = "Hz"; }
  if ($knob == 194) { $priunits = "ms"; $secunits = "Hz"; }
  
  #####
  # Corner cases that affect both measurement units and prefixes
  #####

  # No data
  if ($privalue eq "\"Offline\"") { $priprefix = ""; $priunits = ""; }
  if ($secvalue eq "\"N/A\"") { $secprefix = ""; $secunits = ""; }

  # DC V 2nd Alt - DC V / AC V
  if ( ($knob == 5) && (ord($data[39]) & 2) ) { $priunits = "V DC"; $secunits = "V AC"; };
  if ( ($knob == 6) && (ord($data[39]) & 2) ) { $priunits = "mV DC"; $secunits = "mV AC"; };

  # DC V 3rd Alt - V AC+DC
  if ( ($knob == 5) && (ord($data[39]) & 2) && (ord($data[39]) & 1) ) { $priunits = "V AC+DC"; $secunits = ""; };
  if ( ($knob == 6) && (ord($data[39]) & 2) && (ord($data[39]) & 1) ) { $priunits = "mV AC+DC"; $secunits = ""; };

  # AC V 2nd Alt - AC V / dB
  if ( ($knob == 2) && (ord($data[40]) & 16) ) { $priunits = "mV AC"; $secunits = "dB"; };

  # DC A 2nd Alt - DC A / AC A
  if ( ($knob == 22 || $knob == 21 || $knob == 20) && (ord($data[39]) & 2) ) { $priunits = "A DC"; $secunits = "A AC"; };

  # DC V 3rd Alt - V AC+DC
  if ( ($knob == 20) && (ord($data[39]) & 2) && (ord($data[39]) & 1) ) { $priunits = "A AC+DC"; $secunits = ""; };
  if ( ($knob == 21) && (ord($data[39]) & 2) && (ord($data[39]) & 1) ) { $priunits = "A AC+DC"; $secunits = ""; };
  if ( ($knob == 22) && (ord($data[39]) & 2) && (ord($data[39]) & 1) ) { $priunits = "A AC+DC"; $secunits = ""; };

  # Relative detla and delta percent
  if ($alt40 & 1) {
    $secprefix = $priprefix;
    $secunits = $priunits;
    $priprefix = "Δ" . $priprefix;
  }
  if ($alt40 & 2) {
    $secprefix = $priprefix;
    $secunits = $priunits;
    $priprefix = "Δ%" . $priprefix;
  }

  # dbM/dbV
  if ( ($knob == 1) && ( $alt40 & 8 ) ) {
    $priprefix = "";
    $priunits  = "dB";
    $secunits = "V AC";
  }
  if ( $knob == 2 && ( $alt40 & 8 ) ) {
    $priprefix = "";
    $priunits  = "dB";
    $secunits = "mV AC";
  }

  # Mode alterations, Hz ranges remain normal.
  if (ord($data[38]) & 64) { $modes .= "RE ";}
  if (ord($data[38]) & 128) { $modes .= "FE ";}

  if ( ord($data[33]) & 2 )  { $modes .= "HOLD "; if ( $knob < 32 ) { $secunits = $priunits; } }
  if ( ord($data[33]) & 8 )  { $modes .= "AVG ";  if ( $knob < 32 ) { $secunits = $priunits; } }
  if ( ord($data[33]) & 16 ) { $modes .= "MAX ";  if ( $knob < 32 ) { $secunits = $priunits; } }
  if ( ord($data[33]) & 32 ) { $modes .= "MIN ";  if ( $knob < 32 ) { $secunits = $priunits; } }


  if ( $debug ) { print "DEBUG: Cooked 1 : $privalue $priprefix$priunits\n"; }
  if ( $debug ) { print "DEBUG: Cooked 2 : $secvalue $secprefix$secunits\n"; }

  $priprefix.=$priunits;
  $secprefix.=$secunits; 

  return($privalue,$priprefix,$secvalue,$secprefix,$modes);

}

sub printscreen {

  my $privalue = shift;
  my $priunits = shift;
  my $secvalue = shift;
  my $secunits = shift;
  my $modes = shift;

  if ( $debug) { print "\"DEBUG: \",$privalue,\"$priunits\",$secvalue,\"$secunits\",\"$modes\"\n"; }

   # If it's CSV, let's give them what they want.
   if ( $csv ) {
 
     print "\"" . strftime("%D %T", localtime) . "\",$privalue,\"$priunits\",$secvalue,\"$secunits\",\"$modes\"\n"
 
   } else {
 
     if ( $interval ) {
 
       print `clear`;
       print "----------------------------------\n";
       print "$modes\n";
       print "$privalue $priunits / $secvalue $secunits\n";
       print "----------------------------------\n";
       print sprintf("%35s",strftime("%D %T", localtime) . "\n");
 
     } else {
 
       print strftime("%D %T", localtime) . "\t$privalue $priunits / $secvalue $secunits [$modes]\n";
 
     }
 
   }

}


#####
# This should be the main affair
#####

# This is the default behavior.

if ( defined $interval ) {

  if ( $debug ) {
    print "DEBUG: Supposed to sleep for $interval seconds.\n";  
  }

  if ( defined $screen ) {

    while ( 1 ) {
      printscreen(getscreen());
      sleep ( $interval - 1);
    }

  } else {

    while ( 1 ) {
      printmeasurement(getmeasurement());
      sleep ( $interval - 1 );
    }
  }

} else {

  if ( defined $screen ) {
 
    printscreen(getscreen());

  } else {

    printmeasurement(getmeasurement());

  }

}

