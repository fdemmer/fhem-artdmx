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
  "RGB"           => 1,
  "pct"           => 1,
#  "devStateIcon"  => 0,
);

my %sets = (
  "on"                  => 0,
  "off"                 => 0,
  "toggle"              => 0,
  "flash"               => 1,
  "rgb:colorpicker,RGB" => 1,
  "pct:slider,0,1,255"  => 1,
#  "fadeTo"              => 2,
#  "dimUp"               => 0,
#  "dimDown"             => 0,
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
    @{$hash->{helper}{channels}{b}} = ($c[1]);
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

  if ($cmd eq "rgb") {
    @channels = @{$hash->{helper}{channels}{rgb}};
    @values = RgbToChannels($raw_value, 3);
    readingsSingleUpdate($hash, "rgb", $raw_value, 0);

  } elsif ($cmd eq "pct") {
    @channels = @{$hash->{helper}{channels}{a}};
    @values = ($raw_value);
    readingsSingleUpdate($hash, "pct", $raw_value, 0);

  } elsif ($cmd eq "on") {
    @channels = @{$hash->{helper}{channels}{a}};
    @values = (10); #TODO "on" value...?!
    readingsSingleUpdate($hash, "pct", 10, 0); #TODO "on" value...?!

  } elsif ($cmd eq "off") {
    @channels = @{$hash->{helper}{channels}{a}};
    @values = (0);
    readingsSingleUpdate($hash, "pct", 0, 0);

  } elsif ($cmd eq "flash") {
    @channels = @{$hash->{helper}{channels}{b}};
    @values = ($raw_value);
    readingsSingleUpdate($hash, "flash", $raw_value, 0);
  }

  # a named array where keys are channel numbers and values calues
  # it is not stored, the data only is written to the dmx bridge
  # however the state of the channels is saved in the readings
  my %data;

  foreach my $channel (@channels) {
    my $value = shift @values;
    $data{$channel} = $value;
    Log3 undef, 1, "DMXDevice: set-rgb: $channel = $value";
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

<a name="DMX Device"></a>
<h3>DMX Device</h3>
<ul>
 ...
</ul>

=end html
=cut
