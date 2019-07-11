#!/usr/bin/perl -w
#==============================================================================
# Agilent U1241AN Data Retrieval and Control Utility          
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
#==============================================================================
use strict;
use warnings;
use bytes;
use Getopt::Long;
use Device::SerialPort;
# use Data::Dumper;
use Time::HiRes qw ( sleep );
use POSIX qw(strftime);
use feature qw{ switch };

no if $] >= 5.018, warnings => "experimental::smartmatch";

# Change these to change default behaviors
my $device = "/dev/ttyUSB0";
my $debug = 0;

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

# cheating - used to shorten interval time.
my $func;
my $func2;

# Set flags and options where needed
# from the command line.
GetOptions (

  "csv|c" => \$csv, 
  "debug|d" => \$debug,
  "help|h" => \$help,
  "interval|i=s" => \$interval,
  "port|p=s" => \$device,

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

system('/bin/stty -F ' . $device . ' clocal cs8 cread raw -parenb -cstopb min 0 ignpar')  == 0 || die;

#$port->dtr_active(0);
#$port->rts_active(1);
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

Agilent U1241AN Data Retrieval and Control Utility          
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

  my $timeout = shift;

  # We need time for the meter to respond.
  sleep $timeout;

  my ($count,$got)=$port->read(1);
  my $str = $got;
  my $cnt = $count;

  while ($count > 0) {

    ($count,$got)=$port->read(1);
    $str .= $got;
    $cnt += $count;

  }

  # Ensuring good reception.
  if ($debug) {

    my $debugstr = $str;
    $debugstr =~ s/([^?])/sprintf("%02X ",ord($1))/ge;
    print "DEBUG: Received: $debugstr\n"; 

  }

  return $str;
}

#####
#
# command - Send command, check status, return requested data.
#
#####
sub command {

  my $command = shift;
  my $timeout = shift;

  # Clear the input buffer.
  my $garbage = getresponse(0);
  if ( $debug && $garbage ) { 

    $garbage =~ s/\n//g;
    $garbage =~ s/\r//g;

    print "DEBUG: Garbage collected was \"$garbage\".\n";
  }

  # Query the meter and get a response.
  $port->write("$command\n");
  $port->write_drain;
  if ( $debug ) { print "DEBUG: Command \"$command\" sent.  Awaiting response.\n"; }

  # Fetch the returned data, keep trying if it returns nothing.
  my $returnstring = getresponse($timeout);
  $returnstring =~ s/\n//g;
  $returnstring =~ s/\r//g;

  if ( $debug ) { print "DEBUG: Command returned \"$returnstring\".\n"; }

  if ( ! $returnstring ) { die "FATAL: Is the meter turned on, and connected?\n"; }
  # Check error states, just in case.
  $port->write("SYST:ERR?\n");
  $port->write_drain;

  $garbage = getresponse(0.15);
  $garbage =~ s/\n//g;
  $garbage =~ s/\r//g;

  if ( $garbage =~ m/\+0,\"No err/ ) {
     if ( $debug ) { print "DEBUG: Error status was \"$garbage\".\n"; }
  } else {
    die "FATAL: Meter returned error \"$garbage\".  Please check the\n       meter's settings and try again.\n";
  }

  return $returnstring;

}

#####
#
# translatemeasurement - Translate meter output into real units.
# printmeasurement - Pretty prints the retrieved measurement.
#
#####

sub translatemeasurement {

  my $rawunits = shift;

  if ( $debug ) { print "DEBUG: Raw measurement text is \"$rawunits\".\n"; }

  # Translate from machine-speak to better symbols.
  given ( $rawunits ) {

    when ( /VOLT:AC/ ) { return "VAC"; }
    when ( /VOLT/ ) { return "VDC"; }
    when ( /DIOD/ )    { return "VDC"; }
    when ( /FREQ/ )    { return "HZ"; }
    #when ( /per/ )     { return "Sec"; }
    when ( /RES/ )     { return "Ohm"; }
    when ( /CONT/ )    { return "Ohm"; }
    when ( /CURR:AC/ ) { return "AAC"; }
    when ( /CURR/ ) { return "ADC"; }
    when ( /CAP/ ) { return "F"; }
    when ( /T1:K CEL/ ) { return "°C"; }
    when ( /T1:K FAR/ ) { return "°F"; }
    when ( /CPER/ ) { return "%"; }

    default { die "FATAL: Unexpected unit of measurement \"$rawunits\".\n"; }

  };  
  
}

sub printmeasurement {

  my $measure = shift;

  # clean up and split measurement data
  my @measure = (split ',', $measure);

  $measure[1] = "\"". translatemeasurement(command("CONF?", 0.2)) . "\"";
  $measure[0] = sprintf("%.10g", $measure[0]);

  # Cover 'Offline'
  if ($measure[0] eq "9.9e+37") { $measure[0] = "Offline"; }

  # If it's CSV, let's give them what they want.
  if ( $csv ) {

    $measure = "$measure[0],$measure[1]";
    
    print "\"" . strftime("%D %T", localtime) . "\"," . "$measure\n";

  } else {

    if ( defined $interval ) { 

      $measure = "$measure[0] $measure[1]";
      $measure =~ s/\"//g;

      print `clear`;
      print "Agilent U1240 Series\n"; 
      print "-----------------------------\n";
      print sprintf("%25s","$measure\n");
      print "-----------------------------\n";
      print sprintf("%30s",strftime("%D %T", localtime) . "\n");

    } else {

        $measure = "$measure[0] $measure[1]";

      print strftime("%D %T", localtime) . "\t$measure\n";
 
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

  if ( defined $interval && $interval < 1 ) { $interval = 1 };

  while ( 1 ) {
    
    # It should only take 0.3 seconds to get the next reading 
    # including errors, if any.
    my $debugstr = sleep ( $interval - 0.675 );
    if ( $debug ) { print "DEBUG: Slept $debugstr seconds.\n"; }

    printmeasurement(command('FETC?', 0.15));

  }

} else {

    printmeasurement(command('FETC?', 0.15));
  
}
 
