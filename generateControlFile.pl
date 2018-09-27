#!/usr/bin/perl

use File::Basename;
use POSIX qw(strftime);
use strict;

my @filenames = ( "66_EseraOneWire.pm",
                  "66_EseraDigitalInOut.pm",
                  "66_EseraMulti.pm",
		  "66_EseraTemp.pm");

my $filename = "";
foreach $filename (@filenames)
{
  my @statOutput = stat($filename);

  my $mtime = $statOutput[9];
  my $date = POSIX::strftime("%Y-%d-%m", localtime($mtime));
  my $time = POSIX::strftime("%H:%M:%S", localtime($mtime));
  my $filetime = $date."_".$time;

  my $filesize = $statOutput[7];

  printf("UPD ".$filetime." ".$filesize." FHEM/".$filename."\n");
}
