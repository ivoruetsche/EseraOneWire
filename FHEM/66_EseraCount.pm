################################################################################
# 66_EseraCount.pm 
################################################################################
#
# Copyright pizmus 2019
#
# This FHEM module supports DS2423 counters.   
#
#  --- THIS IS EXPERIMENTAL ---
#
################################################################################
#
# Known issues and potential enhancements:
#
# - ...
#
################################################################################

package main;

use strict;
use warnings;
use SetExtensions;

sub 
EseraCount_Initialize($) 
{
  my ($hash) = @_;
  $hash->{Match}         = "DS2423";
  $hash->{DefFn}         = "EseraCount_Define";
  $hash->{UndefFn}       = "EseraCount_Undef";
  $hash->{ParseFn}       = "EseraCount_Parse";
  $hash->{SetFn}         = "EseraCount_Set";
  $hash->{GetFn}         = "EseraCount_Get";
  $hash->{AttrFn}        = "EseraCount_Attr";
  $hash->{AttrList}      = "ticksPerUnit1 ticksPerUnit2 $readingFnAttributes";
}

sub 
EseraCount_Define($$)
{
  my ($hash, $def) = @_;
  my @a = split( "[ \t][ \t]*", $def);
  
  return "Usage: define <name> EseraCount <physicalDevice> <1-wire-ID> <deviceType>" if(@a < 5);

  my $devName = $a[0];
  my $type = $a[1];
  my $physicalDevice = $a[2];
  my $oneWireId = $a[3];
  my $deviceType = uc($a[4]);

  $hash->{STATE} = 'Initialized';
  $hash->{NAME} = $devName;
  $hash->{TYPE} = $type;
  $hash->{ONEWIREID} = $oneWireId;
  $hash->{ESERAID} = undef;  # We will get this from the first reading.
  $hash->{DEVICE_TYPE} = $deviceType;
  $hash->{DATE_OF_LAST_SAMPLE} = undef;
  $hash->{START_VALUE_OF_DAY_1} = 0;
  $hash->{START_VALUE_OF_DAY_2} = 0;
  $hash->{LAST_VALUE_1} = 0;
  $hash->{LAST_VALUE_2} = 0;

  $modules{EseraCount}{defptr}{$oneWireId} = $hash;
  
  AssignIoPort($hash, $physicalDevice);
  
  if (defined($hash->{IODev}->{NAME})) 
  {
    Log3 $devName, 4, "$devName: I/O device is " . $hash->{IODev}->{NAME};
  } 
  else 
  {
    Log3 $devName, 1, "$devName: no I/O device";
  }

  return undef;
}

sub 
EseraCount_Undef($$) 
{
  my ($hash, $arg) = @_;  
  my $oneWireId = $hash->{ONEWIREID};
  
  RemoveInternalTimer($hash);
  delete( $modules{EseraCount}{defptr}{$oneWireId} );
  
  return undef;
}

sub 
EseraCount_Get($@) 
{
  return undef;
}

sub 
EseraCount_Set($$) 
{
  return undef;
}

sub
EseraCount_IsNewDay($)
{
  my ($hash) = @_;  
  
  my $timestamp = FmtDateTime(gettimeofday());
  # example: 2016-02-16 19:34:24
  
  if ($timestamp =~ m/^([0-9\-]+)\s/)
  {
    my $dateString = $1;
    
    if (defined $hash->{DATE_OF_LAST_SAMPLE})
    {
      if (!($hash->{DATE_OF_LAST_SAMPLE} eq $dateString))
      {
        $hash->{DATE_OF_LAST_SAMPLE} = $dateString;
        return 1;
      }
    }
    else
    {
      $hash->{DATE_OF_LAST_SAMPLE} = $dateString;
    }
  }
  
  return undef;
}

sub 
EseraCount_Parse($$) 
{
  my ($ioHash, $msg) = @_;
  my $ioName = $ioHash->{NAME};
  my $buffer = $msg;

  # expected message format: $deviceType."_".$oneWireId."_".$eseraId."_".$readingId."_".$value
  my @fields = split(/_/, $buffer);
  if (scalar(@fields) != 5)
  {
    return undef;
  }
  my $deviceType = uc($fields[0]);
  my $oneWireId = $fields[1];
  my $eseraId = $fields[2];
  my $readingId = $fields[3];
  my $value = $fields[4];

  # search for logical device
  my $rhash = undef;  
  foreach my $d (keys %defs) {
    my $h = $defs{$d};
    my $type = $h->{TYPE};
        
    if($type eq "EseraCount") 
    {
      if (defined($h->{IODev}->{NAME})) 
      {
        my $ioDev = $h->{IODev}->{NAME};
        my $def = $h->{DEF};

        # $def has the whole definition, extract the oneWireId (which is expected as 2nd parameter)
        my @parts = split(/ /, $def);
	my $oneWireIdFromDef = $parts[1];

        if (($ioDev eq $ioName) && ($oneWireIdFromDef eq $oneWireId)) 
	{
          $rhash = $h;
          last;
        }
      }
    }
  }
 
  if($rhash) {
    my $rname = $rhash->{NAME};
    Log3 $rname, 4, "EseraCount ($rname) - parse - device found: ".$rname;

    # capture the Esera ID for later use
    $rhash->{ESERAID} = $eseraId;
    
    # consistency check of device type
    if (!($rhash->{DEVICE_TYPE} eq uc($deviceType)))
    {
      Log3 $rname, 1, "EseraCount ($rname) - unexpected device type ".$deviceType;
    }
    
    if ($readingId eq "ERROR")
    {
      Log3 $rname, 1, "EseraCount ($rname) - error message from physical device: ".$value;
    }
    elsif ($readingId eq "STATISTIC")
    {
      Log3 $rname, 1, "EseraCount ($rname) - statistics message not supported yet: ".$value;
    }
    else
    {
      if ($deviceType eq "DS2423")
      {
        if (EseraCount_IsNewDay($rhash))
        {
          $rhash->{START_VALUE_OF_DAY_1} = $rhash->{LAST_VALUE_1};
          $rhash->{START_VALUE_OF_DAY_2} = $rhash->{LAST_VALUE_2};
        }
        
        if ($readingId == 1) 
        {
          my $ticksPerUnit = AttrVal($rname, "ticksPerUnit1", 1.0);
          readingsSingleUpdate($rhash, "count1", ($value / $ticksPerUnit), 1);
          readingsSingleUpdate($rhash, "count1Today", ($value - $rhash->{START_VALUE_OF_DAY_1}) / $ticksPerUnit, 1);
          $rhash->{LAST_VALUE_1} = $value;
        }
        elsif ($readingId == 2) 
        {
          my $ticksPerUnit = AttrVal($rname, "ticksPerUnit2", 1.0);
          readingsSingleUpdate($rhash, "count2", ($value / $ticksPerUnit), 1);
          readingsSingleUpdate($rhash, "count2Today", ($value - $rhash->{START_VALUE_OF_DAY_2}) / $ticksPerUnit, 1);
          $rhash->{LAST_VALUE_2} = $value;
        }
      }
    }
           
    my @list;
    push(@list, $rname);
    return @list;
  }
  elsif ($deviceType eq "DS2423")
  {
    return "UNDEFINED EseraCount_".$ioName."_".$oneWireId." EseraCount ".$ioName." ".$oneWireId." ".$deviceType;
  }
  
  return undef;
}

sub 
EseraCount_Attr($$$$) 
{
  my ($cmd, $name, $attrName, $attrValue) = @_;
  # $cmd  -  "del" or "set"
  # $name - device name
  # $attrName/$attrValue
  
  if ($cmd eq "set") {
    if (($attrName eq "ticksPerUnit1") || ($attrName eq "ticksPerUnit2"))
    {
      if ($attrValue <= 0)
      {
        my $message = "illegal value for ticksPerUnit";
        Log3 $name, 3, "EseraCount ($name) - ".$message;
        return $message; 
      }
    }
  }
  
  return undef;
}

1;

=pod
=item summary    Represents a DS2423 1-wire dual counter.
=item summary_DE Repraesentiert einen DS2423 1-wire 2-fach Zaehler.
=begin html

<a name="EseraCount"></a>
<h3>EseraCount</h3>

<ul>
  This module supports DS2423 1-wire dual counters.<br>
  It uses 66_EseraOneWire as I/O device.<br>
  <br>
  
  <a name="EseraCount_Define"></a>
  <b>Define</b>
  <ul>
    <code>define &lt;name&gt; EseraCount &lt;ioDevice&gt; &lt;oneWireId&gt; &lt;deviceType&gt;</code><br>
    &lt;oneWireId&gt; specifies the 1-wire ID of the sensor. Use the "get devices" <br>
    query of EseraOneWire to get a list of 1-wire IDs, or simply rely on autocreate. <br>
    The only supported &lt;deviceType&gt is DS2423.
  </ul>
  
  <a name="EseraCount_Set"></a>
  <b>Set</b>
  <ul>
    <li>no get functionality</li>
  </ul>
  <br>

  <a name="EseraCount_Get"></a>
  <b>Get</b>
  <ul>
    <li>no get functionality</li>
  </ul>
  <br>

  <a name="EseraCount_Attr"></a>
  <b>Attributes</b>
  <ul>
    <li><code>ticksPerUnit1</code></li>
    <li><code>ticksPerUnit2</code></li>
  </ul>
  <br>
      
  <a name="EseraCount_Readings"></a>
  <b>Readings</b>
  <ul>
    <ul>
      <li>count1</li>
      <li>count2</li>
      <li>count1Today</li>
      <li>count2Today</li>
    </ul>
  </ul>
  <br>

</ul>

=end html
=cut
