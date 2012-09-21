#!/usr/bin/perl

# SEE CONFIGURATION IN: lib/Requestor/OSAC.pm

use warnings;
use strict;

package main;

use File::Basename;

use lib dirname($0) . "/../lib";

use Requestor::OSAC;

my $req = Requestor::OSAC->new;
$req->handle;

