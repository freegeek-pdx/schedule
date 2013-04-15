package Requestor::Technocrats;

use strict;
use warnings;

use Requestor::Base;

use base 'Requestor::Base';

#Doesn't get called from super class?
#sub moreheader {
#    return '<link rel="stylesheet" href="/cgi-bin/static/techno.css"></link>';
#}

sub priority {
    return 50;
}

sub transform {
    my $self = shift;
    my $value = shift;
    $value =~ s/<\/td>[^<]+<td/<\/td><\/tr><tr><td/mg;
    return $value;
}

sub hide_other_ticket_f {
    return 1;
}

sub no_other {
    return 1;
}

# implementor API:
# init: set button_names, types, queuename, 
sub init {
    my $self = shift;
    my %types;
    $types{s} = 'technocrats';
    $self->{types} = \%types;
    $self->{queuename} = 'Technocrats';
    my %button_names;
    $button_names{technocrats} = 'Submit a request to Technocrats';
    $self->{buttons} = \%button_names;
}

sub ordered_types {
    return qw(technocrats);
}

sub has_date {
    return 0;
}

sub has_login {
    return 0;
}

# save, setup, parse

sub setup {
    my $self = shift;
    my $form = $self->quickform($self->{fname}, 'Submit Technocrats Request', $self->{mode}, $self->{tid});
    $self->{form} = $form;
    my $type = $self->{type};

    $form->field(name => 'name', 
        label => 'What is your name?', 
        type => 'text', required => 1);

    $form->field(name => 'email', 
        label => 'What is your email address?',
        type => 'text', required => 1);

    $form->field(name => 'area', 
        label => 'Which area within Free Geek is your request related to, if any?<br />
            (i.e. Volunteer Desk, Tech Support, Warehouse)',
        type => 'text');

    $form->field(name => 'infrastructure',
        label => 'Which infrastructure computer and/or software is your request related to?',
        type => 'text');

    $form->field(name => 'summary',
        label => 'Please summarize your request in a few words (70 characters):<br />
            (i.e. Unable to print at volunteer desk, Joebob unable to send email, 
            Install solitaire on database server)',
        type => 'text', required => 1, maxlength => 70);

    $form->field(name => 'details',
        label => 'Please explain in detail what you are trying to do, and what you expect the outcome to be:',
        type => 'textarea');

    $form->field(name => 'steps',
        label => 'What are the exact steps you tried to complete this (if applicable)?',
        type => 'textarea');

    $form->field(name => 'result',
        label => 'What was the result you got and how is it different from the expected behavior (if applicable)?',
        type => 'textarea');

    $form->field(name => 'additional_info',
        label => 'Please provide any other information that might help us investigate this issue.<br />
        (date and time this problem occurred, specific data such as email addresses, contact IDs, crash IDs, cut-and-paste the exact error message displayed, etc.)',
        type => 'textarea');

    $form->field(name => 'when',
        label => 'When do you need this implemented by? (the urgency should be explained reasonably well from what was provided above)<br />
                  (i.e. now (1-2 hrs), today (3-6 hrs), 1-2 weeks, or a specific date)', type => 'text');

}

sub requestor {
    my $self = shift;
    my $form = $self->{form};
    my $name = $form->field('name');
    my $email = $form->field('email');
    my $req = $name . " <" . $email . ">";
    return $req;
}

sub save {
    my $self = shift;
    my $form = $self->{form};

    my $subject = $form->field('summary');
    my $text = $form->field('details');

    my $infra = $form->field('infrastructure');
    if(length($infra) > 0) {
	$text = "Infrastructure: " . $infra . "\n\n" . $text;
    }
    my $area = $form->field('area');
    if(length($area) > 0) {
	$text = "Area: " . $area . "\n\n" . $text;
    }
    my $when = $form->field('when');
    if(length($when) > 0) {
	$text = "Needed by: " . $when . "\n\n" . $text;
    }
    my $steps = $form->field('steps');
    if(length($steps) > 0) {
	$text .= "\n\nSteps to reproduce:\n" . $steps;
    }
    my $result = $form->field('result');
    if(length($result) > 0) {
	$text .= "\n\nResult and expected behavior:\n" . $result;
    }
    my $additional_info = $form->field('additional_info');
    if(length($additional_info) > 0) {
	$text .= "\n\nAdditional information:\n" . $additional_info;
    }

    $self->{subject} = $subject;
    $self->do_save($subject, $text);
}

1;
