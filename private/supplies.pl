#!/usr/bin/perl

package main;

use File::Basename;

use lib dirname($0) . "/../lib";

use Requestor::Supplies;

my $req = Requestor::Supplies->new;
$req->handle;

