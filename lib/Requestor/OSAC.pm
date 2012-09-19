package Requestor::OSAC;

# list of options for sales type
my @options = qw(ebay bulk_amazon);
# max number of files fields
my $max = 10;

# location of files
my $file_base = "/srv/osac-images/";
# URL apache serves from
my $url_base = "/osac-images/";
# display host for URLs, external rather than "freebay" or whatever the user typed
my $host = "sales.freegeek.org";

use strict;
use warnings;

use Requestor::Base;
use CGI;

use base 'Requestor::Base';

use strict;
use warnings;

sub title2 {
    return 'OSAC file uploader';
}

sub title {
    return 'OSAC file uploader (login same as todo.freegeek.org)';
}

sub do_main {
    my $self = shift;

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
	$self->render_top();
	print "<hr />";
	my $dir_url = "http://" . $host . $url_base . $type . "/" . $date . "/" . $name . "/";
	print "Files uploaded to: <a href=\"" . $dir_url . "\">" . $dir_url . "</a><br /><br />\n";
	foreach(1..$max) {
	    my $file = $form->field('filename_' . $_);
	    if($file) {
		open F, ">$dir/$file" or die $!;
		while (<$file>) {
		    print F;
		}
		close F;
		print "Processed " . $file . ": <a href=\"" . $dir_url . $file . "\">" . $dir_url . $file . "</a><br />\n";
	    }
	}
	print "<br />" . $self->quickform("again", "Back to upload form", "again")->render;
    } else {
	$self->render_top();
	print "<hr />";
	print $form->render;
    }
}

1;
