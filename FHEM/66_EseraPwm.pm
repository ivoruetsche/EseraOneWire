################################################################################
#
#    66_EseraPwm.pm
#
#    Copyright (C) 2019  pizmus
#
#    This program is free software: you can redistribute it and/or modify
#    it under the terms of the GNU General Public License as published by
#    the Free Software Foundation, either version 3 of the License, or
#    (at your option) any later version.
#
#    This program is distributed in the hope that it will be useful,
#    but WITHOUT ANY WARRANTY; without even the implied warranty of
#    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#    GNU General Public License for more details.
#
#    You should have received a copy of the GNU General Public License
#    along with this program.  If not, see <https://www.gnu.org/licenses/>.
#
################################################################################
#
# This FHEM module controls an Esera PWM device connected via
# an Esera 1-wire Controller and the 66_EseraOneWire module.
#
################################################################################

package main;

use strict;
use warnings;
use SetExtensions;

sub
EseraPwm_Initialize($)
{
  my ($hash) = @_;
  $hash->{Match}         = "11225";
  $hash->{DefFn}         = "EseraPwm_Define";
  $hash->{UndefFn}       = "EseraPwm_Undef";
  $hash->{ParseFn}       = "EseraPwm_Parse";
  $hash->{SetFn}         = "EseraPwm_Set";
  $hash->{GetFn}         = "EseraPwm_Get";
  $hash->{AttrFn}        = "EseraPwm_Attr";
  $hash->{AttrList}      = "$readingFnAttributes";
}

sub
EseraPwm_Define($$)
{
  my ($hash, $def) = @_;
  my @a = split( "[ \t][ \t]*", $def);

  return "Usage: define <name> EseraPwm <physicalDevice> <1-wire-ID> <deviceType>" if(@a < 5);

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

  $modules{EseraPwm}{defptr}{$oneWireId} = $hash;

  AssignIoPort($hash, $physicalDevice);

  if (defined($hash->{IODev}->{NAME}))
  {
    Log3 $devName, 4, "EseraPwm ($devName) - I/O device is " . $hash->{IODev}->{NAME};
  }
  else
  {
    Log3 $devName, 1, "EseraPwm ($devName) - no I/O device";
  }

  if ($deviceType == 11225)
  {
    IOWrite($hash, "assign;$oneWireId;$deviceType");
  }
  else
  {
    Log3 $devName, 1, "EseraPwm ($devName) - deviceType ".$deviceType." is not supported";
  }

  return undef;
}

sub
EseraPwm_Undef($$)
{
  my ($hash, $arg) = @_;
  my $oneWireId = $hash->{ONEWIREID};

  RemoveInternalTimer($hash);
  delete( $modules{EseraPwm}{defptr}{$oneWireId} );

  return undef;
}

sub
EseraPwm_Get($@)
{
  return undef;
}

sub
EseraPwm_sendPwmCommand($$$)
{
  my ($hash, $oneWireId, $percentage) = @_;
  my $name = $hash->{NAME};

  Log3 $name, 5, "EseraPwm ($name) - EseraPwm_sendPwmCommand: $oneWireId,$percentage";

  if (!defined  $hash->{DEVICE_TYPE})
  {
    my $message = "error: device type not known";
    Log3 $name, 1, "EseraPwm ($name) - ".$message;
    return $message;
  }

  if ($hash->{DEVICE_TYPE} eq "11225")
  {
    if (($percentage < 0) || ($percentage > 100))
    {
      my $message = "error: invalid value";
      Log3 $name, 1, "EseraPwm ($name) - ".$message;
      return $message;
    }

    # look up the ESERA ID
    my $eseraId = $hash->{ESERAID};
    if (!defined $eseraId)
    {
      my $message = "error: ESERA ID not known";
      Log3 $name, 1, "EseraPwm ($name) - ".$message;
      return $message;
    }

    # set output
    my $command = "set,owd,outpwm,".$eseraId.",".$percentage;
    IOWrite($hash, "set;$eseraId;$command");
  }
  else
  {
    my $message = "error: device type not supported: ".$hash->{DEVICE_TYPE};
    Log3 $name, 1, "EseraPwm ($name) - ".$message;
    return $message;
  }

  return undef;
}

sub
EseraPwm_Set($$)
{
  my ( $hash, @parameters ) = @_;
  my $name = $parameters[0];
  my $what = lc($parameters[1]);

  my $oneWireId = $hash->{ONEWIREID};
  my $iodev = $hash->{IODev}->{NAME};

  my $commands = ("percentage");

  if ($what eq "percentage")
  {
    if ((scalar(@parameters) != 3))
    {
      my $message = "error: unexpected number of parameters (".scalar(@parameters).")";
      Log3 $name, 1, "EseraPwm ($name) - ".$message;
      return $message;
    }
    my $percentage = $parameters[2];
    EseraPwm_sendPwmCommand($hash, $oneWireId, $percentage);
  }
  elsif ($what eq "?")
  {
    my $message = "unknown argument $what, choose one of $commands";
    return $message;
  }
  else
  {
    shift @parameters;
    shift @parameters;
    return SetExtensions($hash, $commands, $name, $what, @parameters);
  }
  return undef;
}

sub
EseraPwm_ParseForOneDevice($$$$$$)
{
  my ($rhash, $deviceType, $oneWireId, $eseraId, $readingId, $value) = @_;
  my $rname = $rhash->{NAME};
  Log3 $rname, 4, "EseraPwm ($rname) - ParseForOneDevice: ".$rname;

  # capture the Esera ID for later use
  $rhash->{ESERAID} = $eseraId;

  # consistency check of device type
  if (!($rhash->{DEVICE_TYPE} eq uc($deviceType)))
  {
    Log3 $rname, 1, "EseraPwm ($rname) - unexpected device type ".$deviceType;

    # program the the device type into the controller via the physical module
    IOWrite($rhash, "assign;$oneWireId;".$rhash->{DEVICE_TYPE});
  }

  if ($readingId eq "ERROR")
  {
    Log3 $rname, 1, "EseraPwm ($rname) - error message from physical device: ".$value;
  }
  elsif ($readingId eq "STATISTIC")
  {
    Log3 $rname, 1, "EseraPwm ($rname) - statistics message not supported yet: ".$value;
  }
  else
  {
    my $nameOfReading;
    if ($deviceType eq "11225")
    {
      # There is only one reading
      $nameOfReading = "percentage";
      readingsSingleUpdate($rhash, $nameOfReading, $value, 1);
    }
  }
  return $rname;
}

sub
EseraPwm_Parse($$)
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
  my @list;
  foreach my $d (keys %defs)
  {
    my $h = $defs{$d};
    my $type = $h->{TYPE};

    if($type eq "EseraPwm")
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
	  my $rname = EseraPwm_ParseForOneDevice($rhash, $deviceType, $oneWireId, $eseraId, $readingId, $value);
          push(@list, $rname);
        }
      }
    }
  }

  if ((scalar @list) > 0)
  {
    return @list;
  }
  elsif ($deviceType eq "11225")
  {
    return "UNDEFINED EseraPwm_".$ioName."_".$oneWireId." EseraPwm ".$ioName." ".$oneWireId." ".$deviceType;
  }

  return undef;
}

sub
EseraPwm_Attr(@)
{
}

1;

=pod
=item summary    Represents an Esera 1-wire PWM device.
=item summary_DE Repraesentiert ein Esera 1-wire PWM Device.
=begin html
<a name="EseraPwm"></a>
<h3>EseraPwm</h3>
<ul>
  This module implements an Esera 1-wire PWM device. It uses 66_EseraOneWire as I/O device.<br>
  NOTE: The module is not yet tested with real hardware.<br>
  <br>

  <a name="EseraPwm_Define"></a>
  <b>Define</b>
  <ul>
    <code>define &lt;name&gt; EseraPwm &lt;ioDevice&gt; &lt;oneWireId&gt; &lt;deviceType&gt;</code><br>
    &lt;oneWireId&gt; specifies the 1-wire ID of the PWM device.<br>
    Use the "get devices" query of EseraOneWire to get a list of 1-wire IDs, <br>
    or simply rely on autocreate.<br>
    Supported values for deviceType:
    <ul>
      <li>11225</li>
    </ul>
  </ul>
  <br>

  <a name="EseraPwm_Set"></a>
  <b>Set</b>
  <ul>
    <li>
      <b><code>set &lt;name&gt; percentage &lt;value (0..100)&gt;</code><br></b>
    </li>
  </ul>
  <br>
  <a name="EseraPwm_Get"></a>
  <b>Get</b>
  <ul>
    <li>no get functionality</li>
  </ul>
  <br>
  <a name="EseraPwm_Attr"></a>
  <b>Attributes</b>
  <ul>
    <li>no attributes</li>
  </ul>
  <br>

  <a name="EseraPwm_Readings"></a>
  <b>Readings</b>
  <ul>
    <li>percentage</li>
  </ul>
  <br>
</ul>
=end html
=cut
