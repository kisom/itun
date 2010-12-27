#!/usr/bin/env perl
# iodine tunnel setup
# written by Kyle Isom <coder@kyleisom.net>
#
# see iodine_writeup.txt for instructions.
# 
# options:
#   -r          reconfigure tunnel
#   -k          kill tunnel
#   -p          update path to binary
#   -s          set up SSH tunnel
#   -t          hold iodine tunnel open after collapsing SSH tunnel
#               (implies -s)

use warnings;
use strict;
use Getopt::Std;
use Term::ReadKey;          # used for password entry

# VARIABLE SETUP
# 
# $home: running user's homedir
# $bin: path to iodine binary
# $config_dir: directory holding config file
# $config: the path to the config file
# $server: the server running iodine
# $password: the password to the iodine server
# $reconfigure: flag indicating config file should be rebuilt
# $update_path: flag indicated iodine path needs to be updated
# $hold_open: flag indicating iodine should be kept open even when SSH 
#             tunnel is closed down.
# $retcode: holds value of system calls
# %opts: options hash
chomp(my $home  = `echo \$HOME`);
chomp(my $bin   = `which iodine`);
my $config_dir  = "$home/.iodine" ;
my $config 	= "$home/.iodine/config";
my $server 	= "";
my $password 	= "";
my $reconfigure = 0;
my $update_path = 0;
my $hold_open   = 0;
my $retcode     = 0;
my %opts        = ( );

# SSH tunnel variables
# $setup_tunnel: flag to set up the SSH tunnel
# $lport: local port for SOCKS proxy
# $rport: ssh port on remote host
# $rhost: remote host (typically private IP)
# $ruser: ssh user on remote host
my $setup_tunnel = 0;
my $lport = 8080;
my $rport = 22;
my $rhost = "";
chomp(my $ruser = `echo \$USER`);



###################
# BEGIN MAIN CODE #
###################
# and so it begins...

# process command line options
getopt("rkpst", \%opts) ;
while ( my ($key, $value) = each(%opts) ) {
    if ($key eq 'h') {
        &usage();
    }

    if ($key eq 'r') {
        $reconfigure = 1;
    }

    elsif ($key eq 'p') {
        $update_path = 1;
    }

    elsif ($key eq 's') {
        $setup_tunnel = 1;
    }

    elsif ($key eq 't') {
        $setup_tunnel = 1;
        $hold_open = 1;
    }

    elsif ($key eq 'k') {
        &kill_iodine( );
    }
}    


# INITIAL CONFIG FILE SETUP
# Check to see if config file exists. If it doesn't, this is the first time
# the script has been run and one needs to be set up.
# 
# If it does exist but the reconfigure flag was passed, the config
# file needs to be reset.
#
# If it does exist, read the host and password.
if (! -s $config) {
    # config file doesn't exit, look for config dir
    if (! -d $config_dir) {
        # config dir doesn't exit - set it up and chmod it appropriately
        mkdir ($config_dir, 0700) or 
            die "couldn't create config dir $config_dir: $@";
    }
    # regardless of whether the config dir needed creation, we need to
    # create the config file now. Set reconfigure flag to update config
    # file and set update_path flag to update the path.
    $reconfigure = 1;
    $update_path = 1;
    open(CONFIG, ">$config") or die "could not open $config: $@";
    print CONFIG "# iodine tunnel configuration file\n";
    close CONFIG;
}    

# if the reconfigure flag is set, reconfigure the tunnel
if ($reconfigure) {
    open(CONFIG, ">$config") or die "could not open $config: $@";
    print CONFIG "# iodine tunnel configuration file\n";
    print "iodine server domain (as configured in iodine server config): ";
    chomp ($server = <STDIN>);
    print CONFIG "server: $server\n";

    # set readmode to noecho for password, get password, reset readmode
    ReadMode('noecho');
    print "iodine server password: ";
    chomp ($password = ReadLine(0));
    ReadMode('restore');
    print CONFIG "password: $password\n";
    print "\n";                                 # newline for prettiness

    # set SSH options
    print "local port for SOCKS proxy (enter 0 to use default of $lport): ";
    chomp(my $temp      = ReadLine(0));
    if ($temp) { $lport = $temp; }

    print "remote SSH port on host (enter 0 to use default of $rport): ";
    chomp($temp         = ReadLine(0));
    if ($temp) { $rport = $temp; }

    print "remote host IP address: ";
    chomp($rhost        = ReadLine(0));

    print "remote host user (hit enter to use default of $ruser): ";
    chomp($temp         = ReadLine(0));
    if ($temp) { $ruser = $temp; }
    
    print CONFIG "lport: $lport\nrport: $rport\nrhost: $rhost\n";
    print CONFIG "ruser: $ruser\n";

    print "\n";                                 # newline for prettiness
    close CONFIG;
}

# update config file with new path to iodine if update_path flag set
if ($update_path) {
    print "path to iodine binary: ";
    chomp($bin = <STDIN>);
    open(CONFIG, $config) or die "could not open $config: $@";

    my $config_file  = "";              # stores temporary config file
    my $path_updated = 0;               # flag indicating path updated
    while (<CONFIG>) {
        my ($option, $value) = split(/:\s*/, $_);
        if ($option eq 'path') {
            $config_file .= "path: $bin\n";
            $path_updated = 1;
        }
        else {
            $config_file .= $_;
        }
    }
    close CONFIG;
    
    if (!$path_updated) {
        $config_file .= "path: $bin";
    }

    open(CONFIG, ">$config") or die "coud not open $config: $@";
    print CONFIG "$config_file\n";
    close CONFIG;
}


# READ SETTINGS
# Open the config file and read the settings.
#
# If the reconfigure flag is set, $server and $password are already stored
# in memory.
if (! $reconfigure) {
    open(CONFIG, $config) or die "could not open $config: $@\n";
    while (<CONFIG>) {
        next if /^#/ ;
        my ($option, $value) = split(/:\s*/, $_);
        next if (!defined $value);
        chomp($value);                           # value has newline

        # load server and password variables
        if    ($option =~ /^server$/)   { $server   = $value; }
        elsif ($option =~ /^password$/) { $password = $value; }
        elsif ($option =~ /^path$/)     { $bin      = $value; }
        elsif ($option =~ /^lport$/)    { $lport    = $value; }
        elsif ($option =~ /^rport$/)    { $rport    = $value; }
        elsif ($option =~ /^rhost$/)    { $rhost    = $value; }
        elsif ($option =~ /^ruser$/)    { $ruser    = $value; }
        else {
            print STDERR "!!! invalid option in config file!\n";
            print STDERR "    offending option: $option\n";
            print STDERR "    with value: $value\n";
        }
    }
}

# iodine client
# if a valid path to the iodine binary isn't found, abort
if (! $bin) {
    print STDERR "!!! could not find iodine binary! check to make sure:\n";
    print STDERR "\t1. iodine has been installed\n";
    print STDERR "\t2. iodine is in your path (i.e. export PATH=\$PATH:";
    print STDERR "/home/\$USER/bin\n";
    die "\n!!! binary not found!";
    exit 1;
}

# call the iodine client with the appropriate settings
$retcode = system("sudo $bin -P $password $server");
print "[+] attempting to run iodine client...\t\t";
if ($retcode) {
    print "FAILED!\n";
    die "!!! error running iodine client!\n\t$@\n";
}
print "OK\n";

# routing table changes
# prep for routing - figure out the right routing command to use
chomp(my $platform = `uname -s`);
$platform = lc $platform;

my $route = "";
if ($platform =~ /linux/)   { 
                              $route  = "route add default gw $rhost"; 
                              $route .= " dev dns0";
                            }
elsif ($platform =~ /bsd/)  { $route  = "route add default $rhost"; }
else {
    print "please specify default route command\n";
    print "(use GATEWAY as placeholder for gateway) command: ";
    chomp($route = <STDIN>);
    $route =~ s/GATEWAY/$rhost/ ;
}

# change default route
$retcode = system("sudo $route $rhost");
print "[+] attempting to change default gateway...\t";
if ($retcode) {
    print "FAILED!\n";
    print "*** on $platform - failed with $route\n";
    die "!!! failed to set default route to $rhost!\n\t$@";
}
print "OK\n";

# cleanup
# drop sudo privileges
print "[+] dropping sudo privileges...\t\t\t";
$retcode = system("sudo -K");
if ($retcode) {
    print "FAILED!";
    die "!!! could not revoke SSH permissions (maybe because there were ".
        "no sudo privileges?) $@";
}
print "OK\n";

# at this point, an unencrypted tunnel is running
print "[+] finished setting up iodine tunnel...\n";

# if specified, set up an SSH tunnel to the server
if ($setup_tunnel) {
    print "[+] attempting to set up SSH tunnel...\n";
    print "\tusing $ruser@$rhost...\n";
    print "*** to exit out of the SSH tunnel, hit control + C\n";
    $retcode = system("ssh -C2qTnN -D $lport -p $rport -l $ruser $rhost");

    print "[+] SSH tunnel closed...\n";
    if (! $hold_open) {
        &kill_iodine( );
    }
    else {
        print "*** to kill the DNS tunnel, run $0 with the -k flag.\n";
    }
}

else {
    print "*** to kill the DNS tunnel, run $0 with the -k flag.\n";
}

exit 0;



####################
# SUB: kill_iodine #
####################
# parameters: none
# does exactly what the name implies - kills the iodine tunnel.
sub kill_iodine( ) {
    $retcode = system('sudo pkill iodine');
    if ($retcode) {
        print STDERR "could not kill iodine client!\n";
    }
    else {
        print "*** iodine client killed. Please reset your connection";
        print " to reset default route.\n";
    }
    print "[+] exiting...\n";
    exit $retcode;
}


##############
# SUB: usage #
##############
# parameters: none
# prints a usage message and die()s.
sub usage( ) {
    print "\n\ninterface to iodine client\n";
    print "written by Kyle Isom <coder\@kyleisom.net>\n";
    print "based on iodine software at http://code.kryo.se/iodine\n\n";
    print "usage: $0 -hkprst\n";
    print "\noptions:\n";
    print "\t-h          print this usage message\n";
    print "\t-k          kill tunnel\n";
    print "\t-p          update path to binary\n";
    print "\t-r          reconfigure tunnel\n";
    print "\t-s          set up SSH tunnel\n";
    print "\t-t          hold iodine tunnel open after collapsing SSH ";
    print "tunnel\n";
    print "\t            (implies -s)\n";

    exit 0;
}    
    
