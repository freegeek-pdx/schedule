package Requestor::Schedule;

use strict;
use warnings;

use Requestor::Base;

use base 'Requestor::Base';

use Date::Parse;
use Date::Format;

# implementor API:
# init: set button_names, types, queuename, 
sub init {
    my $self = shift;
    my %types;
    $types{a} = 'schedule';
    $types{b} = 'schedule';
    $types{m} = 'meeting';
    $types{v} = 'vacation';
    $types{h} = 'hours';
    $types{o} = 'other';
    $self->{types} = \%types;
    $self->{queuename} = 'Schedule';
    my %button_names;
    $button_names{meeting} = 'Request a meeting';
    $button_names{vacation} = 'Request a vacation';
    $button_names{hours} = 'Request schedule history corrections to stop hours logging reminders';
    $button_names{schedule} = 'Request other schedule changes';
    $self->{buttons} = \%button_names;
}

sub pre_validate {
    my $self = shift;
    my $form = $self->{form};
    # this does not affect the value that the validations check against, making it useless
    if($form->submitted) {
	if($self->has_date) {
	    $form->field(name => 'date', value => time2str("%Y/%m/%d", str2time($form->field('date'))));	    
	} 
	if($self->has_end_date) {
	    $form->field(name => 'end_date', value => time2str("%Y/%m/%d", str2time($form->field('end_date'))));
	}
    }
}

sub ordered_types {
    return qw(meeting vacation hours schedule);
}

# has_login, has_end_date, dchar_types, login_information
sub dchar_type {
    my $self = shift;
    my $type = $self->{type};
    return ($type eq "schedule") ? "a" : Requestor::Base::dchar_type($self);
}

sub has_end_date {
    my $self = shift;
    my $type = $self->{type};
    if($type eq 'schedule' || $type eq 'vacation') {
	return 1;
    } else {
	return 0;
    }
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

# save, setup, parse

sub setup {
    my $self = shift;
    my $form = $self->quickform($self->{fname}, 'Submit Changes', $self->{mode}, $self->{tid});
#     $form->{javascript} = 0;
    $self->{form} = $form;
    my $type = $self->{type};

    my $dateformat = '/^[0-9]{4}\/?(0?[1-9]|1[0-2])\/?(0?[1-9]|[1-2][0-9]|3[0-1])$/';

    $form->field(name => 'name', label => 'Worker Name', type => 'text', required => 1);
    $form->field(name => 'notes', type => 'textarea',  cols => '80', rows => '10');
    unless($type eq 'other') {
	$form->field(name => 'date', label => 'Requested Date', type => 'text', required => 1, validate => $dateformat);
	$form->field(name => 'date_chooser', type => 'button', label => '', value => 'Date Chooser');
    }
    if($type eq "schedule") {
	$form->field(name => 'date', label => 'Requested Start Date');
	$form->field(name => 'end_date', label => 'End Date (leave empty for ongoing)', type => 'text', validate => $dateformat);
    } elsif($type eq "meeting") {
	$form->field(name => 'name', label => 'Meeting Name');
	$form->field(name => 'notes', label => 'Specify list of attendees and any other details', required => $self->{new_only});
    } elsif($type eq "hours") {
	# do nothing
	$form->field(name => 'date', label => 'Date');
    } elsif($type eq "vacation") {
	$form->field(name => 'end_date', label => 'End Date (leave empty if only one day)', type => 'text', validate => $dateformat);
    } else {
	$form->field(name => 'name', label => 'Request Name');
    }

    if($type eq 'schedule' || $type eq 'vacation') {
	$form->field(name => 'end_date_chooser', type => 'button', label => '', value => 'End Date Chooser');
    }
}

sub preparse {
    my $self = shift;

    my ($char, $type);
    $self->{new_only} = 1;
    if(!defined($self->{type})) {
	$self->{new_only} = 0;
	# editing, let's query RT for subj name, match the first letter into the %types hash to get type
	my $subject = $self->get_subject($self->{tid});
	$self->{subject} = $subject;
	$char = @{[$subject =~ /^(.)\./]}[0];
	if($char) {
	    $type = $self->get_types->{$char};
	} else {
	    $type = 'other';
	    $char = "o";
	}
	$self->{type} = $type;
	$self->{char} = $char;
    } else {
	$self->{char} = $self->dchar_type();
    }

}

sub parse {
    my $self = shift;
    my $form = $self->{form};
    my $subject = $self->{subject};
    my $char = $self->{char};
    unless($form->submitted) {
	if($char eq "o") {
	    my $name = $subject;
	    $form->field(name => 'name', value => $name);
	} else {
	    my @parts = @{[$subject =~ /^(.)\.\s+([^-]+)(?:-(.+))?,\s+(.+)/]};
	    my $date = $parts[1];
	    $form->field(name => 'date', value => $date);
	    if($char eq "v" or $char eq "b") {
		my $end_date = $parts[2];
		$form->field(name => 'end_date', value => $end_date);
	    }
	    my $name = $parts[3];
	    $form->field(name => 'name', value => $name);
	}
    }
}

sub save {
    my $self = shift;
    my $form = $self->{form};
    my $text = $form->field('notes');
    my $name = $form->field('name');
    my $subject = "";
    my $char = $self->{char};
    my $type = $self->{type};
    my($date, $enddate);
    unless($type eq 'other') {
	$date = $form->field('date');
    }
    if($type eq 'vacation' or $type eq 'schedule') {
	$enddate = $form->field('end_date');
    }
    if(($type eq 'vacation' or $type eq "schedule") && ($enddate ne "")) {
	if($type eq 'schedule') {
	    $char = $self->{char} = "b";
	}
	$subject = $char . ". " . $date . "-" . $enddate . ", " . $name; # {CHAR}. {START_DATE} to {END_DATE}, {NAME}
    } elsif($type eq "other") {
	$subject = $name;
    } else {
	$subject = $char . ". " . $date . ", " . $name; # {CHAR}. {START_DATE}, {NAME}
    }
    $self->{subject} = $subject;
    $self->do_save($subject, $text);
}

1;
