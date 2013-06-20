#!/usr/bin/perl

package Landlord::Utils;
use strict;
use warnings;

use vars qw($VERSION @ISA @EXPORT @EXPORT_OK);
require Exporter;
@ISA = qw(Exporter AutoLoader);
$VERSION = '0.01';

@EXPORT = qw();

@EXPORT_OK = qw();

my $dbfile = "database.db"; # or read from config file etc.

# Utility functions

sub read_config_file {
}

sub generate_password {
   my @letters = ('A'..'Z', 'a'..'z',0..9);
   my $pword = "";
   my $length = $_[0];
   for (1..$length) {
      $pword .= $letters[rand(@letters)];
   }
   return $pword;
}

use DBI;

sub init_db {
   my $dbh = &open_db($dbfile);
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
   my @act;
   open(ACTIVE, "lastlog -t $time |");
   for (<ACTIVE>) {
      m/^(\w+)/;
      push @act, $1 if not $1 eq "Username";
   }
   my $update = "update users set expire_date = DATE('now', '+6 month') ".
                "where username in (" . join(",", @act) . ");";
   &sql_modify($update);
}
1
__END__
