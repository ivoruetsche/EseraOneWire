#!/usr/bin/perl

use File::Basename;
use POSIX qw(strftime);
use strict;

my @filenames = ( "66_EseraOneWire.pm",
                  "66_EseraAnalogInOut.pm",
                  "66_EseraDigitalInOut.pm",
                  "66_EseraMulti.pm",
		  "66_EseraTemp.pm",
		  "66_EseraCount.pm",
		  "66_EseraIButton.pm");

my $prefix = "FHEM";
my $filename = "";
foreach $filename (@filenames)
{
  my @statOutput = stat($prefix."/".$filename);
  
  if (scalar @statOutput != 13)
  {
    printf("error: ".$prefix."/".$filename." does not exist!\n");
    next;
  }

  my $mtime = $statOutput[9];
  my $date = POSIX::strftime("%Y-%m-%d", localtime($mtime));
  my $time = POSIX::strftime("%H:%M:%S", localtime($mtime));
  my $filetime = $date."_".$time;

  my $filesize = $statOutput[7];

  printf("UPD ".$filetime." ".$filesize." ".$prefix."/".$filename."\n");
}
