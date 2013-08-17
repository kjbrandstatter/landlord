#!/usr/bin/perl

use feature "say";
push @INC, "./lib";
my $scriptname = shift @ARGV;
say $scriptname;
do "bin/$scriptname" or die $!;
