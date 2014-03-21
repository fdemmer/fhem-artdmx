##############################################
# ArtNet I/O device module
# $Id: 00_ArtNet.pm $
package main;

use strict;
use warnings;
use Time::HiRes qw(gettimeofday);

# DMX AVR ArtNet http://www.ulrichradig.de/home/index.php/avr/dmx-avr-artnetnode
# ArtNet prococol http://www.artisticlicence.com/WebSiteMaster/User%20Guides/art-net.pdf

#TODO remove rambling...
# art net:
# bcast or unicast on fixed port
# art net adresses = universes
# art net opcodes...
# one opcode is send dmx packet
# Q: can i read the last dmx state from the artnet node?
# input: 512 values
# ouput: 1 udp packet

# dmx 512 
# opcode 0x500 payload (or via serial 248 or something!)
# 512 bytes, nothing more nothing less
# config: 
# - address: single serial port or artnet device
# - channels: list/hash of: offset + number fields/name mappings
# inputs: values for each configured field
# ouput: 512 values


# light animations
# input: program, speed, etc
# ouput: list of values to set in dmx dev


use Data::Dumper;

use IO::Socket::INET;

use Memoize;
memoize("_get_artnet_header");


my $DEFAULT_IP = "2.0.0.1";
my $DEFAULT_NETMASK = "255.255.255.0";
my $DEFAULT_PORT = 6454;
my $DEFAULT_UNIVERSE = 0;

my $DEFAULT_AVR_PORT = 7600;


sub ArtNet_Initialize($)
{
  my ($hash) = @_;

  # Provider
  #$hash->{ReadyFn} = "ArtNet_Ready";
  #$hash->{ReadFn}  = "ArtNet_Read";
  $hash->{WriteFn}  = "ArtNet_Write";
  $hash->{Clients}  = ":DMXBridge:";

  # Consumer
  $hash->{DefFn}    = "ArtNet_Define";
  $hash->{UndefFn}  = "ArtNet_Undef";
  $hash->{SetFn}    = "ArtNet_Set";
  $hash->{AttrList} = "do_not_notify:1,0";
}

# define an artnet node by giving an ip and universe
sub ArtNet_Define($$)
{
  my ($hash, $def) = @_;

  Log3 undef, 1, "Artnet: def0: ".Dumper($def);
  Log3 undef, 1, "Artnet: def0: ".Dumper($hash);

  my ($name, $type, $ip, $universe) = split("[ \t]+", $def);

  # internal configuration derived from define command or defaults
  $hash->{fhem}{ip} = $ip || $DEFAULT_IP;
  $hash->{fhem}{port} = $DEFAULT_PORT;
  $hash->{fhem}{universe} = $universe || $DEFAULT_UNIVERSE;

  $hash->{STATE} = "Defined";

  # initialize udp socket
  _init_network($hash);

  Log3 undef, 1, "Artnet: def1: ".Dumper($hash);

  return 0;
}

sub ArtNet_Undef($$)
{
  my ($hash, $arg) = @_;
  Log3 undef, 1, "ArtNet_Undef: $hash->{NAME}";

  close $hash->{fhem}{socket} or die "close: $!";

  return undef;
}

# set command(s) for artnet node configuration
sub ArtNet_Set($@)
{
  my ($hash, @a) = @_;
  my ($name, $cmd, @args) = @a;

  Log3 undef, 1, "ArtNet_Set: ".$name.": ".join(", ", @a);
  #return "\"set $name\" needs at least one parameter" if(@a < 2); 

  if( $cmd eq "ip" ) {
    # configure the ip address of the avr art net node
    # usage:
    #   set <name> ip <new_ip> [<current_ip> [<new_netmask>]]
    #
    # - current_ip is optional (defaults to current configuration)
    # - current_ip may be "255.255.255.255" to broadcast the configuration
    # - new_netmask is optional (defaults to "255.255.255.0")
    my ($new_ip, $old_ip, $new_netmask) = @args;

    $old_ip = $old_ip || $hash->{fhem}{ip};
    $new_netmask = $new_netmask || $DEFAULT_NETMASK;
    Log3 undef, 1, "ArtNet_Set: ip: old=$old_ip, new=$new_ip/$new_netmask";
    
    my $sock = _get_udp_socket($old_ip, $DEFAULT_AVR_PORT);
    return "Could not create socket!" unless defined $sock;

    # configure ip address on avr artnet node
    $sock->send('CMD IP '
      .pack('C*', split(/\./, $new_ip))
      .pack('C*', split(/\./, $old_ip))
      .pack('C*', split(/\./, $new_netmask))
    ) or die "ArtNet send error: $!\n";
    close $sock or die "close: $!";

    # re-define module with new ip address
    my $ret = CommandModify(undef, "$name $new_ip $hash->{fhem}{universe}");

    Log3 undef, 1, "ArtNet_Set: ip: network reconfigured";

  } elsif( $cmd eq "poll" ) {
    # sends and artnet poll packet, but does not do anything with the response

    my $reply_dest = 0; # 0 = bcast, 1 = ucast
    my $reply_type = 1; # 0 = do not send, 1 = do send
    my $reply_event = 0; # 0 = only send on poll, 1 = send on change

    my $msg = pack('b*', $reply_dest.$reply_type.$reply_event."00000");
    my $prio = pack('x');

    my $sock = _get_udp_socket($hash->{fhem}{ip}, $DEFAULT_PORT);
    return "Could not create socket!" unless defined $sock;

    $sock->send(_get_artnet_header(0x2000) # OpPoll
        .$msg
        .$prio
    ) or die "ArtNet send error: $!\n";
    close $sock or die "close: $!";

    Log3 undef, 1, "ArtNet_Set: poll";
  }

  return undef;
}

# send a bunch of data over the wire as art dmx packet
sub ArtNet_Write($$$)
{
  my ($hash, $name, $data) = @_;

  return "socket not opened" unless defined $hash->{fhem}{socket};

  $hash->{fhem}{socket}->send(
    _get_artdmx_packet($hash->{fhem}{universe}, $data)
  ) or die "ArtNet send error: $!\n";
}


# setup the socket for artnet according to $hash->{fhem}{ip} and {port}
sub _init_network($)
{
  my ($hash) = @_;

  $hash->{fhem}{socket} = _get_udp_socket(
    $hash->{fhem}{ip}, $hash->{fhem}{port}
  );
  return "Could not create socket!" unless defined $hash->{fhem}{socket};

  $hash->{STATE} = "Initialized";
  return 1;
}

# get a udp socket to a specific ip/port or broadcast address
sub _get_udp_socket($$)
{
  my ($ip, $port) = @_;

  if ($ip =~ /.+\.255$/) {
    return IO::Socket::INET->new(
      Proto     => 'udp',
      PeerPort  => $port,
      PeerAddr  => $ip,
      Broadcast => 1,
    ) or die "Could not create socket: $!\n";

  } else {
    return IO::Socket::INET->new(
      Proto     => 'udp',
      PeerPort  => $port,
      PeerAddr  => $ip,
    ) or die "Could not create socket: $!\n";
  }
}

# get an ArtDMX packet header, you should memoize that
sub _get_artdmx_packet($$)
{
  my ($universe, $data) = @_;
  return _get_artnet_header(0x5000) # ArtDMX
    .pack('x').pack('x')
    .pack('n', $universe)
    .pack('n', scalar @{$data})
    .pack('C*', @{$data});
}

sub _get_artnet_header($)
{
  my ($opcode) = @_;
  return 'Art-Net'
    .pack('x')
    .pack('v', $opcode)
    .pack('n', 14);
}

1;

=pod
=begin html

<a name="ArtNet"></a>
<h3>ArtNet</h3>
<ul>
 ...
</ul>

=end html
=cut
