#!/usr/bin/perl

push @INC, "./lib";
my $scriptname = shift @ARGV;
do "bin/$scriptname";
