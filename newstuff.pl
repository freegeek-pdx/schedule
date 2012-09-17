#!/usr/bin/perl

my @options = qw(ebay bulk_amazon);
my $max = 10; # files

my $file_base = "/srv/osac-images/";
my $url_base = "/osac-images/";

use CGI::FormBuilder;

use strict;
use warnings;

my $form = CGI::FormBuilder->new(
    enctype => 'multipart/form-data',
    method => 'post',
    title => 'Upload online sales files:',
    submit => 'Upload!'
    );

$form->field(name => 'sale_type', type => 'select', required => 1, options => \@options);

$form->field(name => 'unique_sale_item_name', required => 1, type => 'text');

$form->field(name => 'filename_1', type => 'file', required => 1);
foreach(2..$max) {
    my $name = 'filename_' . $_;
    $form->field(name => $name, type => 'file');
}

use CGI;

if($form->submitted) {
    my $cgi = CGI->new;
    my $name = $form->field('unique_sale_item_name');
    $name =~ s/ /-/g;
    $name = lc($name);
    my $type = $form->field('sale_type');
    my @time = localtime;
    my $date = sprintf("%d%2d%d", $time[5] + 1900, $time[4] + 1, $time[3]);
    $date =~ s/ /0/g;
    mkdir $file_base . $type;
    mkdir $file_base . $type . "/" . $date;
    my $dir = $file_base . $type . "/" . $date . "/" . $name;
    mkdir $dir;
    foreach(1..$max) {
	my $file = $form->field('filename_' . $_);
	if($file) {
	    open F, ">$dir/$file" or die $!;
	    while (<$file>) {
		print F;
	    }
	    close F;
	}
    }
    print $cgi->redirect($url_base . $type . "/" . $date . "/" . $name . "/");
} else {
    print $form->render(header => 1);
}
