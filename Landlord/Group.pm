use strict;
use warnings;

package Landlord::Group;
use Landlord::Utils;

sub addgroup {
   my ($gname, $desc) = @_;

   if (not $gname) { die "No group name given\n"; }
   # Set the default options. We shall expand this later
   my $opts = "";

   `groupadd $gname`;
   my $gid;
   open(GROUP, "</etc/group");
   for (<GROUP>){
      if (m/^$gname:.*:(\d+)/){
         $gid = $1;
         last;
      }
   }
   close GROUP;

   my $query;
   if ($desc) {
      $query = "INSERT INTO groups (id, name, description) ".
         "VALUES ('$gid' , '$gname', '$desc')";
   }
   else {
      $query = "INSERT INTO groups (id, name) VALUES ('$gid' , '$gname')";
   }

   my $dbfile = 'database.db';      # your database file

   use Landlord::Utils;

   Landlord::Utils::run_transaction($dbfile, $query);
}

sub delgroup {
   my ($gname) = @_;
   if (not $gname) { die "No group name given\n"; }


   `groupdel $gname`;


   my $query = "delete from groups where name == '$gname';";

   my $dbfile = 'database.db';      # your database file

   use Landlord::Utils;

   Landlord::Utils::run_transaction($dbfile, $query);
}
1
