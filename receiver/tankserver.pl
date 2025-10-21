#!/usr/bin/perl
#
# Server to collect data about Kaz and Warren's tanks and pump systems.
# (c) 2023 Warren Toomey, GPL3.
#
# Usage: tankserver.pl [-f], -f stays in the foreground (not a daemon)
#
use strict;
use warnings;
use Proc::Daemon;
use Logger::Syslog;
use Time::HiRes qw(usleep);
use RRDs;
use lib '/home/wkt/Tanks';
use BatteryModel;

###################################################
# UDP functions                                   #
# I've left the old UDP code in but commented out #
###################################################

# The UDP socket that we are bound to
# my $sock;

# Bind to a UDP port
# UDP
# sub udp_bind() {
#    my $portno = 10000;
#
#
#    # Now get a UDP server socket. Assume that we are already running
#    # if we cannot bind to our socket
#    $sock = IO::Socket::INET->new( LocalPort => $portno, Proto => 'udp' );
#    if ( !defined($sock) ) {
#
#        # info("Could not bind to socket, exiting");
#        exit(0);
#    }
#}

# Get and return a UDP message from a client
#sub getUDP_Message() {
#    my $message;
#    my $maxlen = 1024;
#    $sock->recv( $message, $maxlen );
#    return ($message);
#}

##################
# LoRa functions #
##################

# File handle for the RYLR998 module
my $LORAFH;

# Send an AT command to the RYLR998 module
sub send_lora_command {
    my $cmd = $_[0] . "\r\n";
    info("Sending $cmd\n");
    print( $LORAFH $cmd );
    usleep(500_000);

    my $answer = <$LORAFH>;
    info("Answer is $answer\n");
}

# Receive data from the RYLR998 module
sub recv_lora_data() {
    while (1) {
        my $answer = <$LORAFH>;
        if ( defined($answer) ) {

            info("Received from LoRa: $answer\n");
            my ( undef, undef, $data ) = split( /,/, $answer );
            return ($data);
        }
        usleep(500_000);
    }
}

# Initialise the RYLR998 module
sub init_lora() {
    open( $LORAFH, "+<", "/dev/ttyS0" ) || die("Cannot open TTY device: $!\n");

    my $cmd = "AT+NETWORKID=5";
    send_lora_command($cmd);
    $cmd = "AT+ADDRESS=255";
    send_lora_command($cmd);
}

###################
# Other functions #
###################

# Per-service hash of client-ids and last message-ids.
# Example: for the voltage service, tank 2 sends messge-id 18, so
# $Lastmsg{voltage}->[2] is 18.
# We ignore messages from a client if they have the same message-id
# as last recorded. This allows the client to send the same message
# multiple times to ensure that it gets delivered over UDP.
my %Lastmsg;

# Data structure of inputs to the server and how to parse them.
# Each keyword is followed by a fixed number of arguments, the
# first of which is a message-id. There is a list of which arguments
# are numeric (1) or not (0).
my %Input = (
    'voltage' => {
        'args'    => 3,
        'numlist' => [ 1, 1, 1 ],
    },
);

# Return true if the argument is not a decimal number
sub badNumber($) {
    my $arg = shift;

    return (1) if ( !$arg =~ m{^\d\.?\d$} );
}

# Array of five battery voltages, currently unknown, and
# time of last update to the RRDP database
my @Voltage     = qw(N U U U U U);
my $Vupdatetime = time();

# Save the current voltages into the RRDP database
# and reset them to unknown. Also reset the timer.
sub saveVoltages() {

    # Try to insert the voltage data into the RRDP database
    debug( "rrdupdate battery: " . join( ':', @Voltage ) );
    my $ERR = "";
    foreach ( 1 .. 9 ) {
        RRDs::update( "/home/wkt/Tanks/batteries.rrd", join( ':', @Voltage ) );

        $ERR = RRDs::error;
        last if ( !$ERR );
    }
    debug("ERROR while updating batteries.rrd: $ERR") if $ERR;

    # Reset the voltages to unknown and save the update time
    @Voltage     = qw(N U U U U U);
    $Vupdatetime = time();
}

# Become a daemon
sub startService() {

    my $daemon = Proc::Daemon->new(
    	work_dir => '/tmp',
        pid_file => '/tmp/tankserver.pid'
    );

    # See if we are already running
    my $existpid= $daemon->Status("/tmp/tankserver.pid");
    if (defined($existpid) && $existpid != 0) {
	info("Already running as pid $existpid");
	exit(1);
    }

    # Become a daemon if no -f command-line argument.
    if ( ( @ARGV != 1 ) || ( $ARGV[0] ne "-f" ) ) {

        # Exit if we are the parent
        my $pid = $daemon->Init;
        exit(0) if ( $pid != 0 );

        info("We are now a daemon");
    }

    info( "Starting at " . localtime() );
}

# Parse a client's message. These are colon-separated lines of text
# starting with a textual command name and a numeric message-id.
# Following that are data values.
#
sub parseMessage($) {
    my $message = shift;

    # Split the message into the command keyword and arguments
    my ( $cmd, @arglist ) = split( /:/, $message );

    # Error if the keyword is unknown
    if ( !defined( $Input{$cmd} ) ) {
        warn("Unrecognised message: $message");
        return;
    }

    # Get the hashref for this type of input
    my $inref = $Input{$cmd};

    # Check that we have the right number of arguments
    if ( @arglist != $inref->{args} ) {
        warn("Incorrect number of arguments: $message");
        return;
    }

    # Check all the arguments that should be numeric
    my $numargs = @{ $inref->{numlist} };
    foreach my $i ( 0 .. ( $numargs - 1 ) ) {
        next if ( $inref->{numlist}->[$i] == 0 );
        if ( badNumber( $arglist[$i] ) ) {
            warn("Non-numeric data: $message");
            return;
        }
    }

    # Ignore duplicate messages from the same client.
    # Lose the msgid from the arglist at the same time.
    my ( $msgid, $clientid ) = @arglist;
    shift(@arglist);
    if ( defined( $Lastmsg{$cmd}->[$clientid] )
        && ( $Lastmsg{$cmd}->[$clientid] == $msgid ) )
    {
        # debug("Duplicate message: $message");
        return;
    }
    $Lastmsg{$cmd}->[$clientid] = $msgid;

    # Message starts with voltage
    # debug("cmd is $cmd");
    if ( $cmd eq 'voltage' ) {

        # Get the arguments
        my ( $batteryid, $adcval ) = @arglist;

        # Update the battery's voltage with the sensor's data
        # debug("About to calc voltage from $batteryid, $adcval");
        openBattDatabase();
        my $voltage = setBatteryVoltage( $batteryid, $adcval );

        # debug("Got $voltage volts from $batteryid, $adcval");
        closeBattDatabase();

        if ( !defined($voltage) ) {
            debug("Unknown battery id: $batteryid");
            return;
        }

        # Save voltage for insertion into the RRDP database
        $Voltage[$batteryid] = $voltage;

        # Do an insert if we haven't done one in 60 seconds
        saveVoltages() if ( ( time() - $Vupdatetime ) > 60 );

        # Finished dealing with a battery update
        return;
    }
}

################
# MAIN PROGRAM #
################

startService();
init_lora();

# UDP
# udp_bind();

while (1) {

    # my $message = getMessage(); # UDP
    my $message = recv_lora_data();
    debug( "Got message " . $message . " at " . localtime() );
    parseMessage($message);
}

exit(0);
