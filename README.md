I wrote this Perl script to forward the filtered output of my AIS receiver to AIS aggregators like MarineTraffic.
See for details and background https://www.thefloatinglab.world/en/aisdispatcher.html

## Highlights

- Platform independent and unobtrusive. It is a simple Perl script, just one file, with no other dependencies than that you must have the Perl interpreter installed. It doesn't mess up your system: If you don't like it anymore, no risky uninstall procedure needed, just delete that single file. The required Perl interpreter is by default installed on Linux and Mac computers, and many people have it unknowingly on their Windows computers as well, and otherwise it is free to download and easy to install.
- Low data usage. AISdispatcher.pl filters and downsamples your NMEA stream and only forwards the absolute minimum to paint you on the map. It has a smart data saver, it only throttles down MMSI's which are sending updates too frequently. See also <a href="#tnotes">Technical notes</a>.
- Transparency. It shows exactly what it is receiving, and it shows exactly what it is sending after filtering and downsampling.
- Privacy. Although it goes against the idea of AIS broadcasts, if you feel that you should only forward AIS data about your own ship, you can tell AISdispatcher.pl not to reveal anyone else's positions.
- Lightweight and simple. It assumes you already have the AIS transponder somehow connected to a computer, so it has no low level connection capabilities by itself and is AIS brand and type independent.
- Source ID tagging. AISdispatcher.pl is able to add a "signature" to its outgoing data, which can be used by aggregators to determine who is sending which data. 

## Input sources
AISdispatcher is written with the assumption that you are not building a dedicated system to capture AIS data and submitting it to aggregation services, but that you already have a working AIS infrastructure and simply want to extend it with an AIS forwarder. Usually, you can use one of the following methods, in order of preference:

### UDP
NMEA data can be streamed over WiFi. Usually this is done by UDP over port 10110. If you don't stream your NMEA data over WiFi, I strongly recommend you to start doing so. The benefits are that any computer logged on to your private WiFi network has access to your NMEA data, which includes your position, wind and depth data, AIS data, etc. This means that you can run OpenCPN on any laptop or even Android phones, without a physical connection to your boat devices. There are several hardware devices that can do this, I use one from [ShipModul](http://www.shipmodul.com/en/index.html).

If you have NMEA data broadcasted on your own network, use 0.0.0.0 as IP address and add the port number, which is usually 10110. The input source is thus specified as "0.0.0.0:10110", like this:
`perl aisdispatcher.pl 0.0.0.0:10110`

### OpenCPN
You probably have [OpenCPN](https://opencpn.org), and otherwise this is just another marvel of software I strongly recommend. Assuming that you have setup OpenCPN to have access to your AIS data, you can easily forward it from OpenCPN to AISdispatcher.pl. Go to the connections tab, and add an UDP output connection.

In this case, the AISdispatcher.pl input source is specified as "127.0.0.1:10110", like this:
`perl aisdispatcher.pl 127.0.0.1:10110`

### GPSD
[GPSD](https://gpsd.gitlab.io/gpsd/) is often used as an intermediate between your physical GPS/AIS hardware device and software clients on Linux, Android systems, driverless cars, aircraft, etc. Assuming that you run AISdispatcher.pl on the computer running GPSD, you use the input source "--gpsd 127.0.0.1:2947", like this:
`perl aisdispatcher.pl --gpsd 127.0.0.1:2947`
The "--gpsd" option is used to let AISdispatcher.pl know that the input is coming from GPSD. The GPSD connection is by TCP, so the --gpsd option automatically includes the --tcp option as well.

## Using AISdispatcher.pl
After downloading, on Linux systems (skip this if you use Windows), set the executable flag with:
`chmod a+x aisdispatcher.pl`

First you should verify that AISdispatcher.pl successfully connects to the input source and that it is receiving data. Run AISdispatcher in the terminal with the input source applicable to your system, but no outputs, like this:
`perl aisdispatcher.pl 0.0.0.0:10110`
If everything is working as intended, you should see a steady stream of NMEA data on the screen. End the program with Ctrl-C once you get bored.

Now it is time to test run without actually sending out any data, by using the --test option. You can specify the output to the aggregation services to make the test more realistic. You should have received a specific IP address and PORT number to forward the data to. Add these to the command line, like this:
`perl aisdispatcher.pl --test 0.0.0.0:10110 1.2.3.4:555`
You can enter multiple aggregation addresses. The output on the screen should be different now, with only the filtered relevant NMEA messages. Depending on the amount of boats you are reporting, it can take up to three minutes before at least your own boat is reported. The AIS message should start with "!AIVDM".

If you run the program with the default interval set, you will see that AISdispatcher.pl maintains a table with records for each individual MMSI number. New MMSI numbers will be added when they present themselves, and if they send too many position updates, some of them will be rejected. Again, once you get bored, it is time for the next step.

Run the program again but this time without the --test option. You should wait some minutes and then go to your "station page" on the respective aggregation site(s). They should report receiving data from you! Note that your boat won't be immediately visible on their public map or mobile phone app. Apparently, your data is first scrutinized to see if it correlates with other sources before it is made public, which can take a few days.

If all is working as intended, you can now make the installation final. The following command should be somewhere on your system so that it will run automatically when you start the computer. The option --daemon is used to specify that it should run as a service in the background.
`perl aisdispatcher.pl --daemon 0.0.0.0:10110 1.2.3.4:555`

Note that in daemon mode you won't get any screen output while it is running. If you want to have a peek about what is going on, you can run AISdispatcher.pl again with the --test mode while the daemon is still running in the background.

## Command line options

Usage:
perl aisdispatcher.pl [OPTIONS] <SOURCE IP:PORT> [<UDP TARGET IP:PORT> ...]

--help
This option displays a small help screen

--tcp
This specifies that the input source is TCP. If you can choose between UDP (the default) and TCP, always try to use UDP. In most cases TCP is better, but in this specific case UDP is the way to go. For the output channels, UDP is always used because this is what all the aggregation services use.

--gpsd
This specifies that the input source is GPSD. It includes the --tcp option because GPSD always uses TCP.

--ownship
Most AIS receivers have a special NMEA message to indicate the position of your own ship. If you have an AIS transceiver, its own broadcasted AIS signal is already included in the standard messages, so the ownship messages are filtered out. I'm not sure however how AIS receiving only devices handle this (but you should not use them on a ship anyway) but if your stream shows other boats but not your own, you can use the option --ownship to specifically include the own position messages.

--justme
If you only care about your own boat position on the map, or are worried about the privacy of your fellow boaters, or want to cut down even more on your data consumption, you can use the --justme option. In that case only information about your own boat will be revealed.

--interval=<SECONDS>
By default AIS position updates from individual MMSI's are not sent more frequently than 25 seconds apart. You can change this value to anything you like. Anything less than 4 seconds disables the position update throttling (and saves some CPU and memory usage). Try to avoid values that are a multitude of 30, as this interferes with the AIS favored 30 seconds or minute intervals. For more information about this see the Technical notes.

--sid=<SOURCE ID>
With this option you can add a marking to your outgoing data so the aggregator can identify you as the source. SOURCE ID is an alphanumeric string of maximal 15 characters, for ships I would suggest to enter your MMSI number in this field. All aggregators understand --sid, except for MarineTraffic. If you feed to MarineTraffic together with other aggregators, specify the MarineTraffic HOST:IP first, then specify the --sid option, and then the other aggregators. For more information and possible uses of this option see the Technical notes.

--test
If this option is used, AISdispatcher.pl will work in normal mode, except that it does not actually send out any data. With this option you can run AISdispatcher.pl while another instance is running in daemon mode.

--daemon
If this option is used, the program terminates but leaves a service running in the background. Note that in this case you can not run a second instance of AISdispatcher.pl from the command line (except with the use of option --test), because otherwise you would be feeding all information to the aggregation services twice.

## Technical notes

### Filtering
In contrast to some other AISdispatcher software, AISdispatcher.pl actually decodes the AIS messages and applies some smart filtering.

1. All non AIS-related NMEA messages are filtered away.
2. The remaining AIS-related messages are filtered. Only the following AIS messages types remain:

- 1,2,3: Standard class-A position report
- 5: Static and voyage related data
- 9: Standard SAR aircraft position report
- 18: Standard class-B position report
- 19: Extended class-B position report
- 24: Static data report

3. The frequency of AIS update reports is depending on the situation. For a class-B station at anchor, it drops down to one message per 3 minutes. However, for a fast or turning class-A station, the updates will be broadcasted only 2 seconds apart! This might be great for navigational purposes, however it is not in the interest of the typical MarineTraffic user to get so many updates and it is just a waste of your data. To alleviate this, AISdispatcher.pl maintains a list of all MMSI stations and times of their most recent updates. If MMSI stations are sending position update reports (message type 1,2,3 or 18) more frequently than the interval value (default 25 seconds) it will downsample only those position updates of these specific MMSI numbers.

Note that the smart filtering requires a bit more CPU and memory, so if you run AISdispatcher.pl on a memory or CPU constrained system, you might switch it off with "--interval=0" at the expense of a bit more data consumption in high traffic areas.

### Interval
A bit more information about sensible values for the --interval option. By default, a class-B AIS transponder broadcasts a position update every 30 seconds when the boat is sailing. To avoid recurring broadcast collisions with nearby other boats this interval is intentionally slightly variable. If you would instruct AISdispatcher.pl to only allow position updates once in every 30 seconds, then when the transponder is giving one update slightly faster it will be rejected because it is "too soon", and during the next interval when the transponder might use a slightly longer interval it will be accepted. This causes the update frequency on the output of AISdispatcher.pl to look somewhat erratic with half of the time a rejected position update. With an interval which is set somewhat lower than the transponder interval, you won't have this problem, and that is why the default is set at 25 seconds. Consequently, if you wish to allow only a position update once per minute, specify an interval of 55. Don't set the interval too long, because at some point the aggregation service will see the updates as "glitches" rather than a steady stream of position updates, and they might flag your station as "low/poor coverage". I think that an update frequency of 3 minutes (use --interval=170) would still be acceptable, but note that due to the nature of AIS you might sometimes miss a transponder update, so in reality the updates could become longer apart.

### Relaying
If you are feeding multiple aggregation services, your data consumption goes up with each additional target aggregation service. One way to overcome this is to setup a shore bound relay. There are two ways to achieve this:

1. Assuming you have access to a computer running somewhere ashore, with a fixed IP address, you could setup AISdispatcher.pl on your boat to forward your AIS data only to the IP:PORT of your shore station (as if it is an aggregation service). If you need to use option --sid, do this not on your boat but on the shore computer. On the shore station you run AISdispatcher.pl with its input listening to your boat output, and with the multiple final aggregation targets as its own outputs. On the shore station use --interval=0 and no further options (except for --daemon and/or --sid), because the filtering is already done on your boat. Of course the output HOST:IP of your boat should match the input HOST:IP of your shore station, and you will have to setup the router of your shore station to forward the relevant port to the computer running AISdispatcher.pl, and if you have a firewall installed you have to configure it as well.

2. You can use a relay on our ZwerfCat server for a small fee. Ask us for more information if you are interested.

### Source ID (--sid)
With this option you can add a marking to the outgoing data. It uses the NMEA 4.0 tag block. The following is prepended to the NMEA sentence: 

\s:<SID>*<NMEA CHECKSUM>\

According to the NMEA 4.0 specs, this should be accepted by NMEA interpreters, and indeed, almost all AIS aggregators do, with the notable exception of MarineTraffic.

The Source ID feature can be used as extra safety, if the AIS aggregator uses it for authentication, it becomes harder to submit bogus AIS data in someone else's feed data port.

Also, it can be used in cases where just one UDP port accepts data from anyone. With the Source ID feature it is still possible to distinguish between different AIS stations.
