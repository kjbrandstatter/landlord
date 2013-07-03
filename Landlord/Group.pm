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

   open(GROUP, "</etc/group") or die "Cannot open group file";
   my $gid = (map { split ":" } grep {/$group/} <GROUP>)[2];
   close GROUP;

   my $query = $description ?
      "INSERT INTO groups (id, name, description) ".
      "VALUES ('$gid' , '$group', '$description')"
      : "INSERT INTO groups (id, name) VALUES ('$gid' , '$group')";

   Landlord::Utils::sql_modify($query) if `groupadd $group`;
}

sub delete_group {
   my ($group) = @_;
   die "No group name given\n" if (not $group);

   my $query = "delete from groups where name == '$group';";

   Landlord::Utils::sql_modify($query) if `groupdel $group`;
}

sub add_to_group {
   my ($user, $group) = @_;
   die "Invalid arguments" if not $user or not $group;
   my $query =<< "END_SQL";
INSERT into group_memberships select uid,gid from
(SELECT id as uid from users where username = '$user')
join (select id as gid from groups where name = '$group');
END_SQL
   Landlord::Utils::sql_modify($query) if `gpasswd -a $user $group`;
}

sub delete_from_group {
   my ($user, $group) = @_;
   die "Invalid arguments" if not $user or not $group;
   my $query = "Delete from group_memberships where user = '$user' AND group = '$group';";
   Landlord::Utils::sql_modify($query) if `gpasswd -r $user $group`;
}
1;
__END__
