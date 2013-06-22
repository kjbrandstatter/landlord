use strict;
use warnings;

package Landlord::User;
use Landlord::Utils;
use feature "say";

use vars qw($VERSION @ISA @EXPORT @EXPORT_OK);
require Exporter;
@ISA = qw(Exporter AutoLoader);
$VERSION = '0.01';

@EXPORT = qw();

@EXPORT_OK = qw(add_user delete_user);


# User Related functions
sub add_user {
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


   `useradd $opts $username`;
   `echo $username:$pass | chpasswd`;
   `passwd -e $username`;
   open PASSWD, "</etc/passwd" or die $!;
   my $uid = (map { split ":" } grep(/$username/, <PASSWD>))[2];
   close PASSWD;

   my $query =<< "END_SQL";
INSERT INTO users
(id, username, fullname, email, status, expire_date, home)
VALUES ($uid, '$username', '$fullname', '$email', 1, date('now', '+6 month'), '/home/$username');
END_SQL

   Landlord::Utils::sql_modify($query);
}
sub delete_user {
   my $username = $_[0];
   # change these to get the info from the sql database instead
   open PASSWD, "</etc/passwd";
   my $home = (map { split ":" } grep(/$username/, <PASSWD>))[5];
   close PASSWD;

   `cp -r $home /home/archive`; # rcopy didnt work, perhaps used incorrectly
   `userdel -r $username`; # technical debt. we wrap these everywhere
   #delete_user('username' => $username);

   my $query =<< "END_SQL";
INSERT INTO archives (username, email, remove_date)
select username, email, expire_date from users where username = '$username';
UPDATE archives set remove_date = DATE('now') where username = '$username';
DELETE FROM users where username='$username';
END_SQL

   Landlord::Utils::sql_modify($query);
}
sub reset_password {
   my $username = $_[0];
   my $newpass = generate(8);

   `echo $username:$newpass | chpasswd`;
   `echo $newpass > $username`;
   `passwd -e $username`;
}

sub expire_user {
   my ($username) = @_;
   my $query = "update users set status = 0 where username = '$username';";
   `passwd -l $username`;
   Landlord::Utils::sql_modify($query);
}

sub renew_user {
   my ($username) = @_;
   my $query = "update users set status = 1 where username = '$username';";
   `passwd -u $username`;
   Landlord::Utils::sql_modify($query);
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
      `rm -rv /home/archive/$$row[0]`;
      $update .= "delete from archives where username = '$$row[0]';";
   }
   Landlord::Utils::sql_modify($update);
}
1;
__END__
