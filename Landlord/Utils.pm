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
   ...
   #STUB
}

sub generate_password {
   my @letters = ('A'..'Z', 'a'..'z',0..9);
   my $pword = join '', (map { $_ = $letters[rand(@letters)]; } (0..$_[0]));
   return $pword;
}


sub init_db {
   my $drop =<< 'END_SQL';
drop table if exists group_memberships;
drop table if exists archives;
drop view if exists user_group;
drop table if exists users;
drop table if exists groups;
END_SQL
   my $user_create =<< 'END_SQL';
create table users (
id integer primary key not null,
username char(20) not null,
fullname char(50) not null,
email char(50),
home char(50) not null,
status integer not null default 1,
expire_date DATE not null );
END_SQL
   my $group_create =<< 'END_SQL';
create table groups (
id integer primary key not null,
name char(50) not null,
description char(200) );
END_SQL
   my $group_assoc =<< 'END_SQL';
create table group_memberships (
user_id integer not null,
group_id integer not null,
primary key (user_id,group_id),
foreign key (user_id) references users(id) on delete cascade,
foreign key (group_id) references groups(id) on delete cascade);
END_SQL
   my $archive_table =<< 'END_SQL';
CREATE table archives (id integer primary key autoincrement,
username char(50) not null, email char(50) not null,
remove_date DATE not null, encpass char(20) );
END_SQL
   my $user_group_view =<< 'END_SQL';
create view user_group as select username, groups.name
from (select username , group_id from users
join group_memberships as gu on users.id = gu.user_id)
as ug join groups on ug.group_id = groups.id;
END_SQL
   sql_modify(
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

# Deprecate this
sub sql_modify {
   my ($query) = @_;
   my $dbh = open_db();
   $dbh->begin_work;
   $dbh->do("PRAGMA foreign_keys=ON;");
   for (split(/;/, $query)){
      print "$_\n"; # For debugging purposes
      $dbh->do($_);
   }
   $dbh->commit;
   $dbh->disconnect();
}

# Deprecate
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
   close(ACTIVE);
   my $active_list = join("','", @active_users);
   my $update =<< "END_SQL";
update users set expire_date = DATE('now', '+6 month')
where username in ('$active_list');
END_SQL
   sql_modify($update);
}

sub refresh_database_info {
   refresh_users();
   refresh_groups();
   refresh_memberships();
}

# These functions are to verify consistency, they should be used very infrequently
# They are currently inefficient, but i prefer inefficient if it guaruntees consistency
# Ill continue to optimize to make them more efficient
sub refresh_users {
   my $query =<< "END_SQL";
create temp table tmpuser (
id integer primary key,
username char(50) unique not null,
fullname char(50) not null,
email char(50),
home char(50) not null,
status integer not null,
expire_date DATE not null);
END_SQL
   open(PASSWD, "</etc/passwd") or die "Failed to open passwd file";
   for (<PASSWD>) {
      chomp;
      my @fields = split ":";
      $fields[4] =~ m/(.*)(?:<(.*)>)?/;
      my $name = $1;
      my $email = $2 ? $2 : "";
      my $home = $fields[5];
      if ($fields[2] >= 1000 and $fields[2] < 65534) {
         $query .=<< "END_SQL";
INSERT INTO tmpuser
(id, username, fullname, email, home, status, expire_date) VALUES
($fields[2], '$fields[0]', '$name', '$email', '$home', 1, date('now'));
END_SQL
      }
   }
   close PASSWD;
   $query .=<< "END_SQL";
insert into users select * from tmpuser
where tmpuser.id not in (select id from users);
delete from users
where id in (select id from users except select id from tmpuser);
END_SQL
   sql_modify($query);
}
sub refresh_groups {
   my $query =<< "END_SQL";
CREATE temp TABLE tmpgroups (
id integer primary key,
name char(50) not null,
description char(200) );
END_SQL
   open(GROUPS, "</etc/group") or die "Failed to open group file";
   for (<GROUPS>) {
      chomp;
      my @fields = split ':';
      if ($fields[2] < 1000) {
         $query .= "INSERT INTO tmpgroups (id, name) VALUES($fields[2], '$fields[0]');";
      }
   }
   $query .=<< "END_SQL";
INSERT INTO groups (id, name) select id,name from tmpgroups
where id not in (select id from groups);
END_SQL
   close GROUPS;
   sql_modify($query);
}
sub refresh_memberships {
   my $query =<< "END_SQL";
CREATE temp table tmpmemb (
user char(50),
gid integer,
primary key(user,gid));
END_SQL
   open(GROUPS, "</etc/group") or die "Failed to open group file";
   for (<GROUPS>) {
      chomp;
      my @fields = split ':';
      my @members = split ',', $fields[3] if $fields[3];
      for (@members) {
         $query .= "INSERT INTO tmpmemb values ('$_', $fields[2]);";
      }
   }
   close GROUPS;
   $query .=<< "END_SQL";
insert into group_memberships
select users.id, tmpmemb.gid
from users join tmpmemb
on users.username = tmpmemb.user;
END_SQL
   sql_modify($query);
}
1
__END__
