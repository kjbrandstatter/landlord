use strict;
use warnings;

package Landlord::User;
use Landlord::Utils;

sub adduser {
   my $pass = Landlord::Utils::generate(8);
   print $pass . "\n";

   my ($uname, $name, $email, $expire) = @_;

   die "No username supplied" if not $uname;


   my $gecos = "";
   $gecos .= $name if $name;
   $gecos .= " <$email>" if $email;

   my $home = "/home/$uname"; # if not $home;
   my $shell = "/bin/bash"; # if not $shell;

   my $opts = "-m -G users -s $shell ";
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

   my $dbfile = 'database.db';      # your database file

   use Landlord::Utils;

   Landlord::Utils::run_transaction($dbfile, $query);
}
sub deluser {
   my $uname = $_[0];
   # change these to get the info from the sql database instead
   my $home = `grep $uname /etc/passwd | awk -F: '{ print \$6; }'`;
   chomp $home;
   my $uid = `id -u $uname`;
   chomp $uid;

   `cp -r $home /home/archive`;
   `userdel -r $uname`;
   #delete_user('uname' => $uname);

   my $query = "DELETE FROM users where username='$uname';";

   use Landlord::Utils;

   my $dbfile = "database.db";
   Landlord::Utils::run_transaction($dbfile, $query);
}
sub pass_reset {
   my $uname = $ARGV[0];
   my $newpass = Landlord::Utils::generate(8);

   `echo $uname:$newpass | chpasswd`;
   `echo $newpass > $uname`;
   `passwd -e $uname`;
}
1
