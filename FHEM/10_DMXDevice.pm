##############################################
# $Id: 10_DMXDevice.pm $

package main;

use strict;
use warnings;

use Data::Dumper;

use SetExtensions;
use Color;


my %gets = (
  "rgb"           => 1,
  "dim"           => 1,
  "flash"         => 1,
);

my %sets = (
  "on"                  => 0,
  "off"                 => 0,
  "toggle"              => 0,
  "rgb:colorpicker,RGB" => 1,
  "dim:slider,0,1,255"  => 1,
  "flash:slider,0,1,255" => 1,
);


sub DMXDevice_Initialize($)
{
  my ($hash) = @_;

  # Consumer
  $hash->{Match}    = "^DMXDevice";
  $hash->{DefFn}    = "DMXDevice_Define";
  $hash->{UndefFn}  = "DMXDevice_Undefine";
  $hash->{GetFn}    = "DMXDevice_Get";
  $hash->{SetFn}    = "DMXDevice_Set";
  $hash->{StateFn}  = "DMXDevice_State";

  $hash->{AttrList} = "IODev ".
                      "do_not_notify:1,0 ignore:0,1 dummy:0,1 ".
                      "color-icons:1,2 ".
                      #"model:".join(",", sort keys %hueModels)." ".
                      "subType:colordimmer,dimmer,switch ".
                      $readingFnAttributes;

  #$hash->{FW_summaryFn} = "HUEDevice_summaryFn";

  #$hash->{ParseFn}   = "DMXDevice_Parse";

  # initialize fhemweb color picker
  FHEM_colorpickerInit();
}

sub DMXDevice_Define($$)
{
  my ($hash, $def) = @_;
  Log3 undef, 1, "DMXDevice_Define: $def";

  my @args = split("[ \t]+", $def);

  return "Usage: define <name> DMXDevice <type> <channels>"  if(@args < 2);

  #TODO not very nice because if proposed not exists, is assigned other one but DEF still set to this
  my ($name, $type, $device, $channels) = @args;
  Log3 undef, 1, "DMXDevice_Define: $name, $type, $device, $channels";

  AssignIoPort($hash);
  if(defined($hash->{IODev}->{NAME})) {
    Log3 $name, 3, "$name: I/O device is " . $hash->{IODev}->{NAME};
  } else {
    Log3 $name, 1, "$name: no I/O device";
  }

  #$modules{$name}{defptr}{$ioname} = $hash; #TODO why?

  #$attr{$name}{devStateIcon} = '{(DMXDevice_devStateIcon($name),"toggle")}' if( !defined( $attr{$name}{devStateIcon} ) );


  #InternalTimer(gettimeofday()+10, "HUEDevice_GetUpdate", $hash, 0);

  ## Help FHEMWEB split up devices
  #$attr{$name}{subType} = $device;

  # store list of channel numbers/keys
  my @c = split("[, \t]+", $channels);
  if ($device eq "rgba"){
    Log3 undef, 1, "DMXDevice: is RGBA device";
    @{$hash->{helper}{channels}{rgb}} = @c[0 .. 2];
    @{$hash->{helper}{channels}{a}} = ($c[3]);
  } elsif ($device eq "flash"){
    Log3 undef, 1, "DMXDevice: is FLASH device";
    @{$hash->{helper}{channels}{a}} = ($c[0]);
    @{$hash->{helper}{channels}{m}} = ($c[1]);
  } elsif ($device eq "simple"){
    Log3 undef, 1, "DMXDevice: is SIMPLE device";
    @{$hash->{helper}{channels}{a}} = ($c[0]);
  }

  $hash->{STATE} = 'Initialized';

  Log3 undef, 1, "DMXDevice: def1: ".Dumper($hash->{helper});

  return undef;
}

sub DMXDevice_Undefine($$)
{
  my ($hash, $arg) = @_;

  #RemoveInternalTimer($hash);

  delete $modules{DMXDevice}{defptr}{uc($hash->{DEF})};

  return undef;
}

sub DMXDevice_devStateIcon($)
{
  my($hash) = @_;
  $hash = $defs{$hash} if( ref($hash) ne 'HASH' );

  return undef if( !$hash );

  my $name = $hash->{NAME};

  return '<div style="width:32px;height:19px;'.
         'border:1px solid #fff;border-radius:8px;background-color:#FFFFFF"></div>';
}

sub DMXDevice_Set($@)
{
  my ($hash, $name, $cmd, @a) = @_;
  Log3 undef, 1, "DMXDevice_Set: $name $cmd ".Dumper(@a);
  
  my @match = grep($_ =~ /^$cmd($|:)/, keys %sets);

  # call set extensions function if command does not match one of our own
  # adds built-in blink and other on/off functionality
  return SetExtensions($hash, join(" ", keys %sets), $name, $cmd, @a) unless (@match == 1);
  
  # complain about missing parameters according to our set list
  return "$cmd expects $sets{$match[0]} parameters" unless (@a eq $sets{$match[0]});

  my $raw_value = $a[0];
  my @values = ();
  my @channels = ();

  # color of rgba device
  if ($cmd eq "rgb") {
    @channels = @{$hash->{helper}{channels}{rgb}};
    @values = RgbToChannels($raw_value, 3);
    readingsSingleUpdate($hash, "RGB", $raw_value, 1);

  # brightness of rgba device or absolute value of simple device
  } elsif ($cmd eq "dim") {
    @channels = @{$hash->{helper}{channels}{a}};
    @values = ($raw_value);
    readingsSingleUpdate($hash, "dim", $raw_value, 1);

  # restore previous brightness of rgba or absolute value of simple device
  } elsif ($cmd eq "on") {
    @channels = @{$hash->{helper}{channels}{a}};
    @values = (ReadingsVal($name, "dim_prev", 0));
    readingsSingleUpdate($hash, "dim", ReadingsVal($name, "dim_prev", 0), 1);

  # set brightness or absolute value of simple device to zero
  } elsif ($cmd eq "off") {
    @channels = @{$hash->{helper}{channels}{a}};
    @values = (0);
    readingsSingleUpdate($hash, "dim_prev", ReadingsVal($name, "dim", 0), 0);
    readingsSingleUpdate($hash, "dim", 0, 1);

  # flashing rate/mode of flash device (not valid for simple and rgba)
  } elsif ($cmd eq "flash") {
    @channels = @{$hash->{helper}{channels}{m}};
    @values = ($raw_value);
    readingsSingleUpdate($hash, "flash", $raw_value, 1);
  }

  # a named array where keys are channel numbers and values calues
  # it is not stored, the data only is written to the dmx bridge.
  # however, the state is saved in the readings.
  my %data;

  foreach my $channel (@channels) {
    my $value = shift @values;
    $data{$channel} = $value;
    Log3 undef, 1, "DMXDevice: setting channel $channel = $value";
  }
 
  IOWrite($hash, $hash->{NAME}, %data);

  return undef;
}


# called by setstate command
# eg. via statefile
# statefile stores readings
sub DMXDevice_State($$$$)
{
  my ($hash, $tim, $cmd, $sval) = @_;
  Log3 undef, 1, "DMXDevice_State: $tim, $cmd, $sval";

  # the readings are updated in CommandSetstate of fhem core
  # if the saved state had a timestamp newer than the current reading

  # since CommandSetstate does not send the value, only sets the 
  # module's readings/state, we need to send the values here.

  # no need to check the cmd here, just try to set it
  # the set function will ignore unknown set commands
  # (a command is eg. "rgb" for a dmx device of *type* rgb 
  #   with 3 color channels)
  Log3 undef, 1, "DMXDevice_State: calling DMXDevice_Set($hash, $hash->{NAME}, $cmd, $sval)";
  DMXDevice_Set($hash, $hash->{NAME}, $cmd, $sval);

  # setting an actual "STATE" is not supported
}


sub DMXDevice_Get($@)
{
  my ($hash, $name, $cmd, @a) = @_;
  
  return "FRM_RGB: Get with unknown argument $cmd, choose one of ".join(" ", sort keys %gets)
    unless defined($gets{$cmd});
    
}

1;

=pod
=begin html

<a name="DMXDevice"></a>
<h3>DMX Device</h3>
<ul>
    A DMX device is a device controlled by a <a href="#Artnet">Artnet Controller</a> via the DMX512 protocol.<br><br>

    <a name="DMXDevicedefine"><b>Define</b></a>
    <ul>
        <code>define &lt;name&gt; DMXDevice &lt;devicetype&gt; &lt;channels&gt;</code><br>
        <br>
        Devicetypes can be:
        <li><b>rgba:</b> a RGB device</li>
        <li><b>flash:</b> a white flashing device</li>
        <li><b>simple:</b> a 1 channel device</li>
    Examples:
    <ul>
        <code>define LED1 DMXDevice rgba 13,12,11,15</code> RGB device with three channels and one for brightness<br>
        <code>define LED2 DMXDevice flash 14,16</code> white flashing LEDs where one channel is again brightness and a second the flash rate<br>
        <code>define test1 DMXDevice simple 5</code> simple device with one channel<br>
    </ul>
    </ul><br>
    <a name="DMXDeviceattributes"><b>Attributes</b></a>
    <ul>
        <li>IODev<br>
          <code>attr LED1 IODev DMX0</code><br> defines the <a href="IODev">IODev</a> for the device</li>
        <li>webCMD<br>
          <code>attr LED1 webCmd rgb:rgb ff0000:rgb 00ff00:rgb 0000ff:dim:on:off</code><br> defines a rgb color picker, 3 color buttons and on / off switches<br>
          -or-<br>
          <code>attr LED2 webCmd dim:flash:on:off</code> defines a flash device with on / off buttons
    </ul>


</ul>

=end html
=begin html_DE

<a name="DMXDevice"></a>
<h3>DMX Device</h3>
<ul>
    Ein DMX Device ist ein Ger&auml;t, das von einem <a href="#Artnet">Artnet Controller</a> mit dem DMX512 Protokoll gesteuert wird.<br>

    <a name="DMXDevicedefine"><b>Define</b></a>
    <ul>
        <code>define &lt;name&gt; DMXDevice &lt;devicetype&gt; &lt;channels&gt;</code><br>
        <br>
        Devicetypen k&ouml;nnen sein:
        <li><b>rgba:</b> ein RGB device</li>
        <li><b>flash:</b> einfarbige Lampen die blinken</li>
        <li><b>simple:</b> ein Einkanal Ger&auml;t</li>
    Beispiele:
    <ul>
        <code>define LED1 DMXDevice rgba 13,12,11,15</code> RGB Gerauml;t mit 3 Kan&auml;len und einem Kanal f&uuml;r die Helligkeit<br>
        <code>define LED2 DMXDevice flash 14,16</code> weisse, blinkende LEDs mit einem Kanal f&uuml;r die Helligkeit und einem zweiten f&uuml;r die Blinkrate<br>
        <code>define test1 DMXDevice simple 5</code> ein Einkanal Ger&auml;t<br>
    </ul>
    </ul><br>
    <a name="DMXDeviceattributes"><b>Attributes</b></a>
    <ul>
        <li>IODev<br>
          <code>attr LED1 IODev DMX0</code><br> definiert das <a href="IODev">IODev</a> f&uuml;r das Ger&auml;t</li>
        <li>webCMD<br>
          <code>attr LED1 webCmd rgb:rgb ff0000:rgb 00ff00:rgb 0000ff:dim:on:off</code><br> definiert ein Eingabefeld f&uuml;r die HTML Farbe, 3 Farbbuttons und einen An / AUS Schalter<br>
          -oder-<br>
          <code>attr LED2 webCmd dim:flash:on:off</code> definiert ein Blinkger&auml;t mit AN / AUS Schalter
    </ul>


</ul>
=end html
=cut
