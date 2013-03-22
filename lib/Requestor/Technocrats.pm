package Requestor::Technocrats;

use strict;
use warnings;

use Requestor::Base;

use base 'Requestor::Base';

sub moreheader {
    return '<link rel="stylesheet" href="/cgi-bin/static/techno.css"></link>';
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

sub login_information {
    my $info = {};
    die "Missing file in format USER:PASS in /etc/rtconf" unless(-e "/etc/rtconf");
    my $val = `cat /etc/rtconf`;
    chomp $val;
    ($info->{user}, $info->{password}) = split ':', $val;
    return $info;
}

# save, setup, parse

sub setup {
    my $self = shift;
    my $form = $self->quickform($self->{fname}, 'Submit Changes', $self->{mode}, $self->{tid});
    $self->{form} = $form;
    my $type = $self->{type};
    $form->field(name => 'name', label => 'What is your name?', type => 'text', required => 1);
    $form->field(name => 'email', label => 'What is your email address?', type => 'text', required => 1);
    $form->field(name => 'area', label => 'Which area within Free Geek, if any, is your request related to?', type => 'text');
    $form->field(name => 'infrastructure', label => 'Which infrastructure machine and/or existing software used at Free Geek, if any, is your request related to?', type => 'text');
    $form->field(name => 'summary', label => 'Please summarize your request in a few words that explain what the issue is:', type => 'text', required => 1);
    $form->field(name => 'details', label => 'Please elaborate on the details of what you are trying to do and explain what you expect the outcome to be:', type => 'textarea');
    $form->field(name => 'steps', label => 'If our existing infrastructure already supports this functionality,<br />what are the exact steps you tried to complete this?', type => 'textarea');
    $form->field(name => 'result', label => 'If our existing infrastructure already supports this functionality,<br />what was the result you got and how is it different from the expected behavior?', type => 'textarea');
    $form->field(name => 'additional_info', label => 'Is there any other information that you think may help us investigate this issue?<br />(the date or time this problem occurred, specific data such as email addresses, contact IDs, crash IDs, etc)', type => 'textarea');
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
    my @extras = ($form->field('infrastructure'), $form->field('area'));
    my $extra = join ", ", grep {$_ && length($_) > 0} @extras;
    if(length($extra) > 0) {
	$subject = $extra . ": " . $subject;
    }

    my $text = $form->field('details');

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
