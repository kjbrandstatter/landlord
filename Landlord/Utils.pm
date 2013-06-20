#!/usr/bin/perl

package Landlord::Utils;
use strict;
use warnings;

use vars qw($VERSION @ISA @EXPORT @EXPORT_OK);
require Exporter;
require DBI;

@ISA = qw(Exporter AutoLoader);
$VERSION = '0.01';

@EXPORT = qw();

@EXPORT_OK = qw();

my $dbfile = "database.db"; # or read from config file etc.

# Utility functions

sub read_config_file {
   #STUB
}

sub generate_password {
   my @letters = ('A'..'Z', 'a'..'z',0..9);
   my $pword = "";
   for (1..$_[0]) {
      $pword .= $letters[rand(@letters)];
   }
   return $pword;
}


sub init_db {
   my $drop = "drop table if exists group_memberships;".
         "drop table if exists archives;".
         "drop view if exists user_group; ".
         "drop table if exists users ;".
         "drop table if exists groups ;" ;
   my $user_create = "create table users (".
             "id integer primary key not null, ".
             "username char(20) not null, ".
             "fullname char(50) not null, ".
             "email char(50),".
             "home char(50) not null," .
             "status integer not null default 1,".
             "expire_date DATE not null ); ";
   my $group_create = "create table groups (" .
                     "id integer primary key not null, ".
                     "name char(50) not null, ".
                     "description char(200) );";
   my $group_assoc = "create table group_memberships (".
                     "user_id integer not null, ".
                     "group_id integer not null, ".
                     "primary key (user_id,group_id), ".
                     "foreign key (user_id) references users(id) on delete cascade, ".
                     "foreign key (group_id) references groups(id) on delete cascade);";
   my $archive_table = "CREATE table archives (id integer primary key autoincrement,".
                       "username char(50) not null, email char(50) not null,".
                       "remove_date DATE not null, encpass char(20) );";
   my $user_group_view = "create view user_group as select username, groups.name".
                  " from (select username , group_id from users".
                  " join group_memberships as gu on users.id = gu.user_id)".
                  " as ug join groups on ug.group_id = groups.id;";
   &sql_modify($dbfile,
      $drop .
      $user_create .
      $group_create .
      $group_assoc .
      $archive_table
      . $user_group_view
   ) or die "Failed to create database\n";
}

# Returns handle to database
sub open_db {
   my $dbh = DBI->connect(          # connect to your database, create if + needed
    "dbi:SQLite:dbname=$dbfile", # DSN: dbi, driver, database file
    "",                          # no user
    "",                          # no password
    { RaiseError => 1 },         # complain if something goes wrong
   ) or die $DBI::errstr;
   return $dbh;
}

sub sql_modify {
   my ($query) = @_;
   my $dbh = &open_db();
   $dbh->begin_work;
   $dbh->do("PRAGMA foreign_keys=ON;");
   for (split(/;/, $query)){
      #print "$_\n"; # For debugging purposes
      $dbh->do($_);
   }
   $dbh->commit;
   $dbh->disconnect();
}

sub sql_request {
   my ($query) = @_;
   my $dbh = &open_db($dbfile);
   my $sth = $dbh->prepare($query);
   $sth->execute();
   my $rows = $sth->fetchall_arrayref();
   $dbh->disconnect();
   return $rows;
}

sub update_active_status {
   my ($time) = @_;
   my @active_users;
   open(ACTIVE, "lastlog -t $time |");
   for (<ACTIVE>) {
      m/^(\w+)/;
      push @active_users, $1 if not $1 eq "Username";
   }
   my $update = "update users set expire_date = DATE('now', '+6 month') ".
                "where username in (" . join(",", @active_users) . ");";
   &sql_modify($update);
}

sub refresh_database_info {
   &refresh_users();
   &refresh_groups();
   &refresh_memberships();
}

# These functions are to verify consistency, they should be used very infrequently
# They are currently inefficient, but i prefer inefficient if it guaruntees consistency
# Ill continue to optimize to make them more efficient
sub refresh_users {
   my $query = "create temp table tmpuser (".
                 "id integer primary key, ".
                 "username char(50) unique not null, ".
                 "fullname char(50) not null, ".
                 "email char(50),".
                 "home char(50) not null," .
                 "status integer not null,".
                 "expire_date DATE not null); ";
   open(PASSWD, "</etc/passwd");
   for (<PASSWD>) {
      chomp;
      my @fields = split ":";
      $fields[4] =~ m/(.*)(<.*>)?/;
      my $email = "";
      $email = $2 if $2;
      my $name = $1;
      if ($fields[2] >= 1000 and $fields[2] < 65534) {
         $query .= "INSERT INTO tmpuser".
               "(id, username, fullname, email, home, status, expire_date) VALUES ".
               "($fields[2], '$fields[0]', '$name', '$email', '$fields[5]', 1, date('now')); ";
      }
   }
   close PASSWD;
   $query .= "insert into users select * from tmpuser where tmpuser.id not in (select id from users);";
   $query .= "delete from users where id in (select id from users except select id from tmpuser);";
   &sql_modify($query);
}
sub refresh_groups {
   my $query = "CREATE temp TABLE tmpgroups (id integer primary key, name char(50) not null, description char(200) );";
   open(GROUPS, "</etc/group");
   for (<GROUPS>) {
      chomp;
      my @fields = split ':';
      if ($fields[2] < 1000) {
         $query .= "INSERT INTO tmpgroups (id, name) VALUES($fields[2], '$fields[0]');";
      }
   }
   $query .= "INSERT INTO groups (id, name) select id,name from tmpgroups where id not in (select id from groups);";
   close GROUPS;
   &sql_modify($query);
}
sub refresh_memberships {
   my $query = "CREATE temp table tmpmemb (user char(50), gid integer, primary key(user,gid));";
   open(GROUPS, "</etc/group");
   for (<GROUPS>) {
      chomp;
      my @fields = split ':';
      my @members = split ',', $fields[3] if $fields[3];
      for (@members) {
         $query .= "INSERT INTO tmpmemb values ('$_', $fields[2]);";
      }
   }
   close GROUPS;
   $query .= "insert into group_memberships select users.id, tmpmemb.gid from users join tmpmemb on users.username = tmpmemb.user;";
   &sql_modify($query);
}
1
__END__
