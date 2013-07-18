use strict;
use warnings;

package Landlord::Landlord;
use Landlord::SQL_Backend;
use DBI;
use feature "say";

#use vars qw($VERSION @ISA @EXPORT @EXPORT_OK);
#require Exporter;
#@ISA = qw(Exporter AutoLoader);
#$VERSION = '0.01';

#@EXPORT = qw();

#@EXPORT_OK = qw(add_user delete_user add_group delete_group add_to_group delete_from_group);

sub new {
   my ($package) = @_;
   my $backend = Landlord::SQL_Backend->new();
   my $this = [$backend];
   bless $this, $package or die "Failed to bless Landlord";
   return $this;
}

sub backend {
   return shift(@_)->[0];
}

# User Related functions
sub add_user {
   my $this = shift;
   my $pass = Landlord::Utils::generate_password(8);
   say $pass;

   my ($username, $fullname, $email, $expire) = @_;

   die "No username supplied" if not $username;


   my $gecos .= defined $fullname;
   $gecos .= " <$email>" if $email;

   my $home = "/home/$username"; # if not $home;
   my $shell = "/bin/bash"; # if not $shell;

   my $opts = "-m -s $shell ";
   #my %user = ( 'user' => $username,
   #            'pass' => $pass,
   #            'shell' => $shell,
   #            'gecos' => $gecos,
   #            'group' => 'users'
   #         );
   #if ($expire) { $user{'expire'} = $expire; }
   #if ($expire) { $opts .= $expire; }


   open PASSWD, "</etc/passwd" or die "Could not open passwd file";
   my $uid = (map { split ":" } grep(/$username/, <PASSWD>))[2];
   close PASSWD;

   my $query =<< "END_SQL";
INSERT INTO users
(id, username, fullname, email, status, expire_date, home)
VALUES (?, ?, ?, ?, 1, date('now', '+6 month'), ?);
END_SQL

   #my $sth = $backend->cache($query);

   `useradd $opts $username`;
   #$sth->execute($uid, $username, $fullname, $email, $home);
   #Landlord::Utils::sql_modify($query) if `useradd $opts $username`;
   $this->backend->sql_transaction({$query => [$uid,$username,$fullname,$email,$home]});
   `echo $username:$pass | chpasswd`;
   `passwd -e $username`;
}
sub delete_user {
   my ($this, $username) = @_;
   # change these to get the info from the sql database instead
   open PASSWD, "</etc/passwd";
   my $home = (map { split ":" } grep(/$username/, <PASSWD>))[5];
   close PASSWD;

   # rcopy didnt work, perhaps used incorrectly
   `cp -r $home /home/archive`;

   my $trans = {
      "INSERT INTO archives (username, email, remove_date) select username, email, expire_date from users where username = ?;" => [$username],
      "UPDATE archives set remove_date = DATE('now') where username = ?;" => [$username],
      "DELETE FROM users where username = ?;" => [$username]
   };
   `userdel -r $username`;
   $this->backend->sql_transaction($trans);
   #for (split(";\n", $query)) {
   #   Landlord::Utils::custom_sql_query($dbh, $_, $username);
   #}
   #Landlord::Utils::sql_modify($query) if `userdel -r $username`;
}
sub reset_password {
   my ($this, $username) = @_;
   my $newpass = Landlord::Utils::generate_password(8);

   `echo $username:$newpass | chpasswd`;
   `echo $newpass > $username`; # replace this mechanism with an email approach
   `passwd -e $username`;
}

sub expire_user {
   my ($this, $username) = @_;
   my $query = "update users set status = 0 where username = ?;";
   $this->backend->sql_transaction({$query => [$username]});
   `passwd -l $username`;
   #Landlord::Utils::sql_modify($query) if `passwd -l $username`;
}

sub renew_user {
   my ($this, $username) = @_;
   my $query = "update users set status = 1 where username = ?;";
   $this->backend->sql_transaction({$query => [$username]});
   `passwd -u $username`;
}

sub expire_inactive_users {
   my $this = shift;
   $this->check_activity(7); # TODO Configureable
   my $query = "select username from users where expire_date < DATE('now');";
   my $results = $this->sql_request($query);
   expire_user($$_[0]) for (@$results);
}

sub delete_defunct_users {
   my $this = shift;
   my $query =<< "END_SQL";
select username from users
where expire_date < DATE('now', '-3 months')
and status = 0;
END_SQL
   my $results = $this->sql_request($query);
   delete_user($$_[0]) for (@$results);
}

sub delete_stale_archives {
   my $this = shift;
   my $query =<< "END_SQL";
select username from archives
where remove_date < DATE('now', '-12 months');
END_SQL
   my $result = $this->sql_request($query);
   my $update = "";
   for my $row (@$result) {
      `rm -rvf /home/archive/$$row[0]`;
      $update .= "delete from archives where username = '$$row[0]';";
   }
   Landlord::Utils::sql_modify($update);
}
1;

# Group Related functions
sub add_group {
   my ($this, $group, $description) = @_;

   die "No group name given\n" if (not $group);

   `groupadd $group`;
   open(GROUP, "</etc/group") or die "Cannot open group file";
   my $gid = (map { split ":" } grep {/$group/} <GROUP>)[2];
   close GROUP;

   my $query = $description ?
      { "INSERT INTO groups (id, name, description) ".
         "VALUES (? , ?, ?)" => [$gid,$group,$description]}
      : {"INSERT INTO groups (id, name) VALUES (? , ?)" => [$gid, $group] };

   $this->backend->sql_transaction($query);
}

sub delete_group {
   my ($this, $group) = @_;
   die "No group name given\n" if (not $group);

   my $query = {"delete from groups where name = ?;", => [$group]};

   `groupdel $group`;
   $this->backend->sql_transaction($query);
}

sub add_to_group {
   my ($this, $user, $group) = @_;
   die "Invalid arguments" if not $user or not $group;
   my $query =<< "END_SQL";
INSERT into group_memberships select uid,gid from
(SELECT id as uid from users where username = ?)
join (select id as gid from groups where name = ?);
END_SQL
   `gpasswd -a $user $group`;
   $this->backend->sql_transaction({$query => [$user,$group]});
}

sub delete_from_group {
   my ($this, $user, $group) = @_;
   die "Invalid arguments" if not $user or not $group;
   my $query =<< "END_SQL";
Delete from group_memberships where (user_id, group_id) in
(SELECT id as uid from users where username = ?)
join (select id as gid from groups where name = ?);
END_SQL
   `gpasswd -d $user $group`;
   $this->backend->sql_transaction({$query => [$user, $group]});
}
1;
__END__
