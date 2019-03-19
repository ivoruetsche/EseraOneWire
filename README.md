# EseraOneWire
Family of FHEM modules to support the Esera 1-wire controller and various sensors and actors.

# Installation
FHEM commands:
1. update add https://raw.githubusercontent.com/pizmus/EseraOneWire/master/controls_EseraOneWire.txt 
1. update list 
1. update check 
1. update 66_EseraOneWire.pm
1. update 66_EseraAnalogInOut.pm
1. update 66_EseraDigitalInOut.pm
1. update 66_EseraIButton.pm
1. update 66_EseraMulti.pm
1. update 66_EseraTemp.pm
1. shutdown restart

# Getting started
1. Complete the installation as described above.
1. Recommended: Connect at least one 1-wire sensor or actor to the controller.
1. Power your Esera 1-wire controller and connect it to LAN. Remember the IP address.
1. On FHEM command line: "define *yourDeviceName* EseraOneWire *yourIpAddress*"
1. Give FHEM a couple of seconds to initialize the controller.
1. Refresh the FHEM web UI to see devices auto-created for your 1-wire actors/sensors.
1. Your EseraOneWire devices are ready to be used: Check the readings, try the queries
  provided by the controller, switch digital outputs, ...
1. Read the Commandref of the new modules via the web UI.
1. If your 1-wire sensor/actor is not auto-created: Check the log file for corresponding
  error messages. If your device is not supported yet please provide the log file.
  
# FHEM statistics
Optional: To give feedback regarding the use of EseraOneWire please call "fheminfo send" in FHEM and set global attribute "sendStatistics". See the FHEM commandref for details about "fheminfo" and the statistics generated from it. You are also welcome to give feedback and ask questions regarding EseraOneWire in the FHEM forum.
