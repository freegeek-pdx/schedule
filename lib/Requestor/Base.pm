package Requestor::Base;

use CGI::Session;
use CGI::FormBuilder;
use RT::Client::REST;
use RT::Client::REST::User;
use Error qw(:try);

use strict;
use warnings;

sub has_end_date {
    return 0;
}

sub has_date {
    return 1;
}

sub has_login {
    return 1;
}

sub get_login_information {
    my $self = shift;
    if($self->has_login) {
	my $info = {};
	$info->{user} = $self->{session}->param('username');
	$info->{password} = $self->{session}->param('password');
	return $info;
    } else {
	return $self->login_information;
    }
}

sub new {
    my $class = shift;
    my $self = {};
    bless $self, $class;
    $self->init;
    return $self;
}

sub init {
    return;
}

sub get_types {
    my $self = shift;
    $self->{types};
}

sub queuename {
    my $self = shift;
    $self->{queuename};
}

sub button_names {
    my $self = shift;
    $self->{buttons};
}

sub handle {
    my $self = shift;
    $self->run();
}

sub get_email_for_user {
    my ($self, $user) = @_;
    return RT::Client::REST::User->new( rt  => $self->{rt}, id => $user )->retrieve->email_address;
}

sub run {
    my $self = shift;
    my $hostname = `hostname`;
    chomp $hostname;
    my $domain =  ($hostname eq 'art') ? 'localhost' : 'todo.freegeek.org';
    my $rt = RT::Client::REST->new(
	server => 'http://' . $domain . '/rt',
	timeout => 30,
	);

    my @fields = ('username', 'password');
    my $masterform = CGI::FormBuilder->new(fields => \@fields, header => 1, method   => 'post', keepextras => ['mode'], required => 'ALL', name => 'login', title => $self->queuename . ' RT request (login same as todo.freegeek.org)');

    $masterform->field(name => 'password', type => 'password');
    my $session = CGI::Session->new('driver:File',
				    $masterform->sessionid,
				    { Directory=>'/tmp' });

    $masterform->sessionid($session->id);
    $session->expire('+12h');

    my @lfields = ();
    my $logout_form = CGI::FormBuilder->new(fields => \@lfields, header => 1, method   => 'post', submit => 'Logout', name => 'logout', required => 'ALL', title => $self->queuename . ' Requests');
    if(!$self->has_login) {
	$logout_form->submit(0);
    }
    $logout_form->sessionid($session->id);

    my $mode = $masterform->cgi_param('mode') || "index";
    my $tid = $masterform->cgi_param('tid');

    $self->{session} = $session;

    if(!$self->has_login || $session->param('IS_LOGGED_IN')) {
	if ($logout_form->submitted) {
	    $session->delete();
	    print $masterform->render;
	} else {
	    my $success;
	    my $info = $self->get_login_information;
	    my $user = $info->{user};
	    my $pass = $info->{password};

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
		print $logout_form->render;
	    }
	    if($success) {
		$self->{user} = $user;
		$self->{mode} = $mode;
		$self->{tid} = $tid;
		$self->{logout_form} = $logout_form;
		$self->{rt} = $rt;
		if($self->has_login) {
		    $logout_form->text("Logged in as " . $user);
		}
		$self->do_main;
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
		if($self->has_login) {
		    $logout_form->text("Logged in as " . $user);
		}
	    $self->{user} = $user;
	    $self->{mode} = $mode;
	    $self->{tid} = $tid;
	    $self->{logout_form} = $logout_form;
	    $self->{rt} = $rt;
	    $self->do_main;
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
    my ($self, $name, $text, $mode, $tid) = @_;
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
    my ($self, $id) = @_;
    $self->{rt}->show(type => 'ticket', id => $id)->{Subject};
}

sub save_changes {
    my($self, $subject, $text) = @_;
    if(defined($self->{tid})) {
	my $cur_subject = $self->{rt}->show(type => 'ticket', id => $self->{tid})->{Subject};
	unless($text eq "") {
	    $self->{rt}->comment(
		ticket_id   => $self->{tid},
		message     => $text,
		);
	}
	unless($cur_subject eq $subject) {  # disable?
	    $self->{rt}->edit (type => 'ticket', id => $self->{tid}, set => { subject => $subject });
	}
    } else {
	$self->{tid} = $self->{rt}->create(type => 'ticket', set => {priority => 0,
						     requestors => [$self->get_email_for_user($self->{user})], # FIXME when no has_login
						     queue => $self->queuename,
						     subject => $subject}, text => $text)
    }
    $self->{subject} = $subject;
    return $self->{tid};
}

sub dchar_type {
    my $self = shift;
    my $type = $self->{type};
    return @{[split //, $type]}[0];
}

sub do_main {
    my $self = shift;
    if($self->{mode} eq "index") {
	$self->index;
    } else {
	$self->non_index_action;
    }
}

sub hide_other_ticket_f {
    return 1;
}

sub index {
    my $self = shift;
    print $self->{logout_form}->render . "<hr />";
    my $query = "Queue = '" . $self->queuename ."' AND (Status = 'open' OR Status = 'new' OR Status = 'stalled')";
    if($self->has_login) {
	$query = "Creator = '" . $self->{user} . "' AND " . $query;
    }
    my @ids = $self->{rt}->search(
	type => 'ticket',
	query => $query
	); 
    for my $id (@ids) {
	my $subj = $self->get_subject($id);
	print $self->quickform('ticket_$id','Add to or change request #' . $id . ": " . $subj, 'edit', $id)->render;
    }
    my $o_ticket_form = CGI::FormBuilder->new(fields => ['tid'], method   => 'post', submit => 'Edit ticket', name => 'arbitrary_ticket', keepextras => ['mode'], labels => {'tid' => 'Other ticket'});
    $o_ticket_form->cgi_param('mode', 'edit'); # FIXME: other end needs ot verify that this is in correct queue
    unless($self->hide_other_ticket_f) {
	print $o_ticket_form->render;
    }
    print "<hr />";
    
    foreach($self->ordered_types) {
	print $self->quickform('new_$_',$self->button_names->{$_}, 'new_' . $_)->render;
    }
}

sub non_index_action {
    my $self = shift;
    my $fname = $self->{mode};
    if(defined($self->{tid})) {
	$fname .= "_" . $self->{tid};
    }
    $self->{fname} = $fname;
    my $type = @{[$self->{mode} =~ /^new_(.*)$/]}[0];
    $self->{type} = $type;

    $self->preparse; # set type

    $self->setup; # make $form

    if(defined($self->{tid})) {
	$self->parse;
    }

    # happens before form render or back button, THAT WAY THAT DOESN'T SHOW UP

    $self->{logout_form}->title($self->{logout_form}->title . ": " . ($self->{mode} eq "edit" ? "edit" : "new") . " " . $self->{type} . " request");
    print $self->{logout_form}->render . "<hr />";
    my $form = $self->{form};
    if($form->submitted && $form->validate) {
	$self->save;
#	$self->{mode} = "index";
#	return $self->do_main;
    } else {
	$self->render;
    }
    print "<hr />";
    print $self->quickform('back', 'Back to Main Page', 'index')->render;
}

sub render {
    my $self = shift;
    my $form = $self->{form};
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

    if($self->has_date) {
    print '<script type="text/javascript">
    Calendar.setup({
        inputField     :    "date",
        ifFormat       :    "%Y/%m/%d",
        showsTime      :    false,
        button         :    "date_chooser",
    });
</script>
';
    }
    if($self->has_end_date) {
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
}


sub do_save {
    my ($self, $subject, $text) = @_;
    my $newticket = 0;
    my $ferror;
    try {
	$newticket = $self->save_changes($subject, $text);
    } catch Exception::Class::Base with {
	$ferror = shift->message;
    };
    if($newticket == 0) {
	print "<span style='color: red'><b>There was an error while trying to save: " . $ferror . "</b></span>";
    } else {
	print '<table border="1">';
	    print "<tr><th colspan=2>Your submission has been received and saved in ticket #" . $newticket . "</td></tr>";
	for my $field ($self->{form}->fields) {
	    next if $field->name =~ /chooser/i;
	    my $val = $field->value;
	    if($val) {
		my $n = $field->label;
		print "<tr><td>";
		print $n;
		print "</td><td><pre>";
		print $val;
		    print "</pre></td></tr>"
	    }
	}
	print "</table>";
    }
    return;
}

1;
