#!/usr/bin/env perl

use warnings;
use strict;
use Getopt::Std;
use Term::ReadKey;          # used for password entry

# VARIABLE SETUP
# 
# $home: running user's homedir
# $config_dir: directory holding config file
# $config: the path to the config file
# $server: the server running iodine
# $password: the password to the iodine server
# $reconfigure: flag indicating config file should be rebuilt
# %opts: options hash
#
chomp(my $home  = `echo \$HOME`);
my $config_dir  = "$home/.iodine" ;
my $config 	= "$home/.iodine/config";
my $server 	= "";
my $password 	= "";
my $reconfigure = 0;

my %opts        = ( );
getopt("r", \%opts) ;

while ( my ($key, $value) = each(%opts) ) {
    if ($key eq 'r') {
        $reconfigure = 1;
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
    print "\n";                                 # newline for prettiness
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
        if ($option =~ /^server$/) {
            $server = $value;
        }
        elsif ($option =~ /^password$/) {
            $password = $value;
        }
        else {
            print STDERR "* WARNING: invalid option in config file!\n";
            print STDERR "  offending option: $option\n";
            print STDERR "  with value: $value\n";
        }
    }
}

print "will connect to $server with $password...\n";
