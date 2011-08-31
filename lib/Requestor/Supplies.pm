package Requestor::Supplies;

use strict;
use warnings;

use Requestor::Base;

use base 'Requestor::Base';

# implementor API:
# init: set button_names, types, queuename, 
sub init {
    my $self = shift;
    my %types;
    $types{s} = 'supply';
    $self->{types} = \%types;
    $self->{queuename} = 'Supplies';
    my %button_names;
    $button_names{supply} = 'Request a supply';
    $self->{buttons} = \%button_names;
}

sub ordered_types {
    return qw(supply);
}

sub has_date {
    my $self = shift;
    my $type = $self->{type};
    if($type eq 'other') {
	return 0;
    } else {
	return 1;
    }
}

sub has_login {
    return 0;
}

sub login_information {
    my $info = {};
    $info->{user} = "ticketcloser";
    $info->{password} = "ticketticketticket";
    return $info;
}

# save, setup, parse

sub setup {
    my $self = shift;
    my $form = $self->quickform($self->{fname}, 'Submit Changes', $self->{mode}, $self->{tid});
    $self->{form} = $form;
    my $type = $self->{type};

    my $dateformat = '/^[0-9]{4}\/?(0?[1-9]|1[0-2])\/?(0?[1-9]|[1-2][0-9]|3[0-1])$/';

    $form->field(name => 'name', label => 'Supply Name', type => 'text', required => 1);
#    $form->field(name => 'quantity', label => 'Quantity', type => 'text', required => 0);
    $form->field(name => 'notes', type => 'textarea',  cols => '80', rows => '10');

#    $form->field(name => 'date', label => 'Requested Date', type => 'text', required => 0, validate => $dateformat);
#    $form->field(name => 'date_chooser', type => 'button', label => '', value => 'Date Chooser');
}

sub preparse {
    my $self = shift;

    $self->{new_only} = 1;
    if(!defined($self->{type})) {
	$self->{type} = "supply";
	$self->{new_only} = 0;
	my $subject = $self->get_subject($self->{tid});
	$self->{subject} = $subject;
    }
}

sub parse {
    my $self = shift;
    my $form = $self->{form};
    my $subject = $self->{subject};

    unless($form->submitted) {
#    my @parts = @{[$subject =~ /^(.)\.\s+([^-]+)(?:-(.+))?,\s+(.+)/]};
#    my $date = $parts[1];
	$form->field(name => 'name', value => $subject);	
    }
}

sub has_date { # FIXME: remove once the date is uncommented above
    return 0;
}

sub save {
    my $self = shift;
    my $form = $self->{form};
    my $text = $form->field('notes');
    my $name = $form->field('name');
    my $subject = "";
    $subject = $name;
    $self->{subject} = $subject;
    $self->do_save($subject, $text);
}

1;
