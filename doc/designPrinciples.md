# Principles of EseraOneWire regarding the use of the Esera controller

* Do not rely on previous state of the controller. Make all controller settings that are needed for operation 
with this module in this module itself.
* Do not change the state of the controller persistently, e.g. do not use "save" commands to freeze settings 
or the list of connected 1-wire devices.
* Do not rely on ESERA IDs. ESERA IDs are basically indices into the list of known devices maintained by 
the controller. Indices can change.
* For the same reason, hide ESERA IDs from the user. Present 1-wire IDs to the user. Map them to ESERA IDs
internally only, and only when needed.
* Expect one response for each request sent to the controller. Exceptions:
    * Readings and events are sent asynchronously by the controller.
    * Setting digital outputs does not immediately cause a response packet. Responses cannot be 
    distinguished from periodic readings.
    * KAL messages are sent asynchronously be the controller.
    * Send only one request at a time. Wait for response before sending the next request.
* The controller has internal timer. The time is ignored: Do not try to set the time, and do not use the
time reported by the controller.
* The only reason to use the "Config Tool" from Esera is to update the controller firmware.

# Principles regarding communication between physical and logical modules

* Readings are passed to logical modules without device specific interpretation. The format of the messages 
passed to logical modules is fixed. The message contains the 1-wire ID (as unique ID of the device), the device 
type (e.g. DS1820, so that the client module can do a consistency check), and the Esera ID (it can change 
with the next restart of the controller, but it is required to send messages from the client without 
interpretation in this module).
* If the logical module is defined to support an ESERA product number, but the controller has not been 
configured the product number, it will report a "low level" device type to the logical module. This 
results in a deviceType mismatch when interpreting a reading in the logical module. In that case the  
logical module will try to program the controller to use the ESERA product number.
* A reading can be relevant to multiple devices, e.g. when the 8 digital inputs of a DS2408 are used with 
different instances of logical modules, with non-overlapping bit ranges. There is no automatic check  
anywhere to detect overlapping bit ranges.
