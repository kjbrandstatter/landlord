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

   my ($uname, $name, $email, $expire) = @_;

   die "No username supplied" if not $uname;


   my $gecos = "";
   $gecos .= $name if $name;
   $gecos .= " <$email>" if $email;

   my $home = "/home/$uname"; # if not $home;
   my $shell = "/bin/bash"; # if not $shell;

   my $opts = "-m -s $shell ";
   #my %user = ( 'user' => $uname,
   #            'pass' => $pass,
   #            'shell' => $shell,
   #            'gecos' => $gecos,
   #            'group' => 'users'
   #         );
   #if ($expire) { $user{'expire'} = $expire; }
   if ($expire) { $opts .= $expire; }


   `useradd $opts $uname`;
   `echo $uname:$pass | chpasswd`;
   `passwd -e $uname`;
   my $uid = `id -u $uname`;

   my $query .= "INSERT INTO users" .
               "(id, username, fullname, email, status, expire_date, home) ".
               "VALUES ($uid, '$uname', '$name', '$email', 1, date('now', '+6 month'), '/home/$uname');";

   Landlord::Utils::sql_modify($query);
}
sub delete_user {
   my $uname = $_[0];
   # change these to get the info from the sql database instead
   my $home = `grep $uname /etc/passwd | awk -F: '{ print \$6; }'`;
   chomp $home;
   my $uid = `id -u $uname`;
   chomp $uid;

   `cp -r $home /home/archive`;
   `userdel -r $uname`;
   #delete_user('uname' => $uname);

   my $query = "INSERT INTO archives (username, email, remove_date) select username, email, expire_date from users where username = '$uname';";
   $query .= "UPDATE archives set remove_date = DATE('now') where username = '$uname';";
   $query .= "DELETE FROM users where username='$uname';";

   Landlord::Utils::sql_modify($query);
}
sub reset_password {
   my $uname = $_[0];
   my $newpass = generate(8);

   `echo $uname:$newpass | chpasswd`;
   `echo $newpass > $uname`;
   `passwd -e $uname`;
}

sub expire_user {
   my ($uname) = @_;
   my $upd = "update users set status = 0 where username = '$uname';";
   `passwd -l $uname`;
   Landlord::Utils::sql_modify($upd);
}

sub renew_user {
   my ($uname) = @_;
   my $upd = "update users set status = 1 where username = '$uname';";
   `passwd -u $uname`;
   Landlord::Utils::sql_modify($upd);
}

sub expire_inactive_users {
   &check_activity(7); # TODO Configureable
   my $scan = "select username from users where expire_date < DATE('now');";
   my @old;
   my $result = Landlord::Utils::sql_request($scan);
   for my $row (@$result) {
      &expire_user($$row[0]);
   }
}

sub delete_defunct_users {
   my $scan = "select username from users where expire_date < DATE('now', '-3 months') and status = 0;";
   my @dellist;
   my $result = Landlord::Utils::sql_request($scan);
   for my $row (@$result) {
      &delete_user($$row[0]);
   }
}

sub delete_stale_archives {
   my $scan = "select username from archives where remove_date < DATE('now', '-12 months');";
   my @dellist;
   my $result = Landlord::Utils::sql_request($scan);
   my $update = "";
   for my $row (@$result) {
      `rm -rv /home/archive/$$row[0]`;
      $update .= "delete from archives where username = '$$row[0]';";
   }
   Landlord::Utils::sql_modify($update);
}
1;
__END__
