fhem-artdmx
===========

ArtNet and DMX modules for FHEM


Introduction
------------

The fhem-artnet package provides three modules for primitive ArtNet and 
DMX support.


The ArtNet module is used to define an IO device that sends ArtNet messages 
via UDP. 

The only tested device is the DMX AVR ArtNet node by Ulrich Radig. 
http://www.ulrichradig.de/home/index.php/avr/dmx-avr-artnetnode


The DMXBridge module stores a byte array for all the DMX512 channels and 
writes it to the ArtNet device configured as IO device.


A DMXDevice represents a group of one or more DMX channels representing the 
actuall device controlled via DMX, for example three channels for RGB LEDs.


One could probably replace the ArtNet module with something else sending 
DMX512 frames and still reuse the DMXBridge and DMXDevice modules.


Installation
------------

The latest fhem-artdmx modules can be installed directly from the repository 
using the built in update mechanism for thirdparty code:

    update thirdparty https://raw.githubusercontent.com/fdemmer/fhem-artdmx/master artdmx check
    update thirdparty https://raw.githubusercontent.com/fdemmer/fhem-artdmx/master artdmx


Configuration
-------------

Define an ArtNet IO device using its IP address and ArtNet universe:

    define ArtNet0 ArtNet 192.168.10.90 0

Define a DMXBridge using the ArtNet device as IO device:

    define DMX0 DMXBridge
    attr DMX0 IODev ArtNet0

Finally define one or more DMXDevices:

    define LED1 DMXDevice rgba 13,12,11,15
    attr LED1 IODev DMX0
    attr LED1 webCmd rgb:rgb ff0000:rgb 00ff00:rgb 0000ff:pct:on:off

    define LED2 DMXDevice flash 14,16
    attr LED2 IODev DMX0
    #attr LED2 devStateIcon {(DMXDevice_devStateIcon($name),"toggle")}
    attr LED2 webCmd pct:on:off

