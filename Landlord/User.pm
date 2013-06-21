use strict;
use warnings;

package Landlord::User;
use Landlord::Utils;

use vars qw($VERSION @ISA @EXPORT @EXPORT_OK);
require Exporter;
@ISA = qw(Exporter AutoLoader);
$VERSION = '0.01';

@EXPORT = qw();

@EXPORT_OK = qw(add_user delete_user);


# User Related functions
sub add_user {
   my $pass = generate(8);
   print $pass . "\n";

   my ($username, $fullname, $email, $expire) = @_;

   die "No username supplied" if not $username;


   my $gecos = "";
   $gecos .= $fullname if $fullname;
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
   my $uid = `id -u $username`;

   my $query .= "INSERT INTO users" .
               "(id, username, fullname, email, status, expire_date, home) ".
               "VALUES ($uid, '$username', '$fullname', '$email', 1, date('now', '+6 month'), '/home/$username');";

   Landlord::Utils::sql_modify($query);
}
sub delete_user {
   my $username = $_[0];
   # change these to get the info from the sql database instead
   my $home = `grep $username /etc/passwd | awk -F: '{ print \$6; }'`;
   chomp $home;
   my $uid = `id -u $username`;
   chomp $uid;

   `cp -r $home /home/archive`;
   `userdel -r $username`;
   #delete_user('username' => $username);

   my $query = "INSERT INTO archives (username, email, remove_date) select username, email, expire_date from users where username = '$username';";
   $query .= "UPDATE archives set remove_date = DATE('now') where username = '$username';";
   $query .= "DELETE FROM users where username='$username';";

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
   for my $row (@$results) {
      &expire_user($$row[0]);
   }
}

sub delete_defunct_users {
   my $query = "select username from users".
               " where expire_date < DATE('now', '-3 months') ".
               " and status = 0;";
   my $results = Landlord::Utils::sql_request($query);
   for my $row (@$results) {
      &delete_user($$row[0]);
   }
}

sub delete_stale_archives {
   my $query = "select username from archives".
               " where remove_date < DATE('now', '-12 months');";
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
