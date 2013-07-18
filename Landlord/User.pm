use strict;
use warnings;

package Landlord::User;
use Landlord::Utils qw(open_db);
use DBI;
use feature "say";

use vars qw($VERSION @ISA @EXPORT @EXPORT_OK);
require Exporter;
@ISA = qw(Exporter AutoLoader);
$VERSION = '0.01';

@EXPORT = qw();

@EXPORT_OK = qw(add_user delete_user);


# User Related functions
sub add_user {
   my $dbh = open_db();
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

   my $sth = $dbh->prepare($query);

   `useradd $opts $username`;
   $sth->execute($uid, $username, $fullname, $email, $home);
   $dbh->disconnect();
   #Landlord::Utils::sql_modify($query) if `useradd $opts $username`;
   `echo $username:$pass | chpasswd`;
   `passwd -e $username`;
}
sub delete_user {
   my $username = $_[0];
   # change these to get the info from the sql database instead
   open PASSWD, "</etc/passwd";
   my $home = (map { split ":" } grep(/$username/, <PASSWD>))[5];
   close PASSWD;

   # rcopy didnt work, perhaps used incorrectly
   `cp -r $home /home/archive`;

   my $dbh = open_db();
   my $query =<< "END_SQL";
INSERT INTO archives (username, email, remove_date) select username, email, expire_date from users where username = ?;
UPDATE archives set remove_date = DATE('now') where username = ?;
DELETE FROM users where username = ?;
END_SQL
   `userdel -r $username`;
   for (split(";", $query)) {
      say;
      # I would prefer to use prepare/execute, but that wasn't working.
      $dbh->do($_, \my %xattr, $username);
   }

   $dbh->disconnect();

   #Landlord::Utils::sql_modify($query) if `userdel -r $username`;
}
sub reset_password {
   my $username = $_[0];
   my $newpass = Landlord::Utils::generate_password(8);

   `echo $username:$newpass | chpasswd`;
   `echo $newpass > $username`; # replace this mechanism with an email approach
   `passwd -e $username`;
}

sub expire_user {
   my ($username) = @_;
   my $query = "update users set status = 0 where username = ?;";
   my $dbh = open_db();
   $dbh->prepare($query);
   $dbh->execute($username);
   $dbh->disconnect() or die "Database operation failed $!";
   `passwd -l $username`;
   #Landlord::Utils::sql_modify($query) if `passwd -l $username`;
}

sub renew_user {
   my ($username) = @_;
   my $query = "update users set status = 1 where username = ?;";
   my $dbh = open_db();
   $dbh->prepare($query);
   $dbh->execute($username);
   $dbh->disconnect() or die "Database operation failed $!";
   #Landlord::Utils::sql_modify($query) if 
   `passwd -u $username`;
}

sub expire_inactive_users {
   &check_activity(7); # TODO Configureable
   my $query = "select username from users where expire_date < DATE('now');";
   my $results = Landlord::Utils::sql_request($query);
   expire_user($$_[0]) for (@$results);
}

sub delete_defunct_users {
   my $query =<< "END_SQL";
select username from users
where expire_date < DATE('now', '-3 months')
and status = 0;
END_SQL
   my $results = Landlord::Utils::sql_request($query);
   delete_user($$_[0]) for (@$results);
}

sub delete_stale_archives {
   my $query =<< "END_SQL";
select username from archives
where remove_date < DATE('now', '-12 months');
END_SQL
   my $result = Landlord::Utils::sql_request($query);
   my $update = "";
   for my $row (@$result) {
      `rm -rvf /home/archive/$$row[0]`;
      $update .= "delete from archives where username = '$$row[0]';";
   }
   Landlord::Utils::sql_modify($update);
}
1;
__END__
