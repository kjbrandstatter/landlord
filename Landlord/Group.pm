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
   my ($group, $description) = @_;

   die "No group name given\n" if (not $group);
   # Set the default options. We shall expand this later
   my $opts = "";

   `groupadd $group`;
   open(GROUP, "</etc/group");
   my $gid = (map { split ":" } grep {/$group/} <GROUP>)[2];
   close GROUP;

   my $query = $description ?
      "INSERT INTO groups (id, name, description) ".
      "VALUES ('$gid' , '$group', '$description')"
      : "INSERT INTO groups (id, name) VALUES ('$gid' , '$group')";

   Landlord::Utils::sql_modify($query);
}

sub delete_group {
   my ($group) = @_;
   die "No group name given\n" if (not $group);

   `groupdel $group`;

   my $query = "delete from groups where name == '$group';";

   Landlord::Utils::sql_modify($query);
}

sub add_to_group {
   my ($user, $group) = @_;
   die "Invalid arguments" if not $user or not $group;
   `gpasswd -a $user $group`;
   my $stmt =<< "END_SQL";
INSERT into group_memberships select uid,gid from
(SELECT id as uid from users where username = '$user')
join (select id as gid from groups where name = '$group');
END_SQL
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
