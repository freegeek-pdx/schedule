#!/usr/bin/perl

use CGI::Session;
use CGI::FormBuilder;
use RT::Client::REST;
use RT::Client::REST::User;
use Error qw(:try);

use strict;
use warnings;

my %types;
$types{a} = 'schedule';
$types{b} = 'schedule';
$types{m} = 'meeting';
$types{v} = 'vacation';
$types{h} = 'hours';
$types{o} = 'other';

my %button_names;
$button_names{meeting} = 'Request a meeting';
$button_names{vacation} = 'Request a vacation';
$button_names{hours} = 'Request schedule history corrections to stop hours logging reminders';
$button_names{schedule} = 'Request other schedule changes';

my $queuename = 'Schedule';

run();

sub get_email_for_user {
    my ($rt, $user) = @_;
    return RT::Client::REST::User->new( rt  => $rt, id => $user )->retrieve->email_address;
}

sub run {
    my $hostname = `hostname`;
    chomp $hostname;
    my $domain =  ($hostname eq 'art') ? 'localhost' : 'todo.freegeek.org';
    my $rt = RT::Client::REST->new(
    server => 'http://' . $domain . '/rt',
    timeout => 30,
    );

my @fields = ('username', 'password');
my $masterform = CGI::FormBuilder->new(fields => \@fields, header => 1, method   => 'post', keepextras => ['mode'], required => 'ALL', name => 'login', title => $queuename . ' RT request (login same as todo.freegeek.org)');

$masterform->field(name => 'password', type => 'password');
my $session = CGI::Session->new('driver:File',
                                $masterform->sessionid,
                                { Directory=>'/tmp' });

$masterform->sessionid($session->id);
$session->expire('+12h');

my @lfields = ();
my $logout_form = CGI::FormBuilder->new(fields => \@lfields, header => 1, method   => 'post', submit => 'Logout', name => 'logout', required => 'ALL', title => $queuename . ' Requests');
$logout_form->sessionid($session->id);

my $mode = $masterform->cgi_param('mode') || "index";
my $tid = $masterform->cgi_param('tid');

if($session->param('IS_LOGGED_IN')) {
    if ($logout_form->submitted) {
	$session->delete();
	print $masterform->render;
    } else {
	my $success;
	my $user = $session->param('username');
	my $pass = $session->param('password');
	my $error;
    try {
	$rt->login(username => $user, password => $pass);
	$success = 1;
    } catch Exception::Class::Base with {
	$error = "problem communicating with RT server: " . shift->message;
	$success = 0;
    };
	if(!$success) {
	    $logout_form->text($error);
	}
	print $logout_form->render;
	if($success) {
	    do_main($rt, $user, $mode, $tid);
	}
    }
} elsif ($masterform->submitted && $masterform->validate) {
    my $user = $masterform->field('username');
    my $pass = $masterform->field('password');
    my $success;
    my $error;
    try {
	$rt->login(username => $user, password => $pass);
	$success = 1;
    } catch Exception::Class::Base with {
	$error = "problem logging in: " . shift->message;
	$success = 0;
    };

    if($success) {
	    $session->param('IS_LOGGED_IN', 1);
	    $session->param('username', $user);
	    $session->param('password', $pass);
	    $masterform->field(name => 'password',value => '(not shown)',		   force => 1);
	    print $masterform->confirm;
	    $logout_form->header(0); # headers always here otherwise
	print $logout_form->render;
	do_main($rt, $user, $mode, $tid);
    } else {
	$masterform->text($error);
	$masterform->field(name => 'password',value => '',		   force => 1);
	 print $masterform->render;
    }
} else {
    $masterform->field(name => 'password',value => '',		   force => 1);
    print $masterform->render;
}
}

sub quickform {
    my ($name, $text, $mode, $tid) = @_;
    my @list = ('mode');
    if(defined($tid)) {
	push @list, 'tid';
    }
    my $ticket_form = CGI::FormBuilder->new(fields => [], method   => 'post', submit => $text, name => $name, keepextras => \@list);
    $ticket_form->cgi_param('mode', $mode);
    if(defined($tid)) {
	$ticket_form->cgi_param('tid', $tid);
    }
    return $ticket_form;
}

sub get_subject {
    my ($rt, $id) = @_;
    $rt->show(type => 'ticket', id => $id)->{Subject};
}

sub save_changes {
    my($rt, $user, $tid, $subject, $text) = @_;
    if(defined($tid)) {
	my $cur_subject = $rt->show(type => 'ticket', id => $tid)->{Subject};
	unless($text eq "") {
	    $rt->comment(
		ticket_id   => $tid,
		message     => $text,
		);
	}
	unless($cur_subject eq $subject) {  # disable?
	    $rt->edit (type => 'ticket', id => $tid, set => { subject => $subject });
	}
    } else {
	$tid = $rt->create(type => 'ticket', set => {priority => 0,
	    requestors => [get_email_for_user($rt, $user)],
	    queue => $queuename,
	     subject => $subject}, text => $text)
    }
    return $tid;
}

sub dchar_type {
    my $type = shift;
    return ($type eq "schedule") ? "a" : @{[split //, $type]}[0];
}

sub do_main {
    my ($rt, $user, $mode, $tid) = @_;
    print "<hr />";
    if($mode eq "index") {
	my $query = "Creator = '$user' AND Queue = '$queuename' AND (Status = 'open' OR Status = 'new' OR Status = 'stalled')";
    my @ids = $rt->search(
	type => 'ticket',
	query => $query
	); 
    for my $id (@ids) {
	my $subj = get_subject($rt, $id);
	print quickform('ticket_$id','Add to or change request #' . $id . ": " . $subj, 'edit', $id)->render;
    }
    my $o_ticket_form = CGI::FormBuilder->new(fields => ['tid'], method   => 'post', submit => 'Edit ticket', name => 'arbitrary_ticket', keepextras => ['mode'], labels => {'tid' => 'Other ticket'});
    $o_ticket_form->cgi_param('mode', 'edit');
    print $o_ticket_form->render;
    print "<hr />";
	
    foreach(qw(meeting vacation hours schedule)) {
	print quickform('new_$_',$button_names{$_}, 'new_' . $_)->render;
    }
    } else {
	my $fname = $mode;
	if(defined($tid)) {
	    $fname .= "_" . $tid;
	}
	my $type = @{[$mode =~ /^new_(.*)$/]}[0];
	my $subject = "";
	my $char = "";
	my $new_only = 1;
	if(!defined($type)) {
	    $new_only = 0;
	    # editing, let's query RT for subj name, match the first letter into the %types hash to get type
            $subject = get_subject($rt, $tid);
	    $char = @{[$subject =~ /^(.)\./]}[0];
	    if($char) {
		$type = $types{$char};
	    } else {
		$type = 'other';
		$char = "o";
	    }
	} else {
	    $char = dchar_type($type);
	}
	my $form = quickform($fname, 'Submit Changes', $mode, $tid);
	
	my $dateformat = '/^[0-9]{4}\/?(0?[1-9]|1[0-2])\/?(0?[1-9]|[1-2][0-9]|3[0-1])$/';

	$form->field(name => 'name', label => 'Worker Name', type => 'text', required => 1);
	$form->field(name => 'notes', type => 'textarea');
	unless($type eq 'other') {
	    $form->field(name => 'date', label => 'Requested Date', type => 'text', required => 1, validate => $dateformat);
	    $form->field(name => 'date_chooser', type => 'button', label => '', value => 'Date Chooser');
	}
	if($type eq "schedule") {
	    $form->field(name => 'date', label => 'Requested Start Date');
	    $form->field(name => 'end_date', label => 'End Date (leave empty for ongoing)', type => 'text', validate => $dateformat);
	} elsif($type eq "meeting") {
	    $form->field(name => 'name', label => 'Meeting Name');
	    $form->field(name => 'notes', label => 'Specify list of attendees and any other details', required => $new_only);
	} elsif($type eq "hours") {
	    # do nothing
	    $form->field(name => 'date', label => 'Date');
	} elsif($type eq "vacation") {
	    $form->field(name => 'end_date', label => 'End Date', required => 1, type => 'text', validate => $dateformat);
	} else {
	    $form->field(name => 'name', label => 'Request Name');
	}

	if($type eq 'schedule' || $type eq 'vacation') {
	    $form->field(name => 'end_date_chooser', type => 'button', label => '', value => 'End Date Chooser');
	}

        # happens before form render or back button, THAT WAY THAT DOESN'T SHOW UP
	if($form->submitted && $form->validate) {
	    my $text = $form->field('notes');
	    my $name = $form->field('name');
	    my $subject = "";
	    my($date, $enddate);
	    unless($type eq 'other') {
		$date = $form->field('date');
	    }
	    if($type eq 'vacation' or $type eq 'schedule') {
		$enddate = $form->field('end_date');
	    }
	    if($type eq 'vacation' or ($type eq "schedule" && $enddate ne "")) {
		if($type eq 'schedule') {
		$char = "b";
	    }
		$subject = $char . ". " . $date . "-" . $enddate . ", " . $name; # {CHAR}. {START_DATE} to {END_DATE}, {NAME}
	    } elsif($type eq "other") {
		$subject = $name;
	    } else {
		$char = dchar_type($type);
		$subject = $char . ". " . $date . ", " . $name; # {CHAR}. {START_DATE}, {NAME}
	    }
	    my $newticket = save_changes($rt, $user, $tid, $subject, $text);
	    print $form->confirm;
	    return do_main($rt, $user, "index");
	} else {
	    unless($form->submitted) {
		if($char eq "b" or $char eq "v") {
		    my @parts = @{[$subject =~ /^(.)\. (.+)-(.+), (.+)/]};
		    my $date = $parts[1];
		    $form->field(name => 'date', value => $date);
		    my $end_date = $parts[2];
		    $form->field(name => 'end_date', value => $end_date);
		    my $name = $parts[3];
		    $form->field(name => 'name', value => $name);
		} elsif($char eq "o" ) {
		    my $name = $subject;
		    $form->field(name => 'name', value => $name);
		} else {
		    my @parts = @{[$subject =~ /^(.)\. (.+), (.+)/]};
		    my $date = $parts[1];
		    $form->field(name => 'date', value => $date);
		    my $name = $parts[2];
		    $form->field(name => 'name', value => $name);
		}
	    }
	}
	print $form->render;
	print '<script type="text/javascript">
var CalScript=document.createElement("script");
CalScript.src="/cgi-bin/static/calendar.js";
document.body.appendChild(CalScript);
var newSS=document.createElement("link");
newSS.rel="stylesheet";
newSS.href="/cgi-bin/static/calendar.css";
document.body.appendChild(newSS);
</script>';

print '<script type="text/javascript">
    Calendar.setup({
        inputField     :    "date",
        ifFormat       :    "%Y/%m/%d",
        showsTime      :    false,
        button         :    "date_chooser",
    });
</script>
';
	if($type eq 'schedule' || $type eq 'vacation') {
	    print '
<script type="text/javascript">
    Calendar.setup({
        inputField     :    "end_date",
        ifFormat       :    "%Y/%m/%d",
        showsTime      :    false,
        button         :    "end_date_chooser",
    });
</script>
';
	}
	print "<hr />";
	print quickform('back', 'Back to Main Page', 'index')->render;
    }
}
