#!/usr/bin/perl
package pass_generator;
use strict;
use warnings;

my @letters = ('A'..'Z', 'a'..'z',0..9);

sub generate {
   my $pword = "";
   my $length = $_[0];
   for (1..$length) {
      $pword .= $letters[rand(@letters)];
   }
   return $pword;
}
#print &generate(8);
