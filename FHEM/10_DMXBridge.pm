##############################################
# $Id: 10_DMXBridge.pm $
#
# by fdemmer@gmail.com
#
# #TODO description
#
package main;

use strict;
use warnings;

use Data::Dumper;

use SetExtensions;


sub DMXBridge_Initialize($)
{
  my ($hash) = @_;

  # Provider
  #$hash->{ReadFn}   = "DMXBridge_Read";
  $hash->{WriteFn}  = "DMXBridge_Write";
  #$hash->{ReadyFn}  = "DMXBridge_Ready";
  $hash->{Clients}  = ":DMXDevice:";

  # Consumer
  $hash->{Match}    = "^DMXBridge";
  $hash->{DefFn}    = "DMXBridge_Define";
  $hash->{UndefFn}  = "DMXBridge_Undefine";
  #$hash->{GetFn}    = "DMXBridge_Get";
  $hash->{SetFn}    = "DMXBridge_Set";

  #$hash->{AttrList}= "key";
  $hash->{AttrList}  = "IODev do_not_notify:1,0 ignore:0,1 dummy:0,1 ";
  #$hash->{AttrList} = "IODev ".
  #                    $readingFnAttributes;

  $hash->{ParseFn}   = "DMXBridge_Parse";
}

sub DMXBridge_Define($$)
{
  my ($hash, $def) = @_;

  Log3 undef, 1, "DMXBridge: def0: ".Dumper($hash);

  my @args = split("[ \t]+", $def);

  return "Usage: define <name> DMXBridge [interval]"  if(@args < 2);

  #TODO not very nice because if proposed not exists, is assigned other one but DEF still set to this
  my ($name, $type, $interval) = @args;
  # $ioname     name of preferred ArtNet module
  # $interval   interval for pushing control messages

  $interval = 1 unless defined($interval);
  if( $interval < 1 ) { $interval = 1; }

  # number of channels should be configured (optional)
  # must be 512 max and ... 
  #TODO implement this

  AssignIoPort($hash);
  if(defined($hash->{IODev}->{NAME})) {
    Log3 $name, 3, "$name: I/O device is " . $hash->{IODev}->{NAME};
  } else {
    Log3 $name, 1, "$name: no I/O device";
  }

  #$modules{DMXBridge}{defptr}{$ioname} = $hash; #TODO why?

  # initialize channel map for this dmx universe
  my @channels = (0) x 512;
  $hash->{helper}{channels} = \@channels if (!$hash->{helper}{channels});
  $hash->{helper}{channels_changed} = 0;

  #InternalTimer(gettimeofday()+10, "HUEDevice_GetUpdate", $hash, 0);

  ## Help FHEMWEB split up devices
  #$attr{$name}{subType} = $1 if($name =~ m/EnO_(.*)_$a[2]/);

  $hash->{INTERVAL} = $interval;
  $hash->{STATE} = 'Initialized';

  #Log3 undef, 1, "DMXBridge: def1: ".Dumper($hash);

  return undef;
}

sub DMXBridge_Undefine($$)
{
  my ($hash, $arg) = @_;

  #RemoveInternalTimer($hash);

  delete $modules{DMXBridge}{defptr}{uc($hash->{DEF})};

  return undef;
}

sub DMXBridge_Set($@)
{
  # set a single channel to a value

  # note that when directly setting channels the state is not set in the readings
  # the dmx bridge does not save any state (data stored in hash->helper structure!
  # only dmx devices keep the state saved in readings!
  # channels set using this fn will be reset when fhem restarts and sets the state from the statefile
  my ($hash, $name, @args) = @_;

  my ($channel, $value) = @args;
  return "Usage: set $name <channel> <value>" 
    if (!defined $channel || !defined $value);
  return "Channel must be in the range of 0-512!"
    if ((0 > $channel) || ($channel > 512) || $channel !~ m/^\d+$/);
  return "Value must be in the range of 0-255!"
    if ((0 > $value) || ($value > 255) || $value !~ m/^\d+$/);

  my %channels = ( $channel => $value );
  DMXBridge_Write($hash, $hash->{NAME}, %channels);
}

sub DMXBridge_Write($$$)
{
  my ($hash, $name, %channels) = @_;
  Log3 undef, 1, "DMXBridge_Write: $name, ".Dumper(%channels);

  while (my ($key, $value) = each(%channels)) {
    if (${$hash->{helper}{channels}}[$key] != $value) {
      ${$hash->{helper}{channels}}[$key] = $value;
      $hash->{helper}{channels_changed} += 1;
    }
  }

  if ($hash->{helper}{channels_changed} > 0) {
    IOWrite($hash, $name, $hash->{helper}{channels});
    $hash->{helper}{channels_changed} = 0;
  }
}

1;

=pod
=begin html

<a name="DMX Bridge"></a>
<h3>DMX Bridge</h3>
<ul>
 ...
</ul>

=end html
=cut
