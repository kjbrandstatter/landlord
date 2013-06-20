package Landlord::Group;
use Landlord::Utils;
use strict;
use warnings;

use vars qw($VERSION @ISA @EXPORT @EXPORT_OK);
require Exporter;
@ISA = qw(Exporter AutoLoader);
$VERSION = '0.01';

@EXPORT = qw();

@EXPORT_OK = qw(add_group delete_group add_to_group delete_from_group);

# Group Related functions
sub add_group {
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

   Landlord::Utils::sql_modify($query);
}

sub delete_group {
   my ($gname) = @_;
   if (not $gname) { die "No group name given\n"; }


   `groupdel $gname`;


   my $query = "delete from groups where name == '$gname';";

   Landlord::Utils::sql_modify($query);
}

sub add_to_group {
   my ($user, $group) = @_;
   die "Invalid arguments" if not $user or not $group;
   `gpasswd -a $user $group`;
   #my $stmt = "INSERT into group_memberships values ('$user', '$group');";
   my $stmt = "INSERT into group_memberships select uid,gid from ".
              "(SELECT id as uid from users where username = '$user') ".
              "join (select id as gid from groups where name = '$group');";
   Landlord::Utils::sql_modify($stmt);
}

sub delete_from_group {
   my ($user, $group) = @_;
   die "Invalid arguments" if not $user or not $group;
   `gpasswd -r $user $group`;
   my $stmt = "Delete from group_memberships where user = '$user' AND group = '$group';";
   Landlord::Utils::sql_modify($stmt);
}

1;
__END__
