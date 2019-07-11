#!/usr/bin/perl -w
#==============================================================================
# BK Precision 2831E/5491B Data Retrieval and Control Utility          
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
use Data::Dumper;
use POSIX qw(strftime);
use feature qw{ switch };

no if $] >= 5.018, warnings => "experimental::smartmatch";

# Change these to change default behaviors
my $device = "/dev/ttyUSB0";
my $debug; # = 1;

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

BK Precision 2831E/5491B Data Retrieval and Control Utility          
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
  my $timeout = shift;

  # Handle the one special case command here.
  # By definition, system reset never returns.
  if ($command eq '*RST') { 
    if ( $debug ) { print "DEBUG: System reset requested.  Sleeping two seconds.\n"; }
    sleep 2;
    return;

   };

  # Query the meter and get a response.
  $port->write("$command\r");
  $port->write_drain;
  if ( $debug ) { print "DEBUG: Command \"$command\" sent.  Awaiting response.\n"; }

  # Fetch the returned data, keep trying if it returns nothing.
  my @returnstring = getresponse($timeout);

  # Verify that the comand actually ran successfully.
  $port->write("SYSTEM:ERROR?\r");
  $port->write_drain;
  my @errorstring = getresponse(1);
  my $errorstring = join('',@errorstring);
  $errorstring =~ s/\n//g;

  if ( ! @errorstring ) { die "FATAL: Is the meter connected, and turned on?\n"; }

 
  if ( $errorstring eq "NO ERROR!" ) {
    
    if ( $debug ) { print "DEBUG: Command \"$command\" OK\n"; }
 
  } else {
  
    die "FATAL:  Meter unexpectedly returned \"$errorstring\" in response to command \"$command\".\n";

  }

  my $returnstring = join('',@returnstring);
     $returnstring =~ s/\n//g;

  if ( $debug ) { print "DEBUG: Command returned \"$returnstring\".\n"; }

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

    when ( /volt:ac/ ) { return "VAC"; }
    when ( /volt:dc/ ) { return "VDC"; }
    when ( /diod/ )    { return "VDC"; }
    when ( /freq/ )    { return "HZ"; }
    when ( /per/ )     { return "Sec"; }
    when ( /res/ )     { return "Ohm"; }
    when ( /cont/ )    { return "Ohm"; }
    when ( /curr:ac/ ) { return "AAC"; }
    when ( /curr:dc/ ) { return "ADC"; }
    default { die "FATAL: Unexpected unit of measurement \"$rawunits\".\n"; }

  };  
  
}

sub printmeasurement {

  my $measure = shift;

  # clean up and split measurement data
  my @measure = (split ',', $measure);


  # truncate any special characters at the end of the returned string.
  if ($measure[1]) { 

#    $measure[3] = "\"" . translatemeasurement(command("FUNC2?", 1)) . "\""; 
    $measure[3] = "\"$func2\""; 
    $measure[2] = sprintf("%.5g", $measure[1]);
#    $measure[1] = "\"" . translatemeasurement(command("FUNC?", 1)) . "\"";
    $measure[1] = "\"$func\"";
    $measure[0] = sprintf("%.5g", $measure[0]);

  } else {

#    $measure[1] = "\"" . translatemeasurement(command("FUNC?", 1)) . "\"";
    $measure[1] = "\"$func\"";
    $measure[0] = sprintf("%.5g", $measure[0]);

  }

  # If it's CSV, let's give them what they want.
  if ( $csv ) {

    $measure = join (',', @measure);
    
    print "\"" . strftime("%D %T", localtime) . "\"," . "$measure\n";

  } else {

    if ( $interval ) { 

      if ($measure[3]) {
        $measure = "$measure[0] $measure[1]\t$measure[2] $measure[3]";
      } else {
        $measure = "$measure[0] $measure[1]";
      }

      $measure =~ s/,/ \t/g;
      print `clear`;
      print "BK Precision 2831E / 5491B\n"; 
      print "-----------------------------\n";
      print sprintf("%25s","$measure\n");
      print "-----------------------------\n";
      print sprintf("%30s",strftime("%D %T", localtime) . "\n");

    } else {

      if ($measure[3]) {
        $measure = "$measure[0] $measure[1]\t$measure[2] $measure[3]";
      } else {
        $measure = "$measure[0] $measure[1]";
      }

      print strftime("%D %T", localtime) . "\t$measure\n";
 
    }

  }

}

#####
# This should be the main affair
#####

# This is the default behavior.

  if ( $interval < 4 ) { die "FATAL: The interval between readings needs to\n       at least 4 seconds.\n\n"; }

# Initial meter queries, two seconds, for units:
$func = translatemeasurement(command("FUNC?", 1));
$func2 = translatemeasurement(command("FUNC2?", 1));
 
if ( defined $interval ) {

  if ( $debug ) {
    print "DEBUG: Supposed to sleep for $interval seconds.\n";  
  }

  $interval -= 4 - 1;
  if ( $interval < 0 ) { $interval = 0; }

  while ( 1 ) {
    printmeasurement(command('FETCH?', 2));
    sleep ( $interval );
  }

} else {

  printmeasurement(command('FETCH?', 2));
  
}
 
