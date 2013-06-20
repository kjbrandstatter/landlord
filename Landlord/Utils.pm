#!/usr/bin/perl

use strict;
use warnings;
package Landlord::Utils;

sub generate {
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
   my $dbfile = $_[0];
   my $dbh = &db_open($dbfile);
   $dbh->do( "PRAGMA foreign_keys = ON");
   my $user_create = "create table users (".
             "id integer primary key, ".
             "username char(50) unique not null, ".
             "fullname char(50) not null, ".
             "email char(50),".
             "home char(50) not null," .
             "status integer not null default 1,".
             "expire_date DATE not null); ";
   my $group_create = "create table groups (" .
                     "id integer primary key, ".
                     "name char(50) not null, ".
                     "description char(200) );";
   my $group_assoc = "create table group_memberships (".
                     "user_id integer, ".
                     "group_id integer, ".
                     "primary key (user_id,group_id), ".
                     "foreign key (user_id) references users(id) on delete cascade, ".
                     "foreign key (group_id) references groups(id) on delete cascade );";
   &run_transaction($dbfile, $user_create . $group_create . $group_assoc) or
      die "Failed to create database\n";
}

# Returns handle to database
sub db_open {
   my $dbfile = $_[0];
   my $dbh = DBI->connect(          # connect to your database, create if + needed
    "dbi:SQLite:dbname=$dbfile", # DSN: dbi, driver, database file
    "",                          # no user
    "",                          # no password
    { RaiseError => 1 },         # complain if something goes wrong
   ) or die $DBI::errstr;
   return $dbh;
}

sub run_transaction {
   my ($dbfile, $query) = @_;
   my $dbh = &db_open($dbfile);
   $dbh->begin_work;
   $dbh->do("PRAGMA foreign_keys=ON;");
   for (split(/;/, $query)){
      $dbh->do($_);
   }
   $dbh->commit;
   $dbh->disconnect();
}

sub run_request {
   my ($dbfile, $query) = @_;
   my $dbh = &db_open($dbfile);
   $dbh->disconnect();
}
1
