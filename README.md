# EseraOneWire
Family of FHEM modules to support the Esera 1-wire controller and various sensors and actors.

# Installation
FHEM commands:
1. update add https://raw.githubusercontent.com/pizmus/EseraOneWire/master/controls_EseraOneWire.txt 
1. update list 
1. update check 
1. update 66_EseraOneWire.pm
1. update 66_EseraDigitalInOut.pm
1. update 66_EseraTemp.pm
1. update 66_EseraMulti.pm
1. shutdown restart

# Getting started
1. Complete the installation as described above.
1. Power your Esera 1-wire controller and connect it to LAN. Remember the IP address.
1. Not required but helpful: Connect at least one 1-wire sensor or actor to the controller.
1. Choose a name for your 1-wire controller in FHEM.
1. On FHEM command line: "define *yourDeviceName* EseraOnewire *yourIpAddress*"
1. Give FHEM a couple of seconds to initialize the controller.
1. Refresh the FHEM web UI to see devices auto-created for your 1-wire actors/sensor.
1. Your EseraOneWire devices are ready to be used: Check the readings, try the queries
  provided by the controller, switch digital outputs, ...
1. Read the Commandref of the new modules via the web UI.
1. If your 1-wire sensor/actor is not auto-created: Check the log file for corresponding
  error messages. If your device is not supported yet please provide the log file.
 
# Was war die ursprüngliche Anwendung für das neue Modul? Was waren die Anforderungen?

Die Anwendung ist SmartHome Funktionalität in einem neu ausgebauten Dachgeschoss. Folgende Dinge wollte ich 
erreichen:
* SmartHome Funktionen sollen für die Bewohner im Hintergrund stehen. Beispiel: Lampen, Steckdosen und Rollläden 
können vollständig über konventionelle Schalter gesteuert werden. Es gibt keine unerwarteten Verzögerungszeiten 
zwischen Schalterbedienung und Schaltvorgang. Wenn mein Raspi aus welchem Grund auch immer ausgelastet ist oder 
ausfällt funktioniert für die Bewohner alles trotzdem weiter wie immer.
* Der Schaltzustand der Lampen und ausgewählter Steckdosen soll zusätzlich von FHEM überwacht und gesteuert  
werden können.
* Temperaturüberwachung ist in jedem Raum erwünscht.
* Feuchtesensoren soll es im Bad und an ein oder zwei anderen Stellen geben.
* Anwesenheitssensoren sollen überall nachrüstbar sein, sind aber vorerst nur an 2 ausgewählten Stellen vorhanden. 
Sie sollen ausschließlich für eine Alarmanlagenfunktion bei Abwesenheit genutzt werden. 
Mögliche Ausnahme: Optimierte Ansteuerung der Heizung und Lüftung für das Bad.
* Mindestens eine Netzwerkdose in jedem Raum.
* In den Räumen sichtbare Komponenten sollen zum Schalterprogramm passen.

Ich habe mich entschieden, Kabel von allen Verbrauchern/Steckdosen und Schaltern/Tastern bis zu einem 
Unterverteiler zu legen. Auch die Kabel von allen Sensoren und die Netzwerkkabel enden bei dem Unterverteiler 
bzw. Patchfeld. 
Dadurch kann die Standard-Funktion der Schalter mit konventioneller Technik (Stromstoss-Relays) 
implementiert werden. Zusätzlich hat die Hausautomation einfachen Zugriff auf alle Sensoren/Aktoren. 

Weitere Anforderungen:
* Hutschienenmontage der zentralen Komponenten
* Keine Funkverbindungen. Ich habe die Möglichkeit Kabel zu ziehen.
* Netzwerkverbindung zum bereits existierenden FHEM Host im Keller
* Keine selbst gelöteten Schaltungen und keine "in der Luft hängenden Schaltungen" im Unterverteiler
* Vertrauen in Zuverlässig aller zentralen Komponenten
* Die Möglichkeit, Komponenten auch in ein paar Jahren noch nachkaufen zu können, oder sie doch wenigstens 
sinnvoll ersetzen zu können.
* Erweiterung mit weiteren Sensoren/Aktoren verschiedener Anbieter. Auch selbst gebaute Aktoren/Sensoren  
sollen möglich sein.
* Verkabelung mit zuverlässigen Verbindungen.
* Kosten müssen "akzeptabel" bleiben.

# Was waren die Gründe für die Auswahl des Esera 1-wire Controllers?

Ich habe mich im Internet nach Produkten umgesehen. Der 1-wire Bus und die Produkte von Esera haben mich aus 
folgenden Gründen überzeugt:
* Alle meine Anforderungen (siehe oben) werden erfüllt. Es gibt dort alles was ich für die gewünschte Funktion 
brauche: Anbindung von Sensoren/Aktoren via 1-wire an einen Controller, Verbindungstechnik, passende Auswahl 
von Aktoren und Sensoren. Der Controller hängt am LAN.
* Ich habe bei FHEM (z.B. auf https://wiki.fhem.de/wiki/FHEM_und_1-Wire und auf https://wiki.fhem.de/wiki/Kategorie:1-Wire) 
keine Lösung gefunden, die alle Anforderungen genauso gut erfüllt. Der CUNX hätte eine Lösung sein können, ist aber 
fast genauso teuer wie der Esera Controller und im FHEM Wiki noch nicht dokumentiert. Falls jemand eine bessere 
Lösung für alle Anforderungen hat wäre ich daran nach wie vor interessiert.
* 1-wire bietet die Möglichkeit, Aktoren/Sensoren verschiedener Hersteller anzubinden, oder auch selbst herzustellen.
* Offenes API des Controllers. Das Programmierhandbuch kann von esera.de herunterladen werden.
* Hutschienenmontage von Controller, Netzteil, Digitalein- und ausgängen, Koppelrelays und 1-wire Verteilern.
* Verbindungen mit RJ-45 oder mit Schraubklemmen oder mit Druckklemmen.
* Der Controller wird auch von industriellen Kunden eingesetzt. Davon verspreche ich mir einerseits eine gewisse 
Qualität, andererseits die Möglichkeit, den Controller oder einen Nachfolger in den nächsten Jahren nachkaufen zu 
können. Das wird die Zukunft zeigen.
* Verfügbares FHEM Modul: Dies war der größte Schwachpunkt von Esera. Ich habe mich von der Verfügbarkeit des 
Moduls und einem Youtube-Video blenden lassen. Das Modul war für mich aus verschiedenen Gründen unbenutzbar. 
Das habe ich aber erst bemerkt, als ich anfangen wollte mit der erworbenen Hardware zu arbeiten. Ich habe versucht 
im Groben zu verstehen, ob man Esera mit dem OWX Modul verheiraten könnte. Die Ansätze scheinen aber nicht zusammen 
zu passen: Der Esera Controller versteckt den 1-wire Bus praktisch vollständig vor der Software (in diesem Fall 
vor FHEM). Die Kommunikation mit der Software erfolgt über menschenlesbare proprietäre Zeichenketten. Da koennte  
fast jedes Kommunikationsprotokoll dahinterstecken. OWX dagegen implementiert dagegen das 1-wire Protokoll "low level"  
und scheint 1-wire Nachrichten bis an die logischen Module durchzureichen. Ich hoffe ich gebe das so korrekt wieder.  
Nach meinem Verstaendnis liessen sich die beiden Welten jedenfalls nicht sinnvoll miteinander verbinden. Ich 
habe mein Problem daher mit einer Neu-Implementierung gelöst. Da das Protokoll vollständig dokumentiert ist, 
und da einem der Controller die meiste Arbeit abnimmt, war die Implementierung gar nicht so aufwändig. Im Normalbetrieb 
schickt einem der Controller in regelmäßigen Abständen Werte aller gefundenen Sensoren. Die Digital- und Analogausgänge 
der gefundenen 1-wire Devices werden über einfache Befehle gesetzt. Fertig.
[Nachtrag: Der OWX Owner sieht eine Möglichkeit, den Esera Controller einzubinden, siehe Forum-Eintrag. Das ist noch zu prüfen.]
* Bislang kann ich sagen, dass der Support von Esera gut funktioniert. Obwohl ich "nur" eine Privatperson und 
ein FHEM Bastler bin, wurden meine Anfragen bislang immer zügig beantwortet.
* Kosten: Ich finde die Preise OK für das was man bekommt. Die Alternativen, die ich gefunden habe, waren nicht
günstiger, z.B. KNX oder busware CUNX+pigator, oder sie hatten andere Nachteile.

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
