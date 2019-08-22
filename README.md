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
1. Read the Commandref of the Esera modules via the FHEM web UI.
1. If your 1-wire sensor/actor is not auto-created: Check the log file for corresponding
  error messages. If your device is not supported yet please provide the log file.
  
# FHEM statistics
Optional: To give feedback regarding the use of EseraOneWire please call "fheminfo send" in FHEM and set global attribute "sendStatistics". See the FHEM commandref for details about "fheminfo" and the statistics generated from it. You are also welcome to give feedback and ask questions regarding EseraOneWire in the FHEM forum.

# Getting started with EseraStation 200
The following notes might be helpful to you when starting with a new EseraStation. However, there is no guarantee that these notes are complete or correct. The information will get out of date over time and I do not intend to update it on a regular basis.
1. power up EseraStation 200, connect it to LAN, get the IP address from your router
1. ssh -X *yourStationIpAddress* -l pi -> initial password is "esera"
1. change the password
1. sudo apt-get update
1. sudo apt-get dist-upgrade -> got a question about IP Symcon, answer it and continue
1. sudo apt-get -f install && sudo apt-get -y install perl-base libdevice-serialport-perl libwww-perl libio-socket-ssl-perl libcgi-pm-perl libjson-perl sqlite3 libdbd-sqlite3-perl libtext-diff-perl libtimedate-perl libmail-imapclient-perl libgd-graph-perl libtext-csv-perl libxml-simple-perl liblist-moreutils-perl ttf-liberation libimage-librsvg-perl libgd-text-perl libsocket6-perl libio-socket-inet6-perl libmime-base64-perl libimage-info-perl libusb-1.0-0-dev libnet-server-perl
1. sudo wget http://fhem.de/fhem-5.9.deb && sudo dpkg -i fhem-5.9.deb
1. sudo passwd fhem (optional)
1. sudo vi /etc/passwd -> change the shell "/bin/false" to "/bin/bash" (optional)
1. sudo reboot
1. connect to fhem webUI http://*yourStationIpAddress*:8083/fhem
1. install the EseraOneWire FHEM module as described aboved
1. shutdown restart
1. define EseraStation200 EseraOneWire /dev/serial0
1. Wait for the module/controller to complete initialization (observe reading "state" going from "initializing" to "initialized" to "ready") and autocreate devices. The initial communication between the RaspberryPi and the 1-wire controller is somehow corrupted. It takes some time until the first correct messages are received by the EseraOneWire FHEM module. Therefore, the module needs a 2nd attempt when initializing the controller. This takes some time, and there is a corresponding message in the FHEM log file.
1. The lower of 2 bits of the digital inputs and outputs SYS1 and SYS2 represent the DIN and DOUT ports of EseraStation.
