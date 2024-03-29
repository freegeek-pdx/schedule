package CGI::MyFormBuilder;

use strict;
use warnings;

use CGI::FormBuilder;
use base 'CGI::FormBuilder';

use CGI::FormBuilder::Util;

*script_name = \&action;
sub action {
    local $^W = 0;  # -w sucks (still)
    my $self = shift;
    $self->{action} = shift if @_;
    return $self->{action} if exists $self->{action};
    return $ENV{"SCRIPT_NAME"}; # that was easy?
}

sub script {
    my $self = shift;
    my $append = "";
    if($self->{header}) {
	$append .= '<script type="text/javascript" src="/cgi-bin/static/calendar.js"></script><link rel="stylesheet" href="/cgi-bin/static/calendar.css"></link><link rel="stylesheet" href="/cgi-bin/static/scaffold.css"></link><link rel="stylesheet" href="/cgi-bin/static/empty.css" media="handheld"></link><meta name="viewport" content="width=device-width"/>';
	$append .= $self->moreheader();
    }
    return $append . CGI::FormBuilder::script($self, @_);
}

sub moreheader {
    if($ENV{"SCRIPT_NAME"} =~ /technocrats/) {
	return '<link rel="stylesheet" href="/cgi-bin/static/techno.css"></link>';
    } else {
	return '';
    }
}

package Requestor::Base;

use CGI::Session;
use RT::Client::REST;
use RT::Client::REST::FromConfig;
use RT::Client::REST::User;
use Error qw(:try);
use Date::Parse;
use Date::Format;

use strict;
use warnings;

sub preparse {
    return;
}

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
    my $info = {};
    $info->{user} = $self->{session}->param('username');
    $info->{password} = $self->{session}->param('password');
    return $info;
}

sub new {
    my $class = shift;
    my $self = {};
    bless $self, $class;
    $self->init;
    return $self;
}

sub render_top {
    my $self = shift;
    print $self->{logout_form}->render;
    $self->link_hook;
    return;
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

sub title {
    my $self = shift;
    return $self->queuename . ' RT request (login same as todo.freegeek.org)';
}

sub title2 {
    my $self = shift;
    return $self->queuename . ' Requests';
}

sub user_is_allowed {
    return 1;
}

sub do_login {
    my $self = shift;
    my $logout_form = shift;
    my $masterform = shift;

    my $hostname = `hostname`;
    chomp $hostname;

    my $success = 0;

	    try {
		if($self->has_login) {
		    my $domain =  ($hostname eq 'art') ? 'localhost' : 'todo.freegeek.org';
		    my $info = $self->get_login_information;
		    my $user = $info->{user};
		    my $pass = $info->{password};
		    if(defined($masterform)) {
			$user = $masterform->field('username');
			$pass = $masterform->field('password');
		    }
		    my $rt = RT::Client::REST->new(
			server => 'http://' . $domain,
			timeout => 30,
			);
		    $rt->login(username => $user, password => $pass);
		    $self->{user} = $user;  # FIXME? needed?
		    $self->{rt} = $rt;

		    $logout_form->text("Logged in as " . $user);
		} else {
		    my $rt = RT::Client::REST::FromConfig->new( "/root/.rtrc"	);
		    $self->{rt} = $rt;
		}
		$success = 1;
	    } catch Exception::Class::Base with {
		$logout_form->text("problem communicating with RT server: " . shift->message);
		$success = 0;
	    };
    return $success;
}

sub run {
    my $self = shift;

    my @fields = ('username', 'password');
    my $masterform = CGI::MyFormBuilder->new(fields => \@fields, header => 1, method   => 'post', keepextras => ['mode'], required => 'ALL', name => 'login', title => $self->title);

    $masterform->field(name => 'password', type => 'password');
    my $session = CGI::Session->new('driver:File',
				    $masterform->sessionid,
				    { Directory=>'/tmp' });

    $masterform->sessionid($session->id);
    $session->expire('+12h');

    my @lfields = ();
    my $logout_form = CGI::MyFormBuilder->new(fields => \@lfields, header => 1, method   => 'post', submit => 'Logout', name => 'logout', required => 'ALL', title => $self->title2);
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

	    my $success = $self->do_login($logout_form);
	    if(!$success) {
		print $logout_form->render;
	    }
	    if($success) {
		$self->{mode} = $mode;
		$self->{tid} = $tid;
		$self->{logout_form} = $logout_form;
		$self->do_main;
	    }
	}
    } elsif ($masterform->submitted && $masterform->validate) {
	my $user = $masterform->field('username');
	my $pass = $masterform->field('password');
	my $success;
	my $error;

	$success = $self->do_login($logout_form, $masterform);
	if($success) {
	    $success = $self->user_is_allowed($user);
	    if(!$success) {
		$error = "The user $user is not a member of the group required for access.";
	    }
	}
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
	    $self->do_main;
	} else {
	    $self->{rt} = undef;
	    $masterform->text($error);
	    $masterform->field(name => 'password',value => '',		   force => 1);
	    print $masterform->render;
	    $self->link_hook();
	}
    } else {
	$masterform->field(name => 'password',value => '',		   force => 1);
	print $masterform->render;
	print $self->displaymessage;
	$self->link_hook();
    }
}

sub transform {
    my $self = shift;
    my $value = shift;
    return $value;
}

sub displaymessage {
    return '';
}

sub link_hook() {
    return;
}

sub quicklink {
    my ($self, $name, $text, $mode, $tid) = @_;
    my $href = $ENV{"SCRIPT_NAME"};
    $href .= "?";
    $href .= "mode=" . $mode;
    if(defined($tid)) {
	$href .= "&tid=" . $tid;
    }
    return '<a href="' . $href . '">' . $text . "</a><br />";
}

sub quickform {
    my ($self, $name, $text, $mode, $tid) = @_;
    my @list = ('mode');
    if(defined($tid)) {
	push @list, 'tid';
    }
    my $ticket_form = CGI::MyFormBuilder->new(fields => [], method   => 'post', submit => $text, name => $name, keepextras => \@list);
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

sub current_cc {
    my ($self, $id) = @_;
    my $cc = $self->{rt}->show(type => 'ticket', id => $id)->{Cc};
    my $cc2 = $self->{rt}->show(type => 'ticket', id => $id)->{AdminCc};
    if(length($cc) > 0 && length($cc2) > 0) {
	$cc .= ", ";
    }
    $cc .= $cc2;
    my @list = split ', ', $cc;
    return @list;
}

sub cc {
    return ();
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
	if($self->handles_cc() == 1) {
	    $self->{rt}->edit (type => 'ticket', id => $self->{tid}, set => { AdminCc => [$self->cc()] });
	}
    } else {
	# FIXME when no has_login
	$self->{tid} = $self->{rt}->create(type => 'ticket', set => {priority => $self->priority(),
						     requestor => [$self->requestor],
                                                     AdminCc => [$self->cc()],
						     queue => $self->queuename,
						     subject => $subject}, text => $text)
    }
    $self->{subject} = $subject;
    return $self->{tid};
}

sub priority {
    return 0;
}

sub requestor {
    my $self = shift;
    return $self->get_email_for_user($self->{user});
}

sub handles_cc {
    return 0;
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
    return 1; # DEVEL
}

sub no_other {
    return 0;
}

sub index {
    my $self = shift;
    $self->render_top();
    print "<hr />";
    unless($self->no_other) {
    my $query = "Queue = '" . $self->queuename ."' AND (Status = 'open' OR Status = 'new' OR Status = 'stalled')";
    if($self->has_login) {
	$query = "Creator = '" . $self->{user} . "' AND " . $query;
    }
    my @ids = $self->{rt}->search(
	type => 'ticket',
	query => $query
	); 
    if(scalar(@ids) > 0) {
	print '<h4>Add to or change existing request:</h4>';
	my %idhash;
	my %dchash;
	for my $id (@ids) {
	    my $subj = $self->get_subject($id);
	    $idhash{$id} = $subj;
	    $dchash{$id} = $subj . "";
	    $dchash{$id} =~ tr/A-Z/a-z/;
	}
	my @sorted = sort { $dchash{$a} cmp $dchash{$b} } keys %idhash;
	foreach(@sorted) {
	    my $id = $_;
	    my $subj = $idhash{$id};
	    print $self->quicklink('ticket_$id','#' . $id . ": " . $subj, 'edit', $id);
	}
	my $o_ticket_form = CGI::MyFormBuilder->new(fields => ['tid'], method   => 'post', submit => 'Edit ticket', name => 'arbitrary_ticket', keepextras => ['mode'], labels => {'tid' => 'Other ticket'});
	$o_ticket_form->cgi_param('mode', 'edit'); # FIXME: other end needs ot verify that this is in correct queue
	unless($self->hide_other_ticket_f) {
	    print $o_ticket_form->render;
	}
	print "<hr />";
    }
    }
    print '<h4>New request:</h4>';    
    foreach($self->ordered_types) {
	print $self->quickform('new_$_',$self->button_names->{$_}, 'new_' . $_)->render;
    }
}

sub parse_new_action {
    return;
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
    } else {
	$self->parse_new_action;
    }

    # happens before form render or back button, THAT WAY THAT DOESN'T SHOW UP

    $self->{logout_form}->title($self->{logout_form}->title . ": " . ($self->{mode} eq "edit" ? "edit" : "new") . " " . $self->{type} . " request");
    $self->render_top();
    print "<hr />";
    my $form = $self->{form};

    my $success = $self->pre_validate();
    if($form->submitted) {
	$success = $form->validate && $success;
    } else {
	$success = 0;
    }
    if($success) {
	$self->save;
#	$self->{mode} = "index";
#	return $self->do_main;
    } else {
	$self->render;
    }
    print "<hr />";
    print $self->quickform('back', 'Back to Main Page', 'index')->render;
}

sub pre_validate {
    my $self = shift;
    my $form = $self->{form};
    if($form->submitted) {
	if($self->has_date) {
	    my $val = str2time($form->field('date'));
	    if($val) {
		$form->field(name => 'date', value => time2str("%Y/%m/%d", $val), force => 1, validate => undef);	    
	    }
	} 
	if($self->has_end_date) {
	    my $val = str2time($form->field('end_date'));
	    if($val) {
		$form->field(name => 'end_date', value => time2str("%Y/%m/%d", $val), force => 1, validate => undef);
	    }
	}
    }
    return $self->pre_validate_hook();
}

sub pre_validate_hook {
    return 1;
}

sub render {
    my $self = shift;
    my $form = $self->{form};
    $form->{javascript} = 0;
    print $self->transform($form->render);

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

    $self->post_render_hook();
}

sub post_render_hook {
    return;
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
    if(defined($ferror) && $ferror =~ /Ticket (\d+) created/) {
	$self->{tid} = $newticket = $1;
    }
    if($newticket == 0) {
	print "<span style='color: red'><b>There was an error while trying to save: " . $ferror . "</b></span>";
    } else {
	print '<table border="1">';
	    print "<tr><th colspan=2>Your submission has been received and saved in ticket #" . $newticket . "</th></tr>";
	    if(defined($ferror)) {
		print "<tr><td colspan=2>There was an error which did NOT prevent the ticket from being created, but please report this issue to a Technocrat regardless: " . $ferror . "</td></tr>";
	    }
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
