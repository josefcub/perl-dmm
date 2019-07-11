#!/usr/bin/perl -w
#=============================================================================
# TP4000ZC Data Collection Utility                                  2013 AJC
#
# Parse and display data from the TP4000ZC multimeter and relatives, and 
# display in CSV format, or a more human-readable form.  
#
# This was written in two hours, after a few shots of whiskey, on a bet.  
# Write up everything wrong with this implementation, compared to modern best 
# practices.  I guarantee it won't be a short writeup.
#=============================================================================

#========================================
# NOTHING BELOW THIS LINE NEEDS CHANGED.
#========================================

#=====================================
# Global variables and module
# definitions
#=====================================

use strict;
use warnings;
use bytes;
use Getopt::Long;

my $version = "1.00.00";   # self explanatory

my $prefix = '';           # negative sign, etc.
my $measurement = '';      # the measurement itself
my $modifier = ' ';        # kilo, mega, nano, micro
my $units = '';            # ohms, volts, percent, etc.
my $status = '';           # RS-232, other measurement modifiers.

my $csv;                   # Do we want to output CSV?
my $display;		   # Super sekrit display mode
my $single;                # One-shot mode?
my $help;                  # Do we need a help readout?
my $fname;                 # Filename to read from.
my $quiet;                 # Do we want data warnings?

my $influx = '';            # Temporary byte storage;
my $buffer = '';            # Whole data frame storage;

#=====================================
# Global setup area
#=====================================

# Set flags and options where needed
# from the command line.
GetOptions (

  "csv|c" => \$csv, 
  "display|d" => \$display,
  "file|f=s" => \$fname,
  "help|h" => \$help,
  "quiet|q" => \$quiet,
  "single|s" => \$single,

) or die "Huh? Type \"$0 --help\" for help.\n";

# It's important that everything be 8-bit bytes.  
binmode STDIN, ":bytes";
binmode STDOUT, ":unix";

# If the user requested help, oblige them.
if ($help) { 

  print STDERR <<HELPDOC;

TP4000ZC remote data collection utility
Version $version
2013

Usage:

$0 [OPTIONS]

Options:

  --csv	    -c		 Outputs meter data in CSV format
  --display -d           Special demo display mode
  --file    -f filename  Reads from filename instead of stdin
  --help    -h		 This text
  --quiet   -q           Don't scream about bad data.
  --single  -s           Outputs only a single meter reading

Notes:

  If filename is specified, opens and takes input from that file, 
  otherwise stdin is used.

  Timestamps in CSV output are given in unix epoch time, but are 
  human readable in the standard readout mode.

HELPDOC

exit 0;

}

#=====================================
# parser - Parse a 14-byte frame
#=====================================
sub parser {

  # The data frame should be the only argument passed.
  my $input = $_[0];

  # Split it into individual bytes, one per array element.
  my @data = split('', $input);

  # Convert array elements into actual numbers.
  foreach (@data) {

    $_ = oct("0b" . unpack('B8', $_));

  }

  # Validate each byte's sequential identifier header.
  # If one of them is missing or out-of-sequence, then
  # discard the whole frame and error out.
  if ( (( $data[0] & 240 ) >> 4 ) ne 1 ) { return -1 }
  if ( (( $data[1] & 240 ) >> 4 ) ne 2 ) { return -1 }
  if ( (( $data[2] & 240 ) >> 4 ) ne 3 ) { return -1 }
  if ( (( $data[3] & 240 ) >> 4 ) ne 4 ) { return -1 }
  if ( (( $data[4] & 240 ) >> 4 ) ne 5 ) { return -1 }
  if ( (( $data[5] & 240 ) >> 4 ) ne 6 ) { return -1 }
  if ( (( $data[6] & 240 ) >> 4 ) ne 7 ) { return -1 }
  if ( (( $data[7] & 240 ) >> 4 ) ne 8 ) { return -1 }
  if ( (( $data[8] & 240 ) >> 4 ) ne 9 ) { return -1 }
  if ( (( $data[9] & 240 ) >> 4 ) ne 10 ) { return -1 }
  if ( (( $data[10] & 240 ) >> 4 ) ne 11 ) { return -1 }
  if ( (( $data[11] & 240 ) >> 4 ) ne 12 ) { return -1 }
  if ( (( $data[12] & 240 ) >> 4 ) ne 13 ) { return -1 }
  if ( (( $data[13] & 240 ) >> 4 ) ne 14 ) { return -1 }

  # We blank these prior to parsing out the new measurements,
  # just in case.
  $prefix = ' ';
  $measurement = '';
  $modifier = ' ';
  $units = '';
  $status = '';

  #=====================================
  # getnumber - internal subroutine to 
  #             the parser, to return
  #             a numeric from LCD state
  #=====================================
  sub getnumber {
   
    my $high = $_[0];    # High octal 
    my $low = $_[1];     # Low nybble

    if (($high == 0) && ($low == 5))  { return "1"; }
    if (($high == 5) && ($low == 11)) { return "2"; }
    if (($high == 1) && ($low == 15)) { return "3"; }
    if (($high == 2) && ($low == 7))  { return "4"; }
    if (($high == 3) && ($low == 14)) { return "5"; }
    if (($high == 7) && ($low == 14)) { return "6"; }
    if (($high == 1) && ($low == 5))  { return "7"; }
    if (($high == 7) && ($low == 15)) { return "8"; }
    if (($high == 3) && ($low == 15)) { return "9"; }
    if (($high == 7) && ($low == 13)) { return "0"; }
    if (($high == 6) && ($low == 8)) { return "L"; }

    # If all else fails, return a blank space.
    return " ";

  }

  # Assemble the measurement itself from each byte of screen data.

  # First single bit flag is the negative sign
  if ($data[1] & 8) { $measurement .= "-"; $prefix = ''; }

  # Leftmost number
  $measurement .= getnumber (($data[1] & 7), ($data[2] & 15));

  # Do we have a decimal point here?
  if ($data[3] & 8) { $measurement .= "."; }

  # Second leftmost number
  $measurement .= getnumber (($data[3] & 7), ($data[4] & 15));

  # Or here?
  if ($data[5] & 8) { $measurement .= "."; }
  
  # Second rightmost number
  $measurement .= getnumber (($data[5] & 7), ($data[6] & 15));

  # How about here?
  if ($data[7] & 8) { $measurement .= "."; }

  # Rightmost number.
  $measurement .= getnumber (($data[7] & 7), ($data[8] & 15));

  # Per the spec, this is what the other random bits mean
  # in the bitstream, indicating what was measured, and 
  # the order of magnitude of the measurement.
  if ($data[9] & 2) { $modifier .= "kilo"; }
  if ($data[9] & 4) { $modifier .= "nano"; }
  if ($data[9] & 8) { $modifier .= "micro"; }

  if ($data[10] & 2) { $modifier .= "mega"; }
  if ($data[10] & 4) { $units .= "percent"; }
  if ($data[10] & 8) { $modifier .= "milli"; }
  
  if ($data[11] & 4) { $units .= "ohms"; }
  if ($data[11] & 8) { $units .= "farads"; }

  if ($data[12] & 1) { $status .= " Low Battery, "; }
  if ($data[12] & 2) { $units .= "hertz"; }
  if ($data[12] & 4) { $units .= "volts"; }
  if ($data[12] & 8) { $units .= "amps"; }

  if ($data[13] & 4) { $units .= "degrees Celsius"; }

  # These are moved out of logical order for aesthetic 
  # reasons on the resulting string.
  if ($data[0] & 1) { $status .= "RS-232"; }
  if ($data[10] & 1) { $status .= " Buzzer"; }
  if ($data[9] & 1) { $status .= " Diode"; }
  if ($data[11] & 1) { $status .= " Hold"; }
  if ($data[0] & 2) { $status .= " Auto"; }

  # These are here for a very good reason
  if (($data[0] & 4) && ($data[12] & 12)) { $units .= " DC"; }
  if ($data[0] & 8) { $units .= " AC"; }

  # Awkward formatting is awkward.
  if ($data[11] & 2) { $units .= " Δ"; }

  # If we made it this far, we did well!
  return 0;  

}

#=====================================
# outputcsv - Output basic CSV data
#             from parsed frame data.
#=====================================
sub outputcsv {

  if ($modifier eq " mega" ) { $measurement *= 1000000 };
  if ($modifier eq " kilo" ) { $measurement *= 1000 };
  if ($modifier eq " milli") { $measurement *= 0.001 };
  if ($modifier eq " micro") { $measurement *= 0.000001 };
  if ($modifier eq " nano") { $measurement *= 0.000000001 };
  if ($modifier ne " ") { $measurement = sprintf("%.12f", $measurement); }
  print STDOUT time . "," . $measurement . ",\"" . $units . "\",\"" . $status . "\"\n";

}

#=====================================
# output - Print human readable data
#          from parsed measurement
#          frame data.
#=====================================
sub output {

  if ($display) {

    # Change ALL THE THINGS!
    if ($modifier eq " mega" ) { $modifier = "M" };
    if ($modifier eq " kilo" ) { $modifier = "K" };
    if ($modifier eq " milli") { $modifier = "m" };
    if ($modifier eq " micro") { $modifier = "μ" };
    if ($modifier eq " nano")  { $modifier = "n" };
    if ($units eq "volts DC") { $units = "VDC" };
    if ($units eq "volts AC") { $units = "VAC" };
    if ($units eq "volts DC Δ") { $units = "VDCΔ" };
    if ($units eq "volts AC Δ") { $units = "VACΔ" };
    if ($units eq "ohms") { $units = "Ω" };
    if ($units eq "hertz") { $units = "Hz" };
    if ($units eq "farads") { $units = "F" };
    if ($units eq "farads Δ") { $units = "FΔ" };
    if ($units eq "amps DC") { $units = "ADC" };
    if ($units eq "amps AC") { $units = "AAC" };
    if ($units eq "amps DC Δ") { $units = "ADCΔ" };
    if ($units eq "amps AC Δ") { $units = "AACΔ" };
    if ($units eq "percent") { $units = "%" };
    if ($units eq "degrees Celsius Δ") { $units = "°CΔ" };
    if ($units eq "degrees Celsius") { $units = "°C" };
    
    # Pretty output
    print `clear`;
    print localtime(time) . "\n\n\n";
    print "       " . $prefix . $measurement . " " . $modifier . $units . "\n\n\n";
    print $status . "";

  } else {
    print STDOUT localtime(time) . "\t" . $prefix . $measurement . $modifier . $units . " ($status )\n";
  }

}


#=====================================
# The main event happens here!
#=====================================

# Do we have a filename to open?  If not, use stdin.
if ($fname) {
  open (FHANDLE, "<", $fname) or die "FATAL: Cannot open $fname for reading: $!\n";
} else {
  *FHANDLE=*STDIN;
}

# While the file's actually open, keep going in a loop.
while (tell(FHANDLE) != -1) {

   # Read one byte from our source.  The exit here is a cop-out.
   read (FHANDLE, $influx, 1) or exit;

   # Is that byte the first byte of a packet?
   if ( ( (oct("0b" . unpack('B8', $influx)) & 240 ) >> 4 ) == 1 ) { 

     # Save that first byte, and get 13 more.
     $buffer = $influx;
     read(FHANDLE, $influx, 13) or die "FATAL: Cannot read $fname: $!i\n"; 
     $buffer .= $influx;

     # Attempt to parse the 14-byte data frame.
     if (parser $buffer) {

       # If we're successful, show output depending on user selection.  
       # Otherwise, we have crafted specialized invalid data frame messages.
       if (!$quiet) {
         if ($csv) {
           print time . " , " . 0.000 . " , \"\" , \"Invalid Frame Error\"\n";
         } else {         
           print "Invalid frame: $buffer\n";
         }
       }
     } else {

       # How does the user want it?
       if ($csv) {
         outputcsv;
       } else {
         output;
       }

     }

   } else {

     # If the byte we read isn't the first byte, read another!
     # eventually, if we're lucky, we'll hit the start of a data
     # frame that we can decode.
     next;
     
   }

   # If the user only wants a single reading, please oblige them.
   if ($single) { last; }

}

