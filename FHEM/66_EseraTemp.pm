################################################################################
# 66_EseraTemp.pm 
################################################################################
#
# Copyright pizmus 2018
#
# This FHEM module supports a temperature sensor connected via
# an Esera "1-wire Controller 1" with LAN interface and the 66_EseraOneWire 
# module.
#
# supported device types: DS1820
#
################################################################################
#
# Known issues and potential enhancements:
#
# - support ESERA product numbers of ESERA temperature sensors
#
################################################################################


package main;

use strict;
use warnings;
use SetExtensions;

sub 
EseraTemp_Initialize($) 
{
  my ($hash) = @_;
  $hash->{Match}         = "DS1820";
  $hash->{DefFn}         = "EseraTemp_Define";
  $hash->{UndefFn}       = "EseraTemp_Undef";
  $hash->{ParseFn}       = "EseraTemp_Parse";
  $hash->{SetFn}         = "EseraTemp_Set";
  $hash->{GetFn}         = "EseraTemp_Get";
  $hash->{AttrFn}        = "EseraTemp_Attr";
  $hash->{AttrList}      = "$readingFnAttributes";
}

sub 
EseraTemp_Define($$)
{
  my ($hash, $def) = @_;
  my @a = split( "[ \t][ \t]*", $def);
  
  return "Usage: define <name> EseraTemp <physicalDevice> <1-wire-ID> <deviceType>" if(@a < 5);

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
 
  $modules{EseraTemp}{defptr}{$oneWireId} = $hash;
  
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
EseraTemp_Undef($$) 
{
  my ($hash, $arg) = @_;  
  my $oneWireId = $hash->{ONEWIREID};
  
  RemoveInternalTimer($hash);
  delete( $modules{EseraTemp}{defptr}{$oneWireId} );
  
  return undef;
}

sub 
EseraTemp_Get($@) 
{
  return undef;
}

sub 
EseraTemp_Set($$) 
{
  my ( $hash, @parameters ) = @_;
  my $name = $parameters[0];
  my $what = lc($parameters[1]);
 
  my $oneWireId = $hash->{ONEWIREID};
  my $iodev = $hash->{IODev}->{NAME};
  
  my $commands = ("statusRequest");
  
  if ($what eq "statusRequest")
  {
    IOWrite($hash, "status;$oneWireId");
  }
  elsif ($what eq "?")
  {
    # TODO use the :noArg info 
    my $message = "unknown argument $what, choose one of $commands";
    return $message;
  }
  else
  {
    my $message = "unknown argument $what, choose one of $commands";
    Log3 $name, 1, "EseraTemp ($name) - ".$message;
    return $message;
  }
  return undef;
}

sub 
EseraTemp_Parse($$) 
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
        
    if($type eq "EseraTemp") 
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
    Log3 $rname, 4, "EseraTemp ($rname) - parse - device found: ".$rname;

    # capture the Esera ID for later use
    $rhash->{ESERAID} = $eseraId;
    
    # consistency check of device type
    if (!($rhash->{DEVICE_TYPE} eq uc($deviceType)))
    {
      Log3 $rname, 1, "EseraTemp ($rname) - unexpected device type ".$deviceType;
    }
    
    if ($readingId eq "ERROR")
    {
      Log3 $rname, 1, "EseraTemp ($rname) - error message from physical device: ".$value;
    }
    elsif ($readingId eq "STATISTIC")
    {
      Log3 $rname, 1, "EseraTemp ($rname) - statistics message not supported yet: ".$value;
    }
    else
    {
      my $nameOfReading = $oneWireId."_temperature";
      readingsSingleUpdate($rhash, $nameOfReading, $value / 100.0, 1);
    }
           
    my @list;
    push(@list, $rname);
    return @list;
  }
  elsif ($deviceType eq "DS1820")
  {
    return "UNDEFINED EseraTemp_".$ioName."_".$oneWireId." EseraTemp ".$ioName." ".$oneWireId." ".$deviceType;
  }
  
  return undef;
}

sub 
EseraTemp_Attr(@) 
{
}

1;

=pod
=item summary    Represents a 1-wire temperature sensor.
=item summary_DE Repraesentiert einen 1-wire Temperatursensor.
=begin html

<a name="EseraTemp"></a>
<h3>EseraTemp</h3>

<ul>
  This module implements a 1-wire temperature sensor. It uses 66_EseraOneWire<br>
  as I/O device.<br>
  <br>
  
  <a name="EseraTemp_Define"></a>
  <b>Define</b>
  <ul>
    <code>define &lt;name&gt; EseraTemp &lt;ioDevice&gt; &lt;oneWireId&gt; &lt;deviceType&gt;</code> <br>
    &lt;oneWireId&gt; specifies the 1-wire ID of the sensor. Use the "get devices"<br>
    query of EseraOneWire to get a list of 1-wire IDs, or simply rely on autocreate.<br>
    Supported values for deviceType: DS1820<br>
  </ul>
  <br>
  
  <a name="EseraTemp_Set"></a>
  <b>Set</b>
  <ul>
    <li>no set functionality</li>
  </ul>
  <br>

  <a name="EseraTemp_Get"></a>
  <b>Get</b>
  <ul>
    <li>no get functionality</li>
  </ul>
  <br>

  <a name="EseraTemp_Attr"></a>
  <b>Attributes</b>
  <ul>
    <li>no attributes</li>
  </ul>
  <br>
      
  <a name="EseraTemp_Readings"></a>
  <b>Readings</b>
  <ul>
    <li>&lt;oneWireId&gt;_temperature &ndash; temperature in degrees Celsius</li>
  </ul>
  <br>

</ul>

=end html
=cut
