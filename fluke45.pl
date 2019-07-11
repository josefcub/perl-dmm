#!/usr/bin/perl -w
#==============================================================================
# Fluke 45/8808A Data Retrieval and Control Utility          
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
use Data::Dumper;
use POSIX qw(strftime);

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

Fluke 45/8808A Data Retrieval and Control Utility          
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

  # Handle the one special case command here.
  # By definition, system reset never returns.
  if ($command eq '*RST') { 
    if ( $debug ) { print "DEBUG: System reset requested.  Sleeping two seconds.\n"; }
    sleep 2;
    return '=>';
   };

  if ( $debug ) { print "DEBUG: Command \"$command\" sent.  Awaiting response.\n"; }
  # Query the meter and get a response.
  $port->write("$command\r");
  $port->write_drain;
  my @returnstring = getresponse();


  # If nothing's returned, nobody is home.
  if ( ! @returnstring ) { die "FATAL: Is the meter connected, and turned on?\n"; }

  # We need the returned text (if any), and the prompt to
  # determine success.  variable munging!
  my $returnstring = join('',@returnstring);
  @returnstring = split('\n',$returnstring);

  # How much did it actually return?  Some commands
  # don't return text, others do.
  my $n = @returnstring;

  if ( $n == 1 ) {
    $returnstring[1] = $returnstring[0];
  }

  # Ugly hack instead of doing it the right way.
  if ( $returnstring[1] =~ /=>/ ) {
    
    if ( $debug ) { print "DEBUG: Command \"$command\" OK\n"; }
 
  } else {
  
    die "FATAL:  Meter unexpectedly returned:\n\n$returnstring[0]\nin response to command \"$command\".\n";

  }

  return $returnstring[0];

}

#####
#
# getmeasurement   - Retrieve the primary measurement.
# printmeasurement - Pretty prints the retrieved measurement.
#
#####
sub getmeasurement {

 return(command("MEAS?"));

}

sub printmeasurement {

  my $measure = shift;

  # clean up and split measurement data
  $measure =~ s/ /,/g;
  my @measure = (split ',', $measure);
 

  # truncate any special characters at the end of the returned string.
  if ($measure[3]) { 

    $measure[3] = "\"" . substr($measure[3],0,-1) . "\""; 
    $measure[2] = sprintf("%.6g", $measure[2]);
    $measure[1] = "\"" . $measure[1] . "\""; 
    $measure[0] = sprintf("%.6g", $measure[0]);

  } else {

    $measure[1] = "\"" . substr($measure[1],0,-1) . "\""; 
    $measure[0] = sprintf("%.6g", $measure[0]);

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
      print "Fluke 45 / 8808A\n"; 
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

if ( defined $interval ) {

  if ( $debug ) {
    print "DEBUG: Supposed to sleep for $interval seconds.\n";  
  }

  while ( 1 ) {
    printmeasurement(command('MEAS?'));
    sleep ( $interval - 1 );
  }

} else {

  printmeasurement(command('MEAS?'));
  
}
 
