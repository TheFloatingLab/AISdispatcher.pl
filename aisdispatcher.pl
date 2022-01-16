#!perl -w
use strict;
use Socket;

# auto-flush on socket
$| = 1;

my $VERSION="1.10";

print "AISdispatcher.pl $VERSION, by Frans Veldman s/v ZwerfCat (https://www.zwerfcat.nl)\n";

my $tcp=0;
my $gpsd=0;
my $daemon=0;
my $ownship=0;
my $justme=0;
my $test=0;
my $interval=25;
my $sid='';
my $sidsock=0;
my @sockets;

# Get command line options
foreach my $a(@ARGV) {
    $daemon=1 if($a eq "-d" || $a eq "--daemon");
    $ownship=1 if($a eq "-o" || $a eq "--ownship");
    $test=1 if($a eq "-T" || $a eq "--test");
    $tcp=1 if($a eq "-t" || $a eq "--tcp");
    $tcp=1, $gpsd=1 if($a eq "-g" || $a eq "--gpsd");
    $justme=1, $ownship=1 if($a eq "-j" || $a eq "--justme");
    $interval=$2 if($a=~/-(-interval|i)=(\d+)/);
    $sidsock=@sockets, $sid=$2 if($a=~/-(-sid|s)=([\w\d]+)/);
    if($a eq "-?" || $a eq "-h" || $a eq "--help") {
        print "\nUsage:\n";
        print "\tperl aisdispatcher.pl [OPTIONS] <SOURCE IP:PORT> [<UDP TARGET IP:PORT> ...]\n";
        print "\tWith no target specified, displays the raw NMEA from the source\n";
        print "Options:\n";
        print "\t-h   --help                Display help\n";
        print "\t-t   --tcp                 Use TCP source instead of UDP\n";
        print "\t-g   --gpsd                Use GPSD source\n";
        print "\t-o   --ownship             Include VDO messages\n";
        print "\t-j   --justme              Only AIS updates from own ship\n";
        print "\t-i   --interval=<SECONDS>  Minimum interval between position updates (default 25)\n";
        print "\t-s   --sid=<ID>            Submit Source ID\n";
        print "\t-T   --test                Run as normal, but do not really send\n";
        print "\t-d   --daemon              Run as daemon\n";
        print "Example:\n";
        print "\tperl aisdispatcher.pl -t -g -i=25 -s=ZwerfCat 127.0.0.1:2947 1.2.3.4:10110\n";
        exit;
    }
    next if($a=~/^-/);
    if($a=~/^((([0-9]|[1-9][0-9]|1[0-9]{2}|2[0-4][0-9]|25[0-5])\.){3}([0-9]|[1-9][0-9]|1[0-9]{2}|2[0-4][0-9]|25[0-5])):([0-9]+)$/) {
        push @sockets,pack_sockaddr_in($5, inet_aton($1));
    } else {
        die "Error: $a is not a valid IP:PORT address!\n";
    }
}
$interval=0 if($interval<4);

# Check that at least a source address has been specified
die "Error: No AIS source specified!\n" unless(@sockets);

print "TEST-MODE. AIS messages will not be send!\n" if($test);

# if an SID is specified, prepare it.
if($sid ne '') {
    my $sum=0;
    $sid="s:$sid";
    for (my $i=0; $i<length($sid); $i++) {
        $sum ^= ord(substr($sid,$i,1));
    }
    $sum = sprintf("%02X", $sum);
    $sid="\\$sid*$sum\\";
}

my $sock;
sourceconnect();

if(@sockets>1) {
    if(!$test) {
        # If we are going to send UDP packets, check that there are no multiple instances
        use Fcntl qw(LOCK_EX LOCK_NB);
        open our $file, '<', $0 or die $!;
        die "Another instance is already running!\n" unless (flock $file, LOCK_EX|LOCK_NB);
        daemonize() if($daemon);
    }
}

# Setup an UDP output socket
my $socktx;
socket($socktx, PF_INET, SOCK_DGRAM, getprotobyname('udp'))   || die "socket: $!";

my %mmsitbl;
my $mymmsi=0;
my $cleanuptime=time();
my $prevpayload='';

# just loop forever listening for packets
while (1) {
    my $data=<$sock>;
    if(length($data)==0) {
        # We lost the connection, so re-establish it
        close($sock) if($tcp);
        sourceconnect();
        next;
    }
    print "$data" if(@sockets<=1 && !$test);

    # Check for position update messages and extract payload, discard other type messages
    next unless($data=~/(!AI(VD[OM]),\d,\d,\d?,[AB]?,(([12359BCH]).*),\d\*..)/);
    $data=$1;
    my $aistype=$2;
    my $payload=$3;
    my $msgtype=$4;
    
    # If the --justme option is specified, we need to know our own MMSI. We can extract it from a VDO message.
    $mymmsi=getmmsi($payload) if(!$mymmsi && $aistype eq "VDO");
    
    # If --ownship is not specified, we have no use for VDO messages.
    next if(!$ownship && $aistype eq "VDO");
    
    # UDP sometimes delivers data twice. I had this problem when I was using AISdispatcher.pl as a shore relay.
    if(!$tcp) {
        next if($payload eq $prevpayload);
        $prevpayload=$payload;
    }
    
    # Get the MMSI if we need it anyway.
    my $mmsi=0;
    $mmsi=getmmsi($payload) if(!$daemon || $justme || $interval);
    
    # If --justme is specified, we're done if it is not our own MMSI (or we don't know it yet).
    next if($justme && $mmsi!=$mymmsi);

    # If the message is a position update, throttle it down.
    if($interval && $msgtype=~/[123B]/) {
        if(exists $mmsitbl{$mmsi}) {
            if($mmsitbl{$mmsi}+$interval>time()) {
                print "$mmsi update rejected\n" if(!$daemon);
                next;
            }
        } else {
            print "$mmsi added to table\n" if(!$daemon);
        }
        $mmsitbl{$mmsi}=time();
    }

    # If we are not running in daemon mode, display the info on screen
    if(!$daemon) {
        print "$mmsi ";
        if($msgtype=~/[123B]/) {
            print "position update";
        } elsif($msgtype=~/[9]/) {
            print "SAR aircraft";
        } elsif($msgtype=~/[H]/) {
            if(ord(substr($payload, 6, 1)) & 0x04) {
                print "static data B";
            } else {
                print "static data A";
            }
        } else {
            print "voyage/stat data";
        }
        print " \t\"$data\"";
        print " \tforwarded to" if(@sockets>1);
    }
    
    # Send the selected AIS messages to the specified outputs
    $data.="\n";
    for(my $i=1;$i<@sockets;$i++) {
        if(!$daemon) {
            my @target=unpack_sockaddr_in($sockets[$i]);
            my $ip=inet_ntoa($target[1]);
            print " $ip:$target[0]";
        }
        my $submit=$data;
        $submit="$sid$submit" if($i>=$sidsock);
        send($socktx, $submit, 0, $sockets[$i]) if(!$test);
    }
    print "\n" if(!$daemon);

    # Once per hour, see if we can delete some obsolete stations from the table
    if($interval && $cleanuptime+3600<time()) {
        $cleanuptime=time();
        # throw away MMSI's which are no longer within range 
        foreach my $mmsidel (keys %mmsitbl) {
            if($mmsitbl{$mmsidel}+900<time()) {
                delete $mmsitbl{$mmsidel};
                print "$mmsidel deleted from table\n" if(!$daemon);
            }
        }
    }
}


sub getmmsi {
    my($payload)=@_;
    # MMSI is in bit 8-37 (=30 bits). Each byte in the string holds 6 bits.
    # Let's first make an array of translated bytes
    my @sixtbl = unpack("C[7]", $payload);
    for(my $i=1;$i<7;$i++) {
        $sixtbl[$i]-=48;
        $sixtbl[$i]-=8 if($sixtbl[$i]>40);
    }
    
    # This is ugly coding but faster than the alternative below which works bit by bit.
    my $mmsi = ($sixtbl[1] & 0x0F);
    for(my $i=2;$i<6;$i++) {
        $mmsi = $mmsi << 6; 
        $mmsi |= $sixtbl[$i];
    }
    $mmsi = $mmsi << 2;
    $mmsi |= ($sixtbl[6] >> 4);
    
#    # Recover the bits bit by bit.
#    my $mmsi=0;
#    for(my $i=8;$i<38;$i++) {
#        $mmsi = $mmsi << 1;
#        $mmsi |= (($sixtbl[$i/6] >> 5-($i%6)) & 1);
#    }
    return $mmsi;
}


sub sourceconnect {
    if($tcp) {
        # Connect for TCP source
        print "Connecting... " if(!$daemon);
        socket($sock, PF_INET, SOCK_STREAM, getprotobyname('tcp'))   || die "socket: $!";
        setsockopt($sock, SOL_SOCKET, SO_KEEPALIVE, 1);
        connect($sock,$sockets[0]) || die "Could not connect to TCP port!\n";
        print "Connected!\n" if(!$daemon);
        if($gpsd) {
            # Configure GPSD output, and skip config messages
            send($sock,'?WATCH={"enable":true,"json":false,"nmea":true,"raw":0,"scaled":false,"timing":false,"split24":false,"pps":false}',0);
            while(my $line= <$sock>) {
                last unless($line=~/\{/);
                print $line if(!$daemon);
            }
        }
    } else {
        # Connect to UDP source
        socket($sock, PF_INET, SOCK_DGRAM, getprotobyname('udp'))   || die "socket: $!";
        setsockopt($sock, SOL_SOCKET, SO_REUSEADDR, pack("l", 1))   || die "setsockopt: $!";
        setsockopt($sock,SOL_SOCKET,SO_RCVBUF,100000);
        bind($sock, $sockets[0])  || die "bind: $!"; 
    }
}


sub daemonize {
    use POSIX;
    POSIX::setsid or die "setsid: $!";
    my $pid = fork() // die $!; #//
    if($pid) {
        print "Started daemon (PID $pid)\n";
        exit(0);
    }

    chdir "/";
    umask 0;
    open (STDIN, "</dev/null");
    open (STDOUT, ">/dev/null");
    open (STDERR, ">&STDOUT");
}

