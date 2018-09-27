################################################################################
# 66_EseraOneWire.pm 
################################################################################
#
# Copyright pizmus 2018
#
# This FHEM module controls the Esera "1-wire Controller 1" with LAN interface.
# It works together with client modules 66_EseraTemp, 66_EseraDigitalInOut and
# 66_EseraMulti.
#
# The module is tested with:
# - Esera "1-Wire Controller 1" (product number 11319, FW: 11903 SERIAL: 1131918V1.2-587)
# - Esera "Digital Out 8-Channel" (product number 11229) with DS2408
# - Esera "8-Channel Digital Input DC" (product number 11216) with DS2408
# - Esera Multisensor (product number 11134) with DS2438 and DS1820
# - DS1820
# - DS2408
# - DS2438
# - Raspberry Pi as FHEM host
# 
################################################################################
#
# Principles regarding use of the ESERA controller:
# - Do not rely on previous state of the controller. Make all controller 
#   settings that are needed for operation with this module in this module itself.
# - Do not change the state of the controller persistently, e.g. do not use
#   "save" commands to freeze settings or the list of connected 1-wire devices.
# - Do not rely on ESERA IDs. ESERA IDs are basically indices into the list of 
#   known devices maintained by the controller. Indices can change.
# - For the same reason, hide ESERA IDs from the user. Present 1-wire IDs to
#   the user. Map them to ESERA IDs internally only, and only when needed.
# - Expect one response for each request sent to the controller. Exceptions:
#   - Readings and events are sent asynchronously by the controller.
#   - Setting digital outputs does not immediately cause a response packet. Responses
#     cannot be distinguished from periodic readings.
#   - KAL messages are sent asynchronously be the controller.
#   Send only one request at a time. Wait for response before sending the next request.
# - The controller has a watch. The time is ignored: Do not try to set the time, and
#   do not use the time reported by the controller.
# - The only reason to use the "Config Tool" from Esera is to update the controller
#   firmware.
#
# Principles regarding communication with client modules:
# - Readings are passed to clients without device specific interpretation. The format
#   of the messages passed to clients is fixed. The message contains the 1-wire ID
#   (as unique ID of the device), the device type (e.g. DS1820, so that the client
#   module can do a consistency check), and the Esera ID (it can change with the next
#   restart of the controller, but it is required to send messages from the client
#   without interpretation in this module).
# - If the client is defined to support an ESERA product number, but the controller
#   has not been configured the the product number, it will report a "low level" 
#   device type to this module. This results in a deviceType mismatch when interpreting
#   a reading in the client. In that case the client will try to program the controller
#   to use the ESERA product number, not the low level device type.
# - A reading can be relevant to multiple devices, e.g. when the 8 digital inputs
#   of a DS2408 are used with different clients, with non-overlapping bit ranges.
#   There is no automatic check anywhere to detect overlapping bit ranges.
# - Commands to client devices are described in the EseraOneWire_Write function.
#
# Data stored in device hash:
# - Various information read from the controller e.g. during EseraOneWire_refreshControllerInfo().
#   In most cases the hash key is named like the controller command.
# - Hashes storing information per 1-wire device reported by the controller:
#   - ESERA ID of the device (index into a list of devices kept by the controller)
#   - device type
#   - status
#   The key used with these hashes is always a 1-wire ID.
#
################################################################################
#
# Known issues and potential enhancements:
#
# - Add regression test for a defined test setup, so that source code changes
#   can be validated easily.
# - Let the user control certain settings, like DATATIME, SEACHTIME and wait time
#   used after posted writes, e.g. as parameters to the define command.
# - Implement recovery when controller disappears (power-on) and comes back.
#   This is potentially broken, at least not tested thoroughly.
# - Provide a way to reset (close followed by open) the DevIo connection to the
#   controller.
# - Implement an incremental update of the device list: Avoid removing the list
#   when re-building it. Instead, update individual entries as needed, but keep
#   a valid list at all times. This will avoid unnecessary error messages in the
#   log file.
# - Generate warning if Firmware is too old.
# - Test with multiple controllers.
# - Implement support for all devices listed in the Programmierhandbuch.
# - Read error counts as part of status query.
# - Provide an interface so that clients can query the device status.
# - Implement a kind of watchdog based on the KAL message received from the controller.
#   Reset the connection and/or the controller if the message is not received on time.
# - Performance optimizations, e.g.
#   - make use of command FIFO inside the controller, depth 10
#
################################################################################

package main;

use HttpUtils;
use strict;
use warnings;
use vars qw {%attr %defs};
use DevIo;

sub
EseraOneWire_Initialize($)
{
  my ($hash) = @_;
  $hash->{ReadFn} = "EseraOneWire_Read";
  $hash->{WriteFn} = "EseraOneWire_Write";
  $hash->{ReadyFn} = "EseraOneWire_Ready";
  $hash->{DefFn} = "EseraOneWire_Define";
  $hash->{UndefFn} = "EseraOneWire_Undef";
  $hash->{DeleteFn} = "EseraOneWire_Delete";
  $hash->{GetFn} = "EseraOneWire_Get";
  $hash->{SetFn} = "EseraOneWire_Set";
  $hash->{AttrFn} = "EseraOneWire_Attr";
  $hash->{AttrList} = $readingFnAttributes;
  
  $hash->{Clients} = ":EseraDigitalInOut:EseraTemp:EseraMulti:";
  $hash->{MatchList} = { "1:EseraDigitalInOut" => ".*", 
                         "2:EseraTemp" => ".*",
                         "2:EseraMulti" => ".*" };
}

sub 
EseraOneWire_Define($$)
{
  my ($hash, $def) = @_;
  my @a = split("[ \t]+", $def);

  my $name = $a[0];
  
  # $a[1] is always equals the module name "ESERA"
  
  # first argument is the hostname or IP address of the device (e.g. "192.168.1.120")
  my $dev = $a[2]; 

  return "no device given" unless($dev);
  
  # add the default port
  $dev .= ':5000' if(not $dev =~ m/:\d+$/);
  
  Log3 $name, 3, "EseraOneWire ($name) - define: $dev";
    
  $hash->{DeviceName} = $dev;
  
  # close connection if maybe open (on definition modify)
  DevIo_CloseDev($hash) if(DevIo_IsOpen($hash));  
  
  # open connection with custom init and error callback function (non-blocking connection establishment)
  DevIo_OpenDev($hash, 0, "EseraOneWire_Init", "EseraOneWire_Callback"); 
 
  return undef;
}

sub 
EseraOneWire_Undef($$)
{
  my ($hash, $name) = @_;
 
  # close the connection 
  DevIo_CloseDev($hash);
    
  RemoveInternalTimer($hash);

  return undef;
}

sub 
EseraOneWire_Delete($$)
{
  my ($hash, $name) = @_;
  #delete all dev-spec temp-files
  unlink($attr{global}{modpath}. "/FHEM/FhemUtils/$name.tmp");
  return undef;
}

sub 
EseraOneWire_Ready($)
{
  my ($hash) = @_;
  
  # try to reopen the connection in case the connection is lost
  return DevIo_OpenDev($hash, 1, "EseraOneWire_Init", "EseraOneWire_Callback"); 
}

sub
EseraOneWire_Attr(@)
{
  my ($cmd, $name, $attrName, $attrValue) = @_;    
  # $cmd  -  "del" or "set"
  # $name - device name
  # $attrName/$attrValue
  return undef;
}

sub 
EseraOneWire_Init($)
{
  my ($hash) = @_;
  EseraOneWire_baseSettings($hash);
  return undef; 
}

sub 
EseraOneWire_Callback($$)
{
  my ($hash, $error) = @_;
  my $name = $hash->{NAME};

  if ($error)
  {
    Log3 $name, 1, "EseraOneWire ($name) - error while connecting: >>".$error."<<";
  }
    
  return undef; 
}

################################################################################
# controller info, settings and status
################################################################################

sub 
EseraOneWire_baseSettings($)
{
  my ($hash) = @_;  
  my $name = $hash->{NAME};

  $hash->{".CONTROLLER_INITIALIZED"} = 0;
  $hash->{".READ_PENDING"} = 0;

  # clear task list before reset  
  undef $hash->{TASK_LIST} unless (!defined $hash->{TASK_LIST});

  # reset controller and wait for 1_RDY. Ignore "garbage" before 1_RDY.
  EseraOneWire_taskListAddSync($hash, "set,sys,rst,1", "1_RDY", \&EseraOneWire_query_response_handler);

  # Sending this request as a dummy, because the first access seems to get an 1_ERR always, followed
  # by the correct response. Wait time of 3s between "set,sys,rst,1" and "set,sys,dataprint,1" does not help.
  # TODO ask Esera
  EseraOneWire_taskListAddSync($hash, "set,sys,dataprint,1", "1_DATAPRINT", \&EseraOneWire_query_response_handler);

  # commands below here are expected to receive a "good" response
  
  # ensure the controller number 1 is used always
  EseraOneWire_taskListAddSimple($hash, "set,sys,contno,1", "1_CONTNO", \&EseraOneWire_query_response_handler);
  # ensure the controller is active and will send events
  EseraOneWire_taskListAddSimple($hash, "set,sys,run,1", "1_RUN", \&EseraOneWire_query_response_handler);
  # events must contain the 1-wire ID, not the ESERA ID
  EseraOneWire_taskListAddSimple($hash, "set,owb,owdid,1", "1_OWDID", \&EseraOneWire_query_response_handler);
  EseraOneWire_taskListAddSimple($hash, "set,sys,dataprint,1", "1_DATAPRINT", \&EseraOneWire_DATAPRINT_handler);
  EseraOneWire_taskListAddSimple($hash, "set,sys,datatime,10", "1_DATATIME", \&EseraOneWire_query_response_handler);
  EseraOneWire_taskListAddSimple($hash, "set,sys,echo,1", "1_ECHO", \&EseraOneWire_query_response_handler);
  EseraOneWire_taskListAddSimple($hash, "set,sys,kalsend,1", "1_KALSEND", \&EseraOneWire_query_response_handler);
  EseraOneWire_taskListAddSimple($hash, "set,sys,kalsendtime,180", "1_KALSENDTIME", \&EseraOneWire_query_response_handler);
  EseraOneWire_taskListAddSimple($hash, "set,sys,kalrec,0", "1_KALREC", \&EseraOneWire_query_response_handler);
  EseraOneWire_taskListAddSimple($hash, "set,owb,owdidformat,1", "1_OWDIDFORMAT", \&EseraOneWire_query_response_handler);
  EseraOneWire_taskListAddSimple($hash, "set,owb,search,2", "1_SEARCH", \&EseraOneWire_query_response_handler);
  EseraOneWire_taskListAddSimple($hash, "set,owb,searchtime,30", "1_SEARCHTIME", \&EseraOneWire_query_response_handler);
  
  # TODO "data" setting does not work. Ask Esera.
  # 2018.09.23 15:17:51 1: EseraOneWire (owc) - COMM sending: set,owb,data,2
  # 2018.09.23 15:17:51 1: EseraOneWire (owc) - COMM Read: 1_INF|17:59:07
  # 2018.09.23 15:17:51 1: EseraOneWire (owc) - COMM Read: 1_ERR|3
  #EseraOneWire_taskListAddSimple($hash, "set,owb,data,2", "1_DATA", \&EseraOneWire_query_response_handler);
  
  EseraOneWire_taskListAddSimple($hash, "set,owb,polltime,5", "1_POLLTIME", \&EseraOneWire_query_response_handler);
  EseraOneWire_taskListAddSimple($hash, "set,owd,ds2408inv,1", "1_DS2408INV", \&EseraOneWire_query_response_handler);#

  # wait some time to give the controller time to detect the devices
  EseraOneWire_taskListAddPostedWrite($hash, "", 4);

  # read settings, ... from the controller and store the info in the hash
  EseraOneWire_refreshControllerInfo($hash);
  
  # wait some more time before readings can be forwarded to clients
  EseraOneWire_taskListAddPostedWrite($hash, "", 2);

  # This must be the last one.
  EseraOneWire_taskListAddSimple($hash, "get,sys,run", "1_RUN", \&EseraOneWire_init_complete_handler);
}

sub
EseraOneWire_refreshControllerInfo($)
{
  my ($hash) = @_;
  my $name = $hash->{NAME};

  # do nothing if a refresh is already in process
  return undef if ((defined $hash->{".READ_PENDING"}) && ($hash->{".READ_PENDING"} == 1));
  
  # clear old information
  undef $hash->{ESERA_IDS} unless (!defined $hash->{ESERA_IDS});
  undef $hash->{DEVICE_TYPES} unless (!defined $hash->{DEVICE_TYPES});
  
  # queue queries to retrieve updated information

  # The LST0 query gets multiple responses, depending on the number of devices known by the controller.
  # Read the list with a posted write. The wait time has to chosen so that all LST responses are received
  # before the next command is sent. LST responses are handled generically in the EseraOneWire_Read().
  EseraOneWire_taskListAddPostedWrite($hash, "get,owb,list0", 2);

  EseraOneWire_taskListAddSimple($hash, "get,sys,fw", "1_FW", \&EseraOneWire_query_response_handler);
  EseraOneWire_taskListAddSimple($hash, "get,sys,hw", "1_HW", \&EseraOneWire_query_response_handler);
  EseraOneWire_taskListAddSimple($hash, "get,sys,serial", "1_SERIAL", \&EseraOneWire_query_response_handler);
  EseraOneWire_taskListAddSimple($hash, "get,sys,id", "1_ID", \&EseraOneWire_query_response_handler);
  EseraOneWire_taskListAddSimple($hash, "get,sys,dom", "1_DOM", \&EseraOneWire_query_response_handler);
  EseraOneWire_taskListAddSimple($hash, "get,sys,run", "1_RUN", \&EseraOneWire_query_response_handler);
  EseraOneWire_taskListAddSimple($hash, "get,sys,contno", "1_CONTNO", \&EseraOneWire_query_response_handler);
  EseraOneWire_taskListAddSimple($hash, "get,sys,kalrec", "1_KALREC", \&EseraOneWire_query_response_handler);
  EseraOneWire_taskListAddSimple($hash, "get,sys,kalrectime", "1_KALRECTIME", \&EseraOneWire_query_response_handler);
  
  # TODO issue in controller software: string mismatch between command and response, ask Esera
  # 2018.09.23 15:28:48 1: EseraOneWire (owc) - COMM sending: get,sys,dataprint
  # 2018.09.23 15:28:48 1: EseraOneWire (owc) - COMM Read: 1_DATASEND|1
  # 2018.09.23 15:28:48 1: EseraOneWire (owc) - COMM expected response received: 1_DATASEND|1
  EseraOneWire_taskListAddSimple($hash, "get,sys,dataprint", "1_DATASEND", \&EseraOneWire_DATAPRINT_handler);
  
  EseraOneWire_taskListAddSimple($hash, "get,sys,datatime", "1_DATATIME", \&EseraOneWire_query_response_handler);
  EseraOneWire_taskListAddSimple($hash, "get,sys,kalsend", "1_KALSEND", \&EseraOneWire_query_response_handler);
  EseraOneWire_taskListAddSimple($hash, "get,sys,kalsendtime", "1_KALSENDTIME", \&EseraOneWire_query_response_handler);
  EseraOneWire_taskListAddSimple($hash, "get,owb,owdid", "1_OWDID", \&EseraOneWire_query_response_handler);
  
  # TODO The "data" query does not work, ask Esera.
  # 2018.09.23 15:32:42 1: EseraOneWire (owc) - COMM sending: get,owb,data
  # 2018.09.23 15:32:42 1: EseraOneWire (owc) - COMM Read: 1_INF|18:13:59
  # 2018.09.23 15:32:42 1: EseraOneWire (owc) - COMM Read: 1_ERR|3
  # 2018.09.23 15:32:42 1: EseraOneWire (owc) - COMM error response received, expected: 1_DATA
  # 2018.09.23 15:32:42 1: EseraOneWire (owc) - error response, command: get,owb,data , response: 1_ERR|3 , ignoring the response
  #EseraOneWire_taskListAddSimple($hash, "get,owb,data", "1_DATA", \&EseraOneWire_query_response_handler);

  EseraOneWire_taskListAddSimple($hash, "get,owb,owdidformat", "1_OWDIDFORMAT", \&EseraOneWire_query_response_handler);
  
  # TODO issue in controller software: string mismatch between command and response, ask Esera.
  # 2018.09.23 15:32:43 1: EseraOneWire (owc) - COMM sending: get,owb,search
  # 2018.09.23 15:32:43 1: EseraOneWire (owc) - COMM Read: 1_SEARCHMODE|2
  # 2018.09.23 15:32:43 1: EseraOneWire (owc) - COMM expected response received: 1_SEARCHMODE|2
  EseraOneWire_taskListAddSimple($hash, "get,owb,search", "1_SEARCHMODE", \&EseraOneWire_SEARCH_handler);
  
  EseraOneWire_taskListAddSimple($hash, "get,owb,searchtime", "1_SEARCHTIME", \&EseraOneWire_query_response_handler);
  EseraOneWire_taskListAddSimple($hash, "get,owb,polltime", "1_POLLTIME", \&EseraOneWire_query_response_handler);
  EseraOneWire_taskListAddSimple($hash, "get,owd,ds2408inv", "1_DS2408INV", \&EseraOneWire_query_response_handler);
  
  # TODO This does not work. The command is documented like this but it causes an 
  # ERR response. What does the last parameter mean anyway? Ask Esera.
  # 2018.09.23 15:36:04 1: EseraOneWire (owc) - COMM sending: get,sys,owdid,0
  # 2018.09.23 15:36:05 1: EseraOneWire (owc) - COMM Read: 1_INF|18:17:21
  # 2018.09.23 15:36:05 1: EseraOneWire (owc) - COMM Read: 1_ERR|3
  # 2018.09.23 15:36:05 1: EseraOneWire (owc) - COMM error response received, expected: 1_OWDID
  # 2018.09.23 15:36:05 1: EseraOneWire (owc) - error response, command: get,sys,owdid,0 , response: 1_ERR|3 , ignoring the response
  #EseraOneWire_taskListAddSimple($hash, "get,sys,owdid,0", "1_OWDID", \&EseraOneWire_query_response_handler); 
  
  # TODO This does not work as documented. It returns an ERR message. Ask Esera.
  # 2018.09.23 15:36:05 1: EseraOneWire (owc) - COMM sending: get,sys,echo
  # 2018.09.23 15:36:05 1: EseraOneWire (owc) - COMM Read: 1_INF|18:17:21
  # 2018.09.23 15:36:05 1: EseraOneWire (owc) - COMM Read: 1_ERR|3
  # 2018.09.23 15:36:05 1: EseraOneWire (owc) - COMM error response received, expected: 1_ECHO
  #2018.09.23 15:36:05 1: EseraOneWire (owc) - error response, command: get,sys,echo , response: 1_ERR|3 , ignoring the response
  #EseraOneWire_taskListAddSimple($hash, "get,sys,echo", "1_ECHO", \&EseraOneWire_query_response_handler);
      
  # This must be the last one.
  EseraOneWire_taskListAddSimple($hash, "get,sys,run", "1_RUN", \&EseraOneWire_read_complete_handler);
  $hash->{".READ_PENDING"} = 1;

  return undef;
}

sub 
EseraOneWire_refreshStatus($)
{
  my ($hash) = @_;
  my $name = $hash->{NAME};

  # get access to list of active devices
  my $eseraIdsRef = $hash->{ESERA_IDS};
  if (!defined $eseraIdsRef)
  {
    Log3 $name, 1, "EseraOneWire ($name) - no devices known";
    return undef;
  }
  
  # clear old information
  undef $hash->{DEVICE_STATUS} unless (!defined $hash->{DEVICE_STATUS});
  # TODO Fix error count query.
  #undef $hash->{DEVICE_ERRORS} unless (!defined $hash->{DEVICE_ERRORS});
      
  # iterate over known devices  
  my %eseraIds = %$eseraIdsRef;
  my @keys = keys %eseraIds;
  foreach (@keys)
  {
    my $eseraId = $eseraIds{$_};

    # query the status         
    EseraOneWire_taskListAdd($hash, "get,owd,status,".$eseraId, 
    "1_OWD_", \&EseraOneWire_DEVICE_STATUS_handler, "ERR", \&EseraOneWire_error_handler, \&EseraOneWire_unexpected_handler, 0);

    # TODO The "errowd" query does not work yet. "get,owd,errowd,1" returns "1_2:04:171_ERR|3". Report to ESERA.
    # query number of device communication errors
#    EseraOneWire_taskListAddSimple($hash, "get,owd,errowd,".$eseraId, "1_ERROWD", \&EseraOneWire_ERROWD_handler);
  } 
}

sub
EseraOneWire_eseraIdToOneWireId($$)
{
  my ($hash, $eseraId) = @_;
  my $name = $hash->{NAME};
  
  my $eseraIdsRef = $hash->{ESERA_IDS};
  if (defined $eseraIdsRef)
  {
    my %eseraIds = %$eseraIdsRef;
    my @keys = keys %eseraIds;
    foreach (@keys)
    {
      if ($eseraIds{$_} eq $eseraId)
      {
        return $_;
      }
    } 
  }
  return undef;
}

sub
EseraOneWire_oneWireIdToEseraId($$)
{
  my ($hash, $oneWireId) = @_;
  my $name = $hash->{NAME};  
  my $eseraIdsRef = $hash->{ESERA_IDS};
  if (defined $eseraIdsRef)
  {
    my %eseraIds = %$eseraIdsRef;
    my $eseraId = $eseraIds{$oneWireId};
    if (defined $eseraId)
    {
      return $eseraId;
    }
  }
  return undef;
}

################################################################################
# Set command
################################################################################

sub 
EseraOneWire_Set($$)
{
  my ($hash, @parameters) = @_;
  my $name = $parameters[0];
  my $what = lc($parameters[1]);
  
  if ($what eq "raw") 
  {
    if (scalar(@parameters) != 3)
    {
      my $message = "error: unexpected number of parameters (".scalar(@parameters).") to raw";
      Log3 $name, 1, "EseraOneWire ($name) - ".$message;
      return $message;
    }
    my $rawCommand = lc($parameters[2]);
    my $message = "command to ESERA controller: ".$rawCommand;
    Log3 $name, 4, "EseraOneWire ($name) - ".$message;
    
    $hash->{RAW_COMMAND} = $rawCommand;    
    $hash->{RAW_RESPONSE} = ".";
    
    EseraOneWire_taskListAdd($hash, $rawCommand, 
      "1_", \&EseraOneWire_raw_command_handler, "ZZZ", \&EseraOneWire_error_handler, 
      \&EseraOneWire_unexpected_handler, 0.5);

    return undef;
  } 
  elsif ($what eq "refresh")
  {
    EseraOneWire_refreshStatus($hash);
    EseraOneWire_refreshControllerInfo($hash);
  }
  elsif ($what eq "reset")
  {
    if (scalar(@parameters) != 3)
    {
      my $message = "error: unexpected number of parameters (".scalar(@parameters).") to reset";
      Log3 $name, 1, "EseraOneWire ($name) - ".$message;
      return $message;
    }
    my $resetSpecifier = lc($parameters[2]);
    my $message;
    if ($resetSpecifier eq "tasks")
    {
      undef $hash->{TASK_LIST} unless (!defined $hash->{TASK_LIST});
    }
    elsif ($resetSpecifier eq "controller")
    {
      EseraOneWire_baseSettings($hash);
      $message = "reset controller";
      Log3 $name, 4, "EseraOneWire ($name) - ".$message;
    }
    else 
    {
      $message = "error: unknown reset specifier ".$resetSpecifier;
      Log3 $name, 1, "EseraOneWire ($name) - ".$message;
    }
    return undef;
  }
  elsif ($what eq "?")
  {
    my $message = "unknown argument $what, choose one of refresh:noArg reset:controller,tasks raw";
    return $message;
  }
  else
  {
    my $message = "unknown argument $what, choose one of reset refresh raw";
    Log3 $name, 1, "EseraOneWire ($name) - ".$message;
    return $message;
  }
  return undef;
}

################################################################################
# Get command
################################################################################

sub 
EseraOneWire_getDevices($)
{
  my ($hash) = @_;
  my $name = $hash->{NAME};

  my $eseraIdsRef = $hash->{ESERA_IDS};
  my $deviceTypesRef = $hash->{DEVICE_TYPES};
  my $list = "";
  if (defined $eseraIdsRef && defined $deviceTypesRef)
  {
    my %eseraIds = %$eseraIdsRef;
    my %deviceTypes = %$deviceTypesRef;
    my @keys = keys %eseraIds;
    foreach (@keys)
    {
      $list .= $_.",".$eseraIds{$_}.",".$deviceTypes{$_}.";\n";
    } 
  }
  return $list;
}

sub 
EseraOneWire_getInfo($)
{
  my ($hash) = @_;
  my $name = $hash->{NAME};
  my $list = "";

  my $fwVersion = $hash->{".FW"};
  my $hwVersion = $hash->{".HW"};
  my $serialNumber = $hash->{".SERIAL"};
  my $productNumber = $hash->{".ID"};
  my $dom = $hash->{".DOM"};

  $fwVersion = "UNKNOWN" if (!defined $fwVersion);
  $hwVersion = "UNKNOWN" if (!defined $hwVersion);
  $serialNumber = "UNKNOWN" if (!defined $serialNumber);
  $productNumber = "UNKNOWN" if (!defined $productNumber);
  $dom = "UNKNOWN" if (!defined $dom);

  $list .= "FW version: ".$fwVersion."\n";    
  $list .= "HW version: ".$hwVersion."\n";
  $list .= "serial number: ".$serialNumber."\n";
  $list .= "ESERA product number: ".$productNumber."\n";
  $list .= "date of manufacturing: ".$dom."\n";
  return $list;
}

sub 
EseraOneWire_getSettings($)
{
  my ($hash) = @_;
  my $name = $hash->{NAME};
  my $list = "";

  my $run = $hash->{".RUN"};
  my $contno = $hash->{".CONTNO"};
  my $kalrec = $hash->{".KALREC"};
  my $kalrectime = $hash->{".KALRECTIME"};
  my $kalsend = $hash->{".KALSEND"};
  my $kalsendtime = $hash->{".KALSENDTIME"};
  my $datasend = $hash->{".DATASEND"};
  my $datatime = $hash->{".DATATIME"};
  my $useOwdid = $hash->{".OWDID"};
  my $owdidFormat = $hash->{".OWDIDFORMAT"};
  my $searchMode = $hash->{".SEARCH_MODE"};
  my $searchTime = $hash->{".SEARCHTIME"};
  my $polltime = $hash->{".POLLTIME"};
  my $ds2408inv = $hash->{".DS2408INV"};
  
  $run = "UNKNOWN" if (!defined $run);
  $contno = "UNKNOWN" if (!defined $contno);
  $kalrec = "UNKNOWN" if (!defined $kalrec);
  $kalrectime = "UNKNOWN" if (!defined $kalrectime);
  $kalsend = "UNKNOWN" if (!defined $kalsend);
  $kalsendtime = "UNKNOWN" if (!defined $kalsendtime);
  $datasend = "UNKNOWN" if (!defined $datasend);
  $datatime = "UNKNOWN" if (!defined $datatime);
  $useOwdid = "UNKNOWN" if (!defined $useOwdid);
  $owdidFormat = "UNKNOWN" if (!defined $owdidFormat);
  $searchMode = "UNKNOWN" if (!defined $searchMode);
  $searchTime = "UNKNOWN" if (!defined $searchTime);
  $polltime = "UNKNOWN" if (!defined $polltime);
  $ds2408inv = "UNKNOWN" if (!defined $ds2408inv);

  $list .= "RUN: ".$run." (1=controller sending to FHEM)\n";
  $list .= "CONTNO: ".$contno." (ESERA controller number)\n";
  $list .= "KALREC: ".$kalrec." (1=keep-alive signal expected by controller)\n";
  $list .= "KALRECTIME: ".$kalrectime." (time period in seconds used for expected keep-alive messages)\n";
  $list .= "KALSEND: ".$kalsend." (1=controller sending keep-alive messages)\n";
  $list .= "KALSENDTIME: ".$kalsendtime." (time period in seconds used for sending keep-alive messages)\n";
  $list .= "DATASEND: ".$datasend." (aka DATAPRINT, 0=list responses are returned in a single line)\n";
  $list .= "DATATIME: ".$datatime." (time period used for data delivery to FHEM)\n";
  $list .= "OWDID: ".$useOwdid." (1=return readings with 1-wire ID instead of Esera ID)\n";
  $list .= "OWDIDFORMAT: ".$owdidFormat." (selects format of 1-wire ID)\n";
  $list .= "SEARCH_MODE: ".$searchMode." (2=cyclic search for new devices)\n";
  $list .= "SEARCHTIME: ".$searchTime." (time period in seconds used to search for new devices)\n";
  $list .= "POLLTIME: ".$polltime." (time period in seconds used with periodic reads from devices)\n";
  $list .= "DS2408INV: ".$ds2408inv." (1=invert readings from DS2408 devices)\n"; 
  
  return $list;
}

sub 
EseraOneWire_getStatus($)
{
  my ($hash) = @_;
  my $name = $hash->{NAME};
  
  # get access to stored device information
  my $eseraIdsRef = $hash->{ESERA_IDS};
  my $deviceTypesRef = $hash->{DEVICE_TYPES};
  if (!defined $eseraIdsRef || !defined $deviceTypesRef)
  {
    EseraOneWire_refreshControllerInfo($hash);
    my $message = "No device information found. Refreshing list. Please try again.";
    Log3 $name, 3, "EseraOneWire ($name) - ".$message;
    return $message;
  }
  
  # get access to stored device status
  my $deviceStatusRef = $hash->{DEVICE_STATUS};
  if (!defined $deviceStatusRef)
  {
    EseraOneWire_refreshStatus($hash);
    my $message = "No status information found. Triggering refresh. Please try again.";
    Log3 $name, 3, "EseraOneWire ($name) - ".$message;
    return $message;
  }
  
  # iterate over detected devices  
  my $list = "";
  my %eseraIds = %$eseraIdsRef;
  my %deviceTypes = %$deviceTypesRef;
  my %deviceStatus = %$deviceStatusRef;
  my @keys = keys %eseraIds;
  foreach (@keys)
  {
    $list .= $_.",".$eseraIds{$_}.",".$deviceTypes{$_}.",";
    
    my $status = $deviceStatus{$_};
    if (!defined $status)
    {
      $list .= "unknown";
    }
    else 
    {
      $list .= $status;
    }
    
    $list .= ";\n";
  } 

  # trigger next read of status info from controller
  EseraOneWire_refreshStatus($hash);
  
  return $list;
}

sub 
EseraOneWire_Get($$)
{
  my ($hash, @parameters) = @_;
  my $name = $hash->{NAME};
  my $what = lc($parameters[1]);
  
  if ($what eq "devices") 
  {
    return EseraOneWire_getDevices($hash);
  } 
  elsif ($what eq "info") 
  {
    return EseraOneWire_getInfo($hash);
  }
  elsif ($what eq "settings") 
  {
    return EseraOneWire_getSettings($hash);
  }
  elsif ($what eq "status") 
  {
    return EseraOneWire_getStatus($hash);
  }
  elsif ($what eq "?") 
  {
    my $message = "unknown argument $what, choose one of devices:noArg info:noArg settings:noArg status:noArg";
    return $message;
  }

  my $message = "unknown argument $what, choose one of devices:noArg info:noArg settings:noArg status:noArg";
  Log3 $name, 3, "EseraOneWire ($name) - ".$message;
  return $message;
}

################################################################################
# Read command - process data coming from the device
################################################################################

sub 
EseraOneWire_Read($)
{
  my ($hash) = @_;
  my $name = $hash->{NAME};
 
  my $data = DevIo_SimpleRead($hash);
  return if (!defined($data)); # connection lost

  my $buffer = $hash->{PARTIAL};
  
  $data =~ s/\r//g;
  
  # concat received data to $buffer
  $buffer .= $data;
  
  while ($buffer =~ m/\n/)
  {
    my $msg;
    
    # extract the complete message ($msg), everything else is assigned to $buffer
    ($msg, $buffer) = split("\n", $buffer, 2);
    
    # remove trailing whitespaces
    chomp $msg;
        
    Log3 $name, 4, "EseraOneWire ($name) - COMM Read: $msg"; 

    my $ascii = $msg;
    
    if ((length $ascii) == 0)
    {
      Log3 $name, 4, "EseraOneWire ($name) - COMM - error: empty response detected";
      next;
    }
    
    my @fields = split(/\|/, $ascii);
    my $type = $fields[0];
    
    if ($type =~ m/1_EVT/) 
    {
      Log3 $name, 5, "EseraOneWire ($name) - EVT received";
    }
    elsif ($type =~ m/1_CSE/) 
    {
      Log3 $name, 5, "EseraOneWire ($name) - CSE received";
    }
    elsif ($type =~ m/1_CSI/) 
    {
      Log3 $name, 5, "EseraOneWire ($name) - CSI received";
    }
    elsif ($type =~ m/1_INF/) 
    {
      Log3 $name, 5, "EseraOneWire ($name) - COMM - INF received";
    }
    elsif ($type =~ m/1_KAL$/)
    {
      Log3 $name, 5, "EseraOneWire ($name) - COMM - 1_KAL message ignored";
    }   
    elsif ($type eq "1_LST0") 
    {
      Log3 $name, 4, "EseraOneWire ($name) - COMM - 1_LST0 received";
    }
    elsif ($type eq "LST") 
    {
      EseraOneWire_LIST0_handler($hash, $ascii);
    }    
    elsif ($type =~ m/1_OWD(\d+)_(\d+)/)
    {
      if ($hash->{".CONTROLLER_INITIALIZED"})
      {
        Log3 $name, 4, "EseraOneWire ($name) - readings data from controller has incorrect format (1_OWD*_* instead of using the 1-wire ID)";
      }
    }
    elsif ($ascii =~ m/^1_([0-9A-F]+)_(\d+)/)
    {
      if ($hash->{".CONTROLLER_INITIALIZED"})
      {
        EseraOneWire_parseReadingsInSingleLine($hash, $ascii);
      }
      else
      {
        Log3 $name, 5, "EseraOneWire ($name) - readings ignored because controller is not initialized (1)";
      }
    }
    elsif ($ascii =~ m/^1_([0-9A-F]+)\|/)
    {
      if ($hash->{".CONTROLLER_INITIALIZED"})
      {
        EseraOneWire_parseReadingsInSingleLine($hash, $ascii);
      }
      else
      {
        Log3 $name, 5, "EseraOneWire ($name) - readings ignored because controller is not initialized (2)";
      }
    }    
    else
    {
      # everything else is considered a response to latest command
      EseraOneWire_taskListHandleResponse($hash, $ascii);
    }
  }
  
  $hash->{PARTIAL} = $buffer;
}

sub 
EseraOneWire_processListEntry($$)
{
  my ($hash, $fieldsRef) = @_;
  my $name = $hash->{NAME};
  my @fields = @$fieldsRef;
  if (scalar(@fields) != 4)
  {
    Log3 $name, 1, "EseraOneWire ($name) - error: unexpected number of response fields for list entry";
  }

  # extract data from response
  my $longEseraOwd = $fields[1];
  my $eseraOwd;
  if ($longEseraOwd =~ m/1_OWD(\d+)$/)
  {
    $eseraOwd = $1;
  }
  else
  {
    $eseraOwd = "_".$longEseraOwd."_";
  }
  
  my $oneWireId = $fields[2];
  my $oneWireDeviceType = $fields[3];
  Log3 $name, 4, "EseraOneWire ($name) - new list entry: Esera OWD ".$eseraOwd." 1-wire ID ".$oneWireId." device type ".$oneWireDeviceType;

  # store ESERA ID in hash
  if (defined $hash->{ESERA_IDS})
  {
    # list is not empty; get it and add new entry
    my $eseraIdsRef = $hash->{ESERA_IDS};
    my %eseraIds = %$eseraIdsRef;
    $eseraIds{$oneWireId} = $eseraOwd;
    $hash->{ESERA_IDS} = \%eseraIds;
  }
  else
  {
    # list is empty; create new list and store in hash
    my %eseraIds;
    $eseraIds{$oneWireId} = $eseraOwd;
    $hash->{ESERA_IDS} = \%eseraIds;
  }

  # store device type in hash
  if (defined $hash->{DEVICE_TYPES})
  {
    # list is not empty; get it and add new entry
    my $deviceTypesRef = $hash->{DEVICE_TYPES};
    my %deviceTypes = %$deviceTypesRef;
    $deviceTypes{$oneWireId} = $oneWireDeviceType;
    $hash->{DEVICE_TYPES} = \%deviceTypes;
  }
  else
  {
    # list is empty; create new list and store in hash
    my %deviceTypes;
    $deviceTypes{$oneWireId} = $oneWireDeviceType;
    $hash->{DEVICE_TYPES} = \%deviceTypes;
  }
}

# TODO This is called with single LST response only, optimize!
sub 
EseraOneWire_LIST0_handler($$)
{
  my ($hash, $response) = @_;
  my $name = $hash->{NAME};
  
  # example of "list0" response: "1_LST0|13:47:48;LST|1_OWD1|660000001A590029|DS2408;LST|1_OWD2|06000019828A9B29|DS2408;"
  my @listElements = split(/;/, $response);
  
  foreach (@listElements)
  {
    my $listElement = $_;
   
    my @fields = split(/\|/, $listElement);
    my $numberOfFields = scalar(@fields);
    if ($numberOfFields > 0)
    {
      my $type = $fields[0];
      if ($type eq "1_LST0") 
      {
        Log3 $name, 4, "EseraOneWire ($name) - 1_LST0 ignored";
      }
      elsif ($type eq "LST")
      {
        EseraOneWire_processListEntry($hash, \@fields);
      }
      else
      {
        Log3 $name, 1, "EseraOneWire ($name) - unexpected content in LST response: ".$listElement;
      }
    }
  }
}

################################################################################
# Write command - process requests from client modules
################################################################################

sub 
EseraOneWire_Write($$) 
{
  my ($hash, $msg) = @_;
  my $name = $hash->{NAME};
  
  Log3 $name, 4, "EseraOneWire ($name) - received command from client: ".$msg;
  
  my @fields = split(/;/, $msg);
  if ($fields[0] eq "set")
  {
    # set;<oneWireId>;<rawMessageToSend>
    if (scalar(@fields) != 3)
    {
      Log3 $name, 1, "EseraOneWire ($name) - syntax error in command from client: ".$msg;
      return undef;
    }    
    EseraOneWire_taskListAddPostedWrite($hash, $fields[2], 0.1);
  }
  elsif ($fields[0] eq "assign")
  {
    # assign;<oneWireId>;<productNumber> -> send command to controller, used to apply an ESERA product number
    #   This uses a specific call response handler which sends an error message to the client if something goes wrong.
    if (scalar(@fields) != 3)
    {
      Log3 $name, 1, "EseraOneWire ($name) - syntax error in command from client: ".$msg;
      return undef;
    }    
    
    my $oneWireId = $fields[1];    
    my $eseraId = EseraOneWire_oneWireIdToEseraId($hash, $oneWireId);
    if (!defined $eseraId)
    {
      Log3 $name, 1, "EseraOneWire ($name) - error looking up eseraId for assign request";
      return undef;
    }
    
    my $productNumber = $fields[2];    
    my $command = "set,owd,art,".$eseraId.",".$productNumber;
    
    Log3 $name, 1, "EseraOneWire ($name) - assign: $oneWireId $productNumber $command";
    
    EseraOneWire_taskListAdd($hash, $command, "1_ART", \&EseraOneWire_clientArtHandler, 
      "1_ERR", \&EseraOneWire_clientArtErrorHandler, \&EseraOneWire_unexpected_handler, undef);

    # clear the hash of known devices so that the modified article/product number is used
    EseraOneWire_refreshControllerInfo($hash);
  }
  elsif ($fields[0] eq "status")
  {
    # status;<oneWireId> -> retrieve status for given device from controller and return it via Dispatch
    #   $deviceType.";".$owId.";".$readingId.";".$value (and readingId==STATISTIC)
    #   This requires a response handler that calls Dispatch after receiving and processing the response from the
    #   controller.
    if (scalar(@fields) != 4)
    {
      Log3 $name, 1, "EseraOneWire ($name) - syntax error in command from client: ".$msg;
      return undef;
    }    
    Log3 $name, 4, "EseraOneWire ($name) - status command from client not supported yet";
  }
  else
  {
    Log3 $name, 1, "EseraOneWire ($name) - syntax error in command from client: ".$msg;
    return undef;
  }  
}

################################################################################
# Readings
################################################################################

# TODO rename to _forwardReadingToClient
sub 
EseraOneWire_parseReadings($$$$$)
{
  my ($hash, $fieldsCount, $owId, $readingId, $value) = @_;
  my $name = $hash->{NAME};
  if ($fieldsCount != 2)
  {
    Log3 $name, 1, "EseraOneWire ($name) - error: unexpected number of fields for reading";
  }
 
  my $eseraIdsRef = $hash->{ESERA_IDS};
  my $deviceTypesRef = $hash->{DEVICE_TYPES};
  if (!defined $eseraIdsRef || !defined $deviceTypesRef)
  {
    Log3 $name, 1, "EseraOneWire ($name) - info: received data for ".$owId." but device list does not exist. Ignoring data. Triggering re-reading of list of devices from controller.";
    EseraOneWire_refreshControllerInfo($hash);
    return undef;
  }
  
  my %eseraIds = %$eseraIdsRef;
  my %deviceTypes = %$deviceTypesRef;
  if (!defined $eseraIds{$owId} || !defined $deviceTypes{$owId})
  {
    Log3 $name, 1, "EseraOneWire ($name) - info: received data for ".$owId." which is not known. Ignoring data. Triggering re-reading of list of devices from controller.";
    EseraOneWire_refreshControllerInfo($hash);
    return undef;
  }
  
  my $deviceType = $deviceTypes{$owId};
  my $eseraId = $eseraIds{$owId};
  my $message = $deviceType."_".$owId."_".$eseraId."_".$readingId."_".$value;
  Log3 $name, 4, "EseraOneWire ($name) - passing reading to clients: ".$message;
  Dispatch($hash, $message, "");
  
  return undef;
}

# TODO rename to parseReading, and let it work on a single reading only. Multiple readings in same line are not expected anymore.
sub 
EseraOneWire_parseReadingsInSingleLine($$)
{
  my ($hash, $line) = @_;
  my $name = $hash->{NAME};

  # example of single line reading: "1_1:17:211_660000001A590029_1|32;1_660000001A590029_2|00100000;1_660000001A590029_3|0;1_661_1:17:211_660000001A590029_1|32;1_660000001A590029_2|00100000;1_660000001A590029_3|0;1_660000001A590029_4|00000000;1_06000019828A9B29_1|0;1_06000019828A9B29_2|00000000;1_06000019828A9B29_3|0;1_06000019828A9B29_4|00000000;0000001A590029_4|00000000;1_06000019828A9B29_1|0;1_06000019828A9B29_2|00000000;1_06000019828A9B29_3|0;1_06000019828A9B29_4|00000000;"
  my @listElements = split(/;/, $line);
  
  foreach (@listElements)
  {
    my $listElement = $_;
    Log3 $name, 4, "EseraOneWire ($name) - listElement: ".$listElement;
   
    my @fields = split(/\|/, $listElement);
    my $numberOfFields = scalar(@fields);
    if ($numberOfFields == 2)
    {
      if ($fields[0] =~ m/1_([0-9A-F]+)_(\d+)/)  
      {
        my $owId = $1;
        my $readingId = $2;
        my $value = $fields[1];
	
        EseraOneWire_parseReadings($hash, 2, $owId, $readingId, $value);
      }
      elsif ($fields[0] =~ m/1_([0-9A-F]+)/)  
      {
        my $owId = $1;
        my $readingId = 0;
        my $value = $fields[1];
	
        EseraOneWire_parseReadings($hash, 2, $owId, $readingId, $value);
      }
      elsif ($fields[0] =~ m/1_([0-9:]+)_(\d+)/)   # TODO still needed after controller update?
      {
        my $owId = $2;
        my $readingId = 0;
        my $value = $fields[1];
	
        EseraOneWire_parseReadings($hash, 2, $owId, $readingId, $value);
      }
      else
      {
        Log3 $name, 1, "EseraOneWire ($name) - unexpected readings format (1) $fields[0]";
      }
    }
    else
    {
    Log3 $name, 1, "EseraOneWire ($name) - unexpected readings format (2)";
    }
  }
}

################################################################################
# response handlers
################################################################################

sub
EseraOneWire_query_response_handler($$)
{
  my ($hash, $response) = @_;
  my $name = $hash->{NAME};
  $response =~ s/;//g;
  my @fields = split(/\|/, $response);

  if (scalar(@fields) != 2)
  {
    Log3 $name, 1, "EseraOneWire ($name) - error: unexpected number of response fields for generic query response";
    return;
  }
  
  if ($fields[0] =~ m/1_([A-Z0-9]+)$/)
  {
    my $key = ".".$1;
    my $value = $fields[1];
    $hash->{$key} = $value;
  }
}

sub 
EseraOneWire_RST_handler($$)
{
  my ($hash, $response) = @_;
  my $name = $hash->{NAME};
  $response =~ s/;//g;
  my @fields = split(/\|/, $response);
  if (scalar(@fields) != 2)
  {
    Log3 $name, 1, "EseraOneWire ($name) - error: unexpected number of response fields for RST";
  }
  # ignore the response value
}

sub 
EseraOneWire_DATAPRINT_handler($$)
{
  my ($hash, $response) = @_;
  my $name = $hash->{NAME};
  $response =~ s/;//g;
  my @fields = split(/\|/, $response);
  if (scalar(@fields) != 2)
  {
    Log3 $name, 1, "EseraOneWire ($name) - error: unexpected number of response fields for DATASEND";
  }
  $hash->{".DATASEND"} = $fields[1];
}

sub 
EseraOneWire_SEARCH_handler($$)
{
  my ($hash, $response) = @_;
  my $name = $hash->{NAME};
  $response =~ s/;//g;
  my @fields = split(/\|/, $response);
  if (scalar(@fields) != 2)
  {
    Log3 $name, 1, "EseraOneWire ($name) - error: unexpected number of response fields for SEARCH query";
  }
  $hash->{".SEARCH_MODE"} = $fields[1];
}

sub 
EseraOneWire_error_handler($$$)
{
  my ($hash, $command, $response) = @_;
  my $name = $hash->{NAME};
  $response =~ s/;//g;
  
  Log3 $name, 1, "EseraOneWire ($name) - error response, command: ".$command." , response: ".$response." , ignoring the response";
}

sub 
EseraOneWire_unexpected_handler($$$)
{
  my ($hash, $command, $response) = @_;
  my $name = $hash->{NAME};
  $response =~ s/;//g;
  
  Log3 $name, 1, "EseraOneWire ($name) - error: unexpected response, command: ".$command.", response: ".$response.", ignoring the response";
}

sub
EseraOneWire_raw_command_handler($$$)
{
  my ($hash, $response) = @_;
  my $name = $hash->{NAME};
  Log3 $name, 3, "EseraOneWire ($name) - response to raw command: ".$response;
  $hash->{RAW_RESPONSE} = $response;
}

sub
EseraOneWire_init_complete_handler($$$)
{
  my ($hash, $command, $response) = @_;
  my $name = $hash->{NAME};
  $hash->{".CONTROLLER_INITIALIZED"} = 1;
  Log3 $name, 3, "EseraOneWire ($name) - init complete";
}

sub
EseraOneWire_read_complete_handler($$$)
{
  my ($hash, $command, $response) = @_;
  $hash->{".READ_PENDING"} = 0;
}

sub 
EseraOneWire_DEVICE_STATUS_handler($$)
{
  my ($hash, $response) = @_;
  my $name = $hash->{NAME};
  $response =~ s/;//g;
  my @fields = split(/\|/, $response);  
  if (scalar(@fields) != 2)
  {
    Log3 $name, 1, "EseraOneWire ($name) - error: unexpected number of response fields for STATUS query";
  }
  my $owdId;
  my $status;
  if ($fields[0] =~ m/1_OWD_(\d+)/)
  {
    my $eseraId = $1;
    my $oneWireId = EseraOneWire_eseraIdToOneWireId($hash, $eseraId);
    
    if (!defined $oneWireId)
    {
      Log3 $name, 1, "EseraOneWire ($name) - error: could not map ESERA ID to 1-wire ID: ".$eseraId;
      return;
    }
    
    $status = $fields[1];
    my $statusText;
    if (!defined $status)
    {
      $statusText = "unknown";
    }
    elsif ($status == 0)
    {
      $statusText = "ok";
    }
    else
    {
      # TODO question to Esera: What is the meaning of status values 1..3?
    
      $statusText = "error (".$status .")";
    }

    if (defined $hash->{DEVICE_STATUS})
    {
      # list is not empty; get it and add new entry
      my $deviceStatusRef = $hash->{DEVICE_STATUS};
      my %deviceStatus = %$deviceStatusRef;
      $deviceStatus{$oneWireId} = $statusText;
      $hash->{DEVICE_STATUS} = \%deviceStatus;
    }
    else
    {
      # list is empty; create new list and store in hash
      my %deviceStatus;
      $deviceStatus{$oneWireId} = $statusText;
      $hash->{DEVICE_STATUS} = \%deviceStatus;
    }
  }
  else
  {
    Log3 $name, 1, "EseraOneWire ($name) - error: could not extract OWD ID";
  }
}

sub
EseraOneWire_clientArtHandler($$)
{
  my ($hash, $response) = @_;
  my $name = $hash->{NAME};
  $response =~ s/;//g;
  my @fields = split(/\|/, $response);

  if (scalar(@fields) != 3)
  {
    Log3 $name, 1, "EseraOneWire ($name) - error: unexpected number of response fields for ART response ".$response;
    return;
  }
}

sub
EseraOneWire_clientArtErrorHandler($$)
{
  my ($hash, $response) = @_;
  my $name = $hash->{NAME};
  $response =~ s/;//g;
  my @fields = split(/\|/, $response);

  if (scalar(@fields) != 2)
  {
    Log3 $name, 1, "EseraOneWire ($name) - error: unexpected number of response fields for ART error response";
    return;
  }
}

################################################################################
# task list
################################################################################
#
# The purpose of the task list is to provide queue for requests to the controller,
# to map responses to requests and to call handlers for incoming data from the
# controller. It is used to avoid blocking accesses to the controller.
#
# different kinds of tasks:
#
# 1) normal task: Command with expected response and error handling; waitTime is ignored
#    purpose: normal get/set commands that provide one single deterministic response
#
# 2) posted write: Command is sent. It is removed from the queue after waitTime.
#    Responses coming in during waitTime are recognized, but no handler function is called.
#    A zero waitTime is not allowed.
#
# 3) wait: Start a timer. Until the timer expires just do basic generic processing but
#    since no handler function is specified, do no special handling.
#    This is a special case of posted write, with no command and no handlers specified, but with
#    a specified waitTime.
#
# 4) sync: Send a command and expect a given response. Ignore responses which are not expected.
#    waitTime is undefined. 

sub
EseraOneWire_taskListStartNext($)
{
  my ($hash) = @_;
  my $name = $hash->{NAME};

  # retrieve the task list
  my $taskListRef = $hash->{TASK_LIST};
  if (!defined $taskListRef)
  {
    Log3 $name, 4, "EseraOneWire ($name) - task list does not exist";
    return undef;
  }
  my @taskList = @$taskListRef;
  if ((scalar @taskList) < 1)
  {
    Log3 $name, 4, "EseraOneWire ($name) - task list is empty";
    return undef;
  }

  # get the next task
  my $taskRef = $taskList[0];
  my @task = @$taskRef;
  my $command = $task[0];
  my $expectedPattern = $task[1];
  my $waitTime = $task[6];
  
  # if a command is specified: send it to the controller
  if (defined $command)
  {
    Log3 $name, 4, "EseraOneWire ($name) - COMM sending: $command"; 
    DevIo_SimpleWrite($hash, $command."\r", 2);
  }
  
  # if the current command does not have an expected response: start
  # a timer to start the next command later
  if (!defined $expectedPattern)
  {
    Log3 $name, 5, "EseraOneWire ($name) - starting timer"; 
    InternalTimer(gettimeofday()+$waitTime, "EseraOneWire_popPostedWriteFromTaskList", $hash);
  }
  
  return undef;
}

sub
EseraOneWire_taskListGetCurrentCommand($)
{
  my ($hash) = @_;
  my $name = $hash->{NAME};

  # retrieve the task list
  my $taskListRef = $hash->{TASK_LIST};
  if (!defined $taskListRef)
  {
    Log3 $name, 4, "EseraOneWire ($name) - task list does not exist";
    return undef;
  }
  my @taskList = @$taskListRef;
  if ((scalar @taskList) < 1)
  {
    Log3 $name, 4, "EseraOneWire ($name) - task list is empty";
    return undef;
  }

  # get the task
  my $taskRef = $taskList[0];
  my @task = @$taskRef;
  my $command = $task[0];
    
  return $command;
}

sub
EseraOneWire_removeCurrentTaskFromList($)
{
  my ($hash) = @_;
  my $name = $hash->{NAME};
  
  # retrieve the task list
  my $taskListRef = $hash->{TASK_LIST};
  if (!defined $taskListRef)
  {
    Log3 $name, 4, "EseraOneWire ($name) - task list does not exist";
    return undef;
  }
  my @taskList = @$taskListRef;
  if ((scalar @taskList) < 1)
  {
    Log3 $name, 4, "EseraOneWire ($name) - task list is empty";
    return undef;
  }

  # remove current task from list
  my $length = scalar @taskList;
  Log3 $name, 4, "EseraOneWire ($name) - old length of task list: ".$length;
  shift @taskList;  # pop
  $length = scalar @taskList;
  Log3 $name, 4, "EseraOneWire ($name) - new length of task list: ".$length;  
  $hash->{TASK_LIST} = \@taskList;
  
  return undef;
}

# Add a new task to the list. A task is the container for a request (read or write) to the controller,
# plus information about what to do with the response. When adding a new task to an empty
# task list that task will be started.
sub 
EseraOneWire_taskListAdd($$$$$$$$)
{
  my ($hash, $command, $expectedPattern, $handler, $errorPattern, $errorHandler, $unexpectedHandler, $waitTime) = @_;
  my $name = $hash->{NAME};

  # combine task info in one array
  my @task = ($command, $expectedPattern, $handler, $errorPattern, $errorHandler, $unexpectedHandler, $waitTime);
  
  # retrieve the task list
  my $taskListRef = $hash->{TASK_LIST};
  my @taskList;
  if (defined $taskListRef)
  {
    @taskList = @$taskListRef;
  }
  
  # add task to tasklist
  push @taskList, \@task;
  $hash->{TASK_LIST} = \@taskList;

  # trigger the new task if it is the first one in the list
  my $length = scalar @taskList;
  Log3 $name, 4, "EseraOneWire ($name) - new length of task list: ".$length;
  if ($length == 1)
  {
    EseraOneWire_taskListStartNext($hash);
  }
  
  return undef;
}

# Add a new task to the list. Use this function for accesses that do not cause a
# response.
sub 
EseraOneWire_taskListAddPostedWrite($$$)
{
  my ($hash, $command, $waitTime) = @_;
  my $name = $hash->{NAME};

  EseraOneWire_taskListAdd($hash, $command, undef, undef, undef, undef, undef, $waitTime);
  
  return undef;
}

sub 
EseraOneWire_taskListAddSync($$$$)
{
  my ($hash, $command, $expectedPattern, $handler) = @_;
  my $name = $hash->{NAME};

  EseraOneWire_taskListAdd($hash, $command, $expectedPattern, $handler, undef, undef, undef, undef);
  
  return undef;
}

# Add a new task to the list. Use this function if no special handing for
# error responses and unexpected response is required..
sub 
EseraOneWire_taskListAddSimple($$$$)
{
  my ($hash, $command, $expectedPattern, $handler) = @_;
  my $name = $hash->{NAME};

  EseraOneWire_taskListAdd($hash, $command, $expectedPattern, $handler, 
    "1_ERR", \&EseraOneWire_error_handler, \&EseraOneWire_unexpected_handler, undef);
  
  return undef;
}

sub
EseraOneWire_popPostedWriteFromTaskList($)
{
  my ($hash) = @_;
  my $name = $hash->{NAME};
  
  Log3 $name, 5, "EseraOneWire ($name) - EseraOneWire_popPostedWriteFromTaskList";
 
  EseraOneWire_removeCurrentTaskFromList($hash);
  EseraOneWire_taskListStartNext($hash);
  
  return undef;
}

sub
EseraOneWire_taskListHandleResponse($$)
{
  my ($hash, $response) = @_;
  my $name = $hash->{NAME};

  # retrieve the task list
  my $taskListRef = $hash->{TASK_LIST};
  if (!defined $taskListRef)
  {
    Log3 $name, 1, "EseraOneWire ($name) - task list does not exist";
    return undef;
  }
  my @taskList = @$taskListRef;
  if ((scalar @taskList) < 1)
  {
    Log3 $name, 1, "EseraOneWire ($name) - task list is empty";
    return undef;
  }

  my $taskRef = $taskList[0];
  my @task = @$taskRef;
  my $expectedPattern = $task[1];
  my $errorPattern = $task[3];
  my $command = $task[0];

  if (!defined $expectedPattern)
  {
    # response during waitTime after posted write
    Log3 $name, 5, "EseraOneWire ($name) - receiving response while waiting after a posted write, ignoring: $response";
  }
  elsif ((defined $expectedPattern) and (!defined $errorPattern))
  {
    # sync task
    if ($response =~ m/$expectedPattern/)
    {
      # sync found, call registered function
      Log3 $name, 4, "EseraOneWire ($name) - COMM expected response for sync task received: ".$response;
      my $functionRef = $task[2];
      &$functionRef($hash, $response);
      
      EseraOneWire_removeCurrentTaskFromList($hash);
      EseraOneWire_taskListStartNext($hash);
    }
    else
    {
      # continue waiting for sync 
      Log3 $name, 4, "EseraOneWire ($name) - COMM ignoring response while waiting for sync: ".$response;
    }
  }
  else
  {
    # normal task with expected response
    if ($response =~ m/$expectedPattern/)
    {
      Log3 $name, 4, "EseraOneWire ($name) - COMM expected response received: ".$response;
      # call registered handler
      my $functionRef = $task[2];
      &$functionRef($hash, $response);
    }
    elsif ($response =~ m/$errorPattern/)
    {
      Log3 $name, 1, "EseraOneWire ($name) - error response received, expected: $expectedPattern";
      # call registered error handler
      my $functionRef = $task[4];
      &$functionRef($hash, $command, $response);
    }
    else
    {
      Log3 $name, 1, "EseraOneWire ($name) - unexpected response received, expected: $expectedPattern";
      # call registered handler for unepected responses
      my $functionRef = $task[5];
      &$functionRef($hash, $command, $response);
    }
    EseraOneWire_removeCurrentTaskFromList($hash);
    EseraOneWire_taskListStartNext($hash);
  }

  return undef;
}

################################################################################
1;
################################################################################

=pod
=item device
=item summary    Provides an interface between FHEM and Esera 1-wire controllers.
=item summary_DE Stellt eine Verbindung zwischen FHEM und den Esera 1-wire Controllern zur Verfuegung.
=begin html

<a name="EseraOneWire"></a>
<h3>EseraOneWire</h3>

<ul>
  This module provides an interface to Esera 1-wire controllers.<br>
  The module works together with 66_Esera* modules which support <br>
  various 1-wire devices. See these modulesfor more information <br>
  about supported 1-wire devices. The module supports autocreate. <br>
  <br>
  Tested with: Esera "1-Wire Controller 1" (product number 11319, firmware version 11903)<br>
  <br>
  
  <a name="EseraOneWire_Define"></a>
  <b>Define</b>
  <ul>
    <code>define &lt;name&gt; EseraOneWire &lt;ip-address&gt;</code><br>
    Example: <code>define myEseraOneWireController EseraOneWire 192.168.0.15</code><br>
  </ul>
  <br>
  
  <a name="EseraOneWire_Set"></a>
  <b>Set</b>  
  <ul>
    <li>
      <b><code>set &lt;name&gt; reset controller</code><br></b>
      Sends a reset command to the controller.<br>
    </li>
    <li>
      <b><code>set &lt;name&gt; reset tasks</code><br></b>
      The module internally queues tasks. Tasks are requests to the controller<br>
      which need to executed one after the other. For debug purposes only the<br>
      module provides a way to clear the queue.<br>
    </li>
    <li>
      <b><code>set &lt;name&gt; refresh</code><br></b>
      Triggers a read of updated information from the controller, including<br>
      settings, list of devices and controller info. In normal operation it<br>
      is not needed to call thi when the 1-wire devices are added. The module<br>
      triggers a re-read automatically if readings are received from unknown<br>
      devices.<br>
    </li>  
    <li>
      <b><code>set &lt;name&gt; raw &lt;command&gt;</code><br></b>
      Debug only: Allows the user to send an arbitrary low level command to the<br>
      controller. The command is a command as described in the Esera Controller<br>
      Programmierhandbuch, without spaces, with commas as seperators, and without<br>
      trailing new line character.<br>
      The raw command and the received response are stored as internals<br>
      RAW_COMMAND and RAW_RESPONSE.<br>
      <br>
      Examples:<br>
      <ul>
	<li><code>set myEseraOneWireController raw get,sys,datatime</code></li>
	<li><code>set myEseraOneWire raw set,sys,datatime,0</code></li>
      </ul>
    </li>
  </ul>
  <br>
  
  <a name="EseraOneWire_Get"></a>
  <b>Get</b>
  <ul>
    <li>
      <b><code>get &lt;name&gt; info</code><br></b>
      Prints various information about the controller like part number,<br>
      serial number, date of manufacturing.<br>
    </li>
    <li>
      <b><code>get &lt;name&gt; settings</code><br></b>
      Returns various controller settings for debug purposes. New information<br>
      is retrieved when <i>set refresh</i> or <i>get settings</i> is called. New data<br>
      can then be printed with the following call of <i>get settings</i>. It is <br>
      implemented like this because it is a simple way to avoid blocking reads. <br>
      For more information regarding the individual settings please refer to the <br>
      Esera Controller Programmierhandbuch which can be downloaded from<br>
      www.esera.de .<br>
    </li>
    <li>
      <b><code>get &lt;name&gt; devices</code><br></b>
      Returns the list of currently connected 1-wire devices.<br>
      The format of each list entry is<br>
      <code>&lt;oneWireId&gt,&lt;eseraId&gt,&lt;deviceType&gt;;</code><br>
    </li>      
    <li>
      <b><code>get &lt;name&gt; status</code><br></b>
      Reports currently known status of all connected 1-wire devices. <br>
      The format of each list entry is<br>
      <code>&lt;oneWireId&gt;,&lt;eseraId&gt;,&lt;deviceType&gt;,&lt;status&gt;;</code><br>
      New status information is retrieved from the known devices when<br>
      <i>get status</i> is called. New data can then be printed with<br>
      the following call of <i>get status</i>. It is implemented like<br>
      this because it is a simple way to avoid blocking reads.<br>
    </li>          
  </ul>
  <br>
  
</ul>

=end html
=cut