#!/usr/bin/perl
package Landlord::SQL_Backend;
use Landlord::Utils qw(open_db);
use strict;
use warnings;

#use vars qw($VERSION @ISA @EXPORT @EXPORT_OK);
#require AutoLoader;
#require Exporter;
require DBI;

#@ISA = qw(Exporter AutoLoader);
#$VERSION = '0.01';

#@EXPORT = qw();

#@EXPORT_OK = qw();

sub new {
   my ($package) = @_;
   my $add_group_with_desc = "INSERT INTO groups (id, name, description) VALUES (? , ?, ?)";
   #%this{'add_group_with_desc', $dbh->prepare($add_group_with_desc)};
   my $add_group = "INSERT INTO groups (id, name) VALUES (? , ?)";
   my $delete_group = "delete from groups where name == ?;";
   my $add_group_membership =<< "END_SQL";
INSERT into group_memberships select uid,gid from
(SELECT id as uid from users where username = ?)
join (select id as gid from groups where name = ?);
END_SQL
   my $delete_group_membership = "Delete from group_memberships where user = ? AND group = ?;";
   my $delete_user =<< "END_SQL";
INSERT INTO archives (username, email, remove_date) select username, email, expire_date from users where username = ?;
UPDATE archives set remove_date = DATE('now') where username = ?;
DELETE FROM users where username = ?;
END_SQL
   my $mark_inactive = "update users set status = 0 where username = ?;";
   my $mark_active = "update users set status = 1 where username = ?;";
   my $select_expired = "select username from users where expire_date < DATE('now');";
   my $select_unclaimed =<< "END_SQL";
select username from users
where expire_date < DATE('now', '-3 months')
and status = 0;
END_SQL
   my $select_old_archives =<< "END_SQL";
select username from archives
where remove_date < DATE('now', '-12 months');
END_SQL

   my $user_group_view =<< 'END_SQL';
create view user_group as select username, groups.name
from (select username , group_id from users
join group_memberships as gu on users.id = gu.user_id)
as ug join groups on ug.group_id = groups.id;
END_SQL
   my $update_user_status =<< "END_SQL";
update users set expire_date = DATE('now', '+6 month')
where username in (?);
END_SQL
   my $create_tmpuser =<< "END_SQL";
create temp table tmpuser (
id integer primary key,
username char(50) not null,
fullname char(50) not null,
email char(50),
home char(50) not null,
status integer not null,
expire_date DATE not null);
END_SQL
   my $tmpuser_insert =<< "END_SQL";
INSERT INTO tmpuser
(id, username, fullname, email, home, status, expire_date) VALUES
(?, ?, ?, ?, ?, 1, date('now'));
END_SQL
   my $tmpuser_to_user =<< "END_SQL";
insert into users select * from tmpuser
where tmpuser.id not in (select id from users);
delete from users
where id in (select id from users except select id from tmpuser);
END_SQL
   my $create_tmpgroups =<< "END_SQL";
CREATE temp TABLE tmpgroups (
id integer primary key,
name char(50) not null,
description char(200) );
END_SQL
   my $tmpgroup_insert = "INSERT INTO tmpgroups (id, name) VALUES(?, ?);";
   my $tmpgroup_to_groups =<< "END_SQL";
INSERT INTO groups (id, name) select id,name from tmpgroups
where id not in (select id from groups);
END_SQL
   my $create_tmpmemb =<< "END_SQL";
CREATE temp table tmpmemb (
user char(50),
gid integer,
primary key(user,gid));
END_SQL
   my $tmpmemp_to_memb =<< "END_SQL";
insert or ignore into group_memberships
select users.id, tmpmemb.gid
from users join tmpmemb
on users.username = tmpmemb.user;
END_SQL
   my $dbfile = "database.db";
   my $dbh = DBI->connect(          # connect to your database, create if + needed
    "dbi:SQLite:dbname=$dbfile", # DSN: dbi, driver, database file
    "",                          # no user
    "",                          # no password
    { RaiseError => 1 },         # complain if something goes wrong
   ) or die $DBI::errstr;
   my $prepared_statements = {};
   my $this = [$dbh, $prepared_statements];
   bless $this, $package or die;
   return $this;
}

sub dbh {
   return shift(@_)->[0];
}

sub stmt {
   return shift(@_)->[1];
}

sub initialize {
   my ($this) = @_;
   my $dbh = open_db();
   $dbh->begin_work();
   $dbh->do("drop table if exists group_memberships;");
   $dbh->do("drop table if exists archives;");
   $dbh->do("drop view if exists user_group;");
   $dbh->do("drop table if exists users;");
   $dbh->do("drop table if exists groups;");
   my $create_user_table =<< 'END_SQL';
create table users (
id integer primary key not null,
username char(20) not null,
fullname char(50) not null,
email char(50),
home char(50) not null,
status integer not null default 1,
expire_date DATE not null );
END_SQL
   $dbh->do($create_user_table);
   my $create_group_table =<< 'END_SQL';
create table groups (
id integer primary key not null,
name char(50) not null,
description char(200) );
END_SQL
   $dbh->do($create_group_table);
   my $create_membership_table =<< 'END_SQL';
create table group_memberships (
user_id integer not null,
group_id integer not null,
primary key (user_id,group_id),
foreign key (user_id) references users(id) on delete cascade,
foreign key (group_id) references groups(id) on delete cascade);
END_SQL
   $dbh->do($create_membership_table);
   my $create_archive_table =<< 'END_SQL';
CREATE table archives (id integer primary key autoincrement,
username char(50) not null, email char(50) not null,
remove_date DATE not null, encpass char(20) );
END_SQL
   $dbh->do($create_archive_table);
   $dbh->commit();
   $dbh->disconnect();
}

sub refresh_database_info {
   my $this = shift;
   $this->refresh_users();
   $this->refresh_groups();
   $this->refresh_memberships();
}

# These functions are to verify consistency, they should be used very infrequently
# They are currently inefficient, but i prefer inefficient if it guaruntees consistency
# Ill continue to optimize to make them more efficient
sub refresh_users {
   my $this = shift;
   my $dbh = $this->dbh;
   $dbh->begin_work();
   my $query =<< "END_SQL";
create temp table tmpuser (
id integer primary key,
username char(50) not null,
fullname char(50) not null,
email char(50),
home char(50) not null,
status integer not null,
expire_date DATE not null);
END_SQL
   $dbh->do($query);
   open(PASSWD, "</etc/passwd") or die "Failed to open passwd file";
   my $insert =<< "END_SQL";
INSERT INTO tmpuser
(id, username, fullname, email, home, status, expire_date) VALUES
(?, ?, ?, ?, ?, 1, date('now'));
END_SQL
   my $sth = $this->cache($insert);
   for (<PASSWD>) {
      chomp;
      my @fields = split ":";
      $fields[4] =~ m/(.*)(?:<(.*)>)?/;
      my $name = $1;
      my $email = $2 ? $2 : "";
      my $home = $fields[5];
      if ($fields[2] >= 1000 and $fields[2] < 65534) {
         $sth->execute($fields[2], $fields[0], $name, $email, $home);
      }
   }
   close PASSWD;
   $query =<< "END_SQL";
insert into users select * from tmpuser
where tmpuser.id not in (select id from users);
delete from users
where id in (select id from users except select id from tmpuser);
END_SQL
   $dbh->do($query);
   $dbh->commit();
}
sub refresh_groups {
   my $this = shift;
   my $dbh = $this->dbh;
   $dbh->begin_work();
   my $query =<< "END_SQL";
CREATE temp TABLE tmpgroups (
id integer primary key,
name char(50) not null,
description char(200) );
END_SQL
   $dbh->do($query);
   my $cache = $this->stmt;
   my $insert = "INSERT INTO tmpgroups (id, name) VALUES(?, ?);";
   my $sth = $this->cache($insert);

   open(GROUPS, "</etc/group") or die "Failed to open group file";
   for (<GROUPS>) {
      chomp;
      my @fields = split ':';
      if ($fields[2] < 1000) {
         $sth->execute($fields[2], $fields[0]);
      }
   }
   $query =<< "END_SQL";
INSERT INTO groups (id, name) select id,name from tmpgroups
where id not in (select id from groups);
END_SQL
   $dbh->do($query);
   close GROUPS;
   $dbh->commit();
}
sub refresh_memberships {
   my $this = shift;
   my $dbh = $this->dbh;
   $dbh->begin_work();
   my $query =<< "END_SQL";
CREATE temp table tmpmemb (
user char(50),
gid integer,
primary key(user,gid));
END_SQL
   $dbh->do($query);
   my $insert = "INSERT INTO tmpmemb values (?, ?);";
   my $sth = $this->cache($insert);
   open(GROUPS, "</etc/group") or die "Failed to open group file";
   for (<GROUPS>) {
      chomp;
      my @fields = split ':';
      my @members = split ',', $fields[3] if $fields[3];
      for (@members) {
         $sth->execute($_, $fields[2]);
      }
   }
   close GROUPS;
   $query =<< "END_SQL";
insert or ignore into group_memberships
select users.id, tmpmemb.gid
from users join tmpmemb
on users.username = tmpmemb.user;
END_SQL
   $dbh->do($query);
   $dbh->commit();
   $dbh->disconnect();
}

sub cache {
   my ($this, $query) = @_;
   if (not exists $this->stmt->{$query}){
      $this->stmt->{$query} = $this->dbh->prepare($query);
   }
   return $this->stmt->{$query};
}

sub sql_transaction {
   my ($this, $pairs) = @_;
   my $dbh = $this->dbh;
   $dbh->begin_work();
   $dbh->do("PRAGMA foreign_keys=ON;");
   while (my ($query, $args) = each %$pairs) {
      my $sth = $this->cache($query);
      $sth->execute(@$args);
   }
   $dbh->commit();
}

sub sql_request {
   my ($this, $query, @args) = @_;
   my $sth = $this->cache($query);
   $sth->execute(@args);
   my $rows = $sth->fetchall_arrayref();
   return $rows;
}

1;
__END__
