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
use Data::Dumper;

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

my $backlight;
my $csv;
my $help;
my $interval;
my $port;
my $led;

# Set flags and options where needed
# from the command line.
GetOptions (

  "backlight|b" => \$backlight,
  "csv|c" => \$csv, 
  "debug|d" => \$debug,
  "help|h" => \$help,
  "interval|i=s" => \$interval,
  "led|l" => \$led,
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
$port->baudrate(115200);
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

Fluke 280-series Data Retrieval and Control Utility          
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
  --led	      -l	    Flash the power LED, with --interval seconds.
  --backlight -b	    Set backlight on, high, or off.

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

  pop @retval;
  return @retval;

}

#####
#
# getmeasurement   - Retrieve the primary measurement.
# printmeasurement - Pretty prints the retrieved measurement.
#
#####
sub getmeasurement {

    return(join('', command("QDDA")), 0);

}

sub printmeasurement {

    my $measure = shift;
    my @measure = (split ',', $measure);

    # Here comes a metric buttload of data to unravel.
    my $pri_measure = shift @measure;     # Primary Measurement
    my $sec_measure = shift @measure;     # Secondary measurement
    my $rangestate  = shift @measure;     # Are we autoranging or not?
    my $baseunit    = shift @measure;     # Base measurement unit
    my $rangenumber = shift @measure;     # Base range number
    my $rangemulti  = shift @measure;     # Base unit multiplier
    my $highvoltage = shift @measure;     # High voltage present or not
    my $readstart   = shift @measure;     # Epoch start of min/max recording
    my $num_modes   = shift @measure;     # Number of measurement modes
 
    my %modes;

    if ( defined $debug ) {
      print "DEBUG: Primary measurement mode is $pri_measure.\n";
      print "DEBUG: Secondary measurement mode is $sec_measure.\n";
    }
     
    # Load up the hash with measurement modes
    for (my $i = 0; $i < $num_modes; $i++) {
      $modes{$i} = shift @measure;
      if ( defined $debug ) { print "DEBUG: $modes{$i} mode.\n"; }
    }

    my $num_reading = shift @measure;     # Number of readings taken

    my %reading_id;
    my %reading_value;
    my %reading_unit;
    my %reading_unit_prefix;
    my %reading_unit_multiplier;
    my %reading_decimal_places;
    my %reading_digits;
    my %reading_state;
    my %reading_attribute;
    my %reading_timestamp;

    for (my $i = 0; $i < $num_reading; $i++) {
    
      $reading_id{$i} = shift @measure;

      $reading_value{$i} = shift @measure;
      $reading_unit{$i} = shift @measure;
      $reading_unit_multiplier{$i} = shift @measure;

      # Tack this on for readability's sake.
      if ($reading_unit_multiplier{$i} eq "9" ) { $reading_unit_prefix{$i} = "G" } 
      if ($reading_unit_multiplier{$i} eq "6" ) { $reading_unit_prefix{$i} = "M" } 
      if ($reading_unit_multiplier{$i} eq "3" ) { $reading_unit_prefix{$i} = "K" } 

      if ($reading_unit_multiplier{$i} eq "0" ) { $reading_unit_prefix{$i} = "" } 
      if ($reading_unit_multiplier{$i} eq "-3") { $reading_unit_prefix{$i} = "m" }
      if ($reading_unit_multiplier{$i} eq "-6") { $reading_unit_prefix{$i} = "u" }
      if ($reading_unit_multiplier{$i} eq "-9") { $reading_unit_prefix{$i} = "n" }

      $reading_decimal_places{$i} = shift @measure;
      $reading_digits{$i} = shift @measure;
      $reading_state{$i} = shift @measure;
      $reading_attribute{$i} = shift @measure;
      $reading_timestamp{$i} = shift @measure;

    }

    # Do proper output this time.   
    if ( defined $csv ) {

      print "\"" . strftime("%D %T", localtime) . "\",";

      if ( $sec_measure ne "NONE" ) { 
        print "\"$sec_measure\",";
      } else {
        print "\"$pri_measure\",";
      }

      for (my $i = 0; $i < $num_reading; $i++) {

        if ($reading_state{$i} eq "NORMAL") {

          print "\"$reading_id{$i}\"," . sprintf("%.$reading_decimal_places{$i}f", $reading_value{$i} * (10 ** -$reading_unit_multiplier{$i})) . ",\"$reading_unit_prefix{$i}$reading_unit{$i}\",\"$reading_attribute{$i}\",";

        } else {

          print "\"$reading_id{$i}\",\"-----\",\"$reading_state{$i}\",\"$reading_attribute{$i}\",";

        }     

      }

      if ( $num_modes == 0 ) { print "\"RUNNING\","; }

      for (my $i = 0;$i < $num_modes;$i++) {

        print "\"$modes{$i}\",";

        if ( $modes{$i} eq "MIN_MAX_AVG" ) {
          print "\"" . scalar localtime($readstart + 18000) . "\","; 
        }
        
     }
        if ( $highvoltage eq "ON" ) { print "\"HV\""; } else { print "\"\"\n"; }
 
    print "\n";

    } else { 

      if (! defined $debug ) { print `clear`; }
      print " Fluke 287/289 Multimeter" . sprintf("%55s",strftime("%D %T", localtime) . "\n");
      print "--------------------------------------------------------------------------------\n\n";

      if ( $sec_measure ne "NONE" ) {
        print "Measuring $sec_measure:\n\n";
      }


      for (my $i = 0; $i < $num_reading; $i++) {

        if ( defined $debug ) { print "DEBUG: $reading_value{$i}\n"; }

        print " $reading_id{$i}:";
        if ( $reading_id{$i} eq "LIVE" ) { print "\t"; }
       
        if ( $reading_state{$i} ne "NORMAL" ) { 

          print "\t------\t";
        
        } else {
         
          print "\t " . sprintf("%.$reading_decimal_places{$i}f", $reading_value{$i} * (10 ** -$reading_unit_multiplier{$i})) . "\t$reading_unit_prefix{$i}$reading_unit{$i}";

          if ( $reading_state{$i} ne "NORMAL" ) { 
            print "\t$reading_state{$i}"
          }
          if ( $reading_attribute{$i} ne "NONE" ) { 
            print "\t$reading_attribute{$i}"
          }

       }

        print "\n";


      }

      print "\n";

      for (my $i = 0; $i < $num_modes; $i++) {

        if ( $modes{$i} eq "HOLD" ) { 
          print sprintf("%80s", " Meter is holding" . "\n");
        }

        if ( $modes{$i} eq "AUTO_HOLD" ) { 
          print sprintf("%80s", " Meter is holding (AutoHOLD)" . "\n");
        }

        if ( $modes{$i} eq "MIN_MAX_AVG" ) {
          print sprintf("%80s", "Min/Max began at " . scalar localtime($readstart + 18000) . "\n"); 

        }

      }

      print "--------------------------------------------------------------------------------\n";
      if ( $highvoltage eq "ON" ) { print sprintf("%80s", "ALERT: High Voltage\n") . "\n"; } else { print "\n"; }
 
    }

}

#####
# This should be the main affair
#####

# This is the default behavior.

# Toggle the backlight on, high, or off.
if ( defined $backlight ) {
  command("PRESS BACKLIGHT");
  exit 0;
}

if ( defined $interval ) {

  if ( $debug ) {
    print "DEBUG: Supposed to sleep for $interval seconds.\n";  
  }

  while ( 1 ) {

    # Blink the power LED with an interval of $interval seconds.
    if ( defined $led ) {

      if ( $led == 1 ) {   
        command("LEDT ON"); 
        $led = 0;
      } else {
        command("LEDT OFF");
        $led = 1;
     }

    } else {

      printmeasurement(getmeasurement());

    }

      sleep ( $interval - 1 );

  }
  
} else {

    printmeasurement(getmeasurement());

}

