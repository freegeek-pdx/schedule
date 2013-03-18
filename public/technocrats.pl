#!/usr/bin/perl

package main;

use File::Basename;

use lib dirname($0) . "/../lib";

use Requestor::Technocrats;

my $req = Requestor::Technocrats->new;
$req->handle;

