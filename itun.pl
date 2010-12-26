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
# $retcode: holds value of system calls
# %opts: options hash
#
chomp(my $home  = `echo \$HOME`);
chomp(my $bin   = `/usr/bin/env iodine`);
my $config_dir  = "$home/.iodine" ;
my $config 	= "$home/.iodine/config";
my $server 	= "";
my $password 	= "";
my $reconfigure = 0;
my $update_path = 0;
my $retcode     = 0;
my %opts        = ( );

# SSH tunnel variables
# $lport: local port for SOCKS proxy
# $rport: ssh port on remote host
# $rhost: remote host (typically private IP)
# $ruser: ssh user on remote host
my $lport = 8080;
my $rport = 22;
my $rhost = "";
chomp(my $ruser = `echo \$USER`);

getopt("rkp", \%opts) ;

while ( my ($key, $value) = each(%opts) ) {
    if ($key eq 'r') {
        $reconfigure = 1;
    }

    elsif ($key eq 'p') {
        $update_path = 1;
    }

    elsif ($key eq 'k') {
        $retcode = system('sudo pkill iodine');
        if ($retcode) {
            print STDERR "could not kill iodine client!\n";
        }
        else {
            print "*** iodine client killed. Please reset your connection";
            print " to reset default route.\n";
            print "*** please remember to kill the SSH tunnel.\n";
        }
        exit $retcode;
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
    # file.
    $reconfigure = 1;
    open(CONFIG, ">$config") or die "could not open $config: $@";
    print CONFIG "# iodine tunnel configuration file\n";
    close CONFIG;
}    

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
        if ($option =~ /^server$/)      { $server   = $value; }
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

# if a valid path to the iodine binary isn't found, abort
if (! $bin) {
    print STDERR "!!! could not find iodine binary! check to make sure:\n";
    print STDERR "\t1. iodine has been installed\n";
    print STDERR "\t2. iodine is in your path (i.e. export PATH=$PATH:";
    print STDERR "/home/\$USER/bin\n";
    die "\n!!! binary not found!";
    exit 1;
}

$retcode = system("sudo $bin -P $password $server");
print "[+] attempting to run iodine client...\t\t";
if ($retcode) {
    print "FAILED!\n";
    die "!!! error running iodine client!\n\t$@\n";
}
print "OK\n";

$retcode = system("ssh -C2qTnNfn -D $lport -p $rport -l $ruser $rhost");
print "[+] attempting to set up SSH tunnel...\t\t";
if ($retcode) {
    print "FAILED!\n";
    die "!!! failed setting up SSH tunnel\n\t$@\n";
}
print "OK\n";

chomp(lc my $platform = `uname -s`);
my $route = "";
if ($platform =~ /linux/)   { $route = "route add default gw"; }
elsif ($platform =~ /bsd/)  { $route = "route add default"; }
else {
    print "please specify default route command ";
    print "(without gateway address): ";
    chomp($route = <STDIN>);
}

$retcode = system("sudo $route $rhost");
print "[+] attempting to change default gateway...\t\t";
if ($retcode) {
    print "FAILED!\n";
    die "!!! failed to set default route!\n\t$@";
}
print "OK\n";

print "[+] finished\n";

