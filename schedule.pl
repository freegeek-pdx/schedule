#!/usr/bin/perl

package main;

use File::Basename;

use lib dirname($0) . "/lib";

use Requestor::Schedule;

my $req = Requestor::Schedule->new;
$req->handle;

