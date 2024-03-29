package Requestor::Schedule;

use strict;
use warnings;

use Requestor::Base;

use RT::Client::REST::Group;
use RT::Client::REST::Ticket;

use CGI qw(escapeHTML);

use base 'Requestor::Base';

use CGI::FormBuilder::Util;

use DBI;
use DBD::Pg;

my $siteconfig = "/etc/request-tracker3.8/RT_SiteConfig.pm";

my $management_group = 1292; # FGCollective
my $all_staff_group = 94421; # FGPaidworkers
my $access_group = 131528; # FGSchedule, now.

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
    $button_names{hours} = 'Request hours logging or removal from a day you did not work';
    $button_names{schedule} = 'Request other schedule changes';
    $self->{buttons} = \%button_names;
}

sub displaymessage {
    return 'Note: viewing the staff schedule requires logging in now.';
}

sub title {
    return 'Free Geek Staff Schedule (login same as todo.freegeek.org)';
}

sub showfile {
    my $self = shift;
    $self->render_top();
    print '<hr />';
    if($self->{session}->param('IS_LOGGED_IN')) {
	open my $F, '<', $self->{mode} eq 'sched' ? '/home/staffsched/web/index.html' : '/home/staffsched/web/meetings.html';
	binmode $F, ':utf8';
	my @a = <$F>;
	print join '', @a;
    }
    print '<hr />';
    print $self->quickform('back', 'Back to Main Page', 'index')->render;
}

sub do_main {
    my $self = shift;
    if($self->{mode} eq "index") {
	$self->index;
    } elsif($self->{mode} eq "sched" or $self->{mode} eq 'meetings') {
	$self->showfile;
    } else {
	$self->non_index_action;
    }
}

sub link_hook {
    my $self = shift;
    if($self->{session}->param('IS_LOGGED_IN')) {
	if($self->{mode} ne "sched") {
	    print $self->quickform('sched', 'View Staff Schedule', 'sched')->render;
	}
	if($self->{mode} ne "meetings") {
	    print $self->quickform('meetings', 'View Perpetual Meeting Calendar', 'meetings')->render;
	}
    }
    return;
}

sub post_render_hook {
    print "<script>vis_value = false; function toggle_visible(){vis_value = !vis_value; var a = document.getElementsByClassName('hide'); for(var i = 0; i < a.length; i++) { a[i].parentNode.parentNode.hidden = vis_value; }} toggle_visible();</script>\n";
    print "<a href=\"#\" onClick=\"toggle_visible();\">Click to Cc other workers on this request.</a>\n";
    return;
}

sub handles_cc {
    return 1;
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
    my $form = $self->quickform($self->{fname}, 'Submit Schedule Request', $self->{mode}, $self->{tid});
    $self->{form} = $form;
    my $type = $self->{type};

    my $dateformat = '/^[0-9]{4}\/?(0?[1-9]|1[0-2])\/?(0?[1-9]|[1-2][0-9]|3[0-1])$/';

    $form->field(name => 'name', label => 'Worker Name', type => 'text', required => 1);
    $form->field(name => 'notes', label => 'Specify the requested changes', type => 'textarea',  cols => '80', rows => '10', required => $self->{new_only});
    unless($type eq 'other') {
	$form->field(name => 'date', label => 'Requested Date (YYYY/MM/DD)', type => 'text', required => 1, validate => $dateformat);
	$form->field(name => 'date_chooser', type => 'button', label => '', value => 'Date Chooser');
    }
    if($type eq 'meeting') {
	$form->field(name => 'time', label => 'Meeting Time', type => 'text', required => 1);
    }
    if($type eq "schedule") {
	$form->field(name => 'date', label => 'Requested Start Date (YYYY/MM/DD)');
	$form->field(name => 'end_date', label => 'End Date (YYYY/MM/DD, leave empty for ongoing)', type => 'text', validate => $dateformat);
    } elsif($type eq "meeting") {
	$form->field(name => 'name', label => 'Meeting Name');
	$form->field(name => 'notes', label => 'Specify list of attendees and any other details');
    } elsif($type eq "hours") {
	$form->field(name => 'date', label => 'Date (YYYY/MM/DD)');
	$form->field(name => 'notes', label => 'Specify how many hours you worked in each place on each day, or the requested changes if you did not work');
    } elsif($type eq "vacation") {
	$form->field(name => 'end_date', label => 'End Date (YYYY/MM/DD, leave empty if only one day)', type => 'text', validate => $dateformat);
	$form->field(name => 'notes', label => 'Specify shifts needing coverage and any tentative plans');
    } else {
	$form->field(name => 'name', label => 'Request Name');
    }

    if($type eq 'schedule' || $type eq 'vacation') {
	$form->field(name => 'end_date_chooser', type => 'button', label => '', value => 'End Date Chooser');
    }
}

sub list_potential_cc {
    my $self = shift;
    my @cc = ();
    if(!$self->{new_only}) {
	@cc = $self->current_cc($self->{tid});
    }
    my @workers = $self->list_staff();
    my $user = RT::Client::REST::User->new(
					   rt  => $self->{rt},
					   id  => $self->{user},
					   )->retrieve;
    my $value = $user->real_name . ' <' . $user->email_address . '>';
    @workers = grep !/$value/, @workers;
    my @ident_workers = map {_ident($_)} @workers;
    foreach my $w(@cc) {
	my $ident = _ident($w);
	my @found = grep /$ident/, @ident_workers;
	if(scalar(@found) == 0) {
	    unshift @workers, $w;
	    unshift @ident_workers, $ident;
	}
    }
    return @workers;
}

sub cc {
    my $self = shift;
    my $form = $self->{form};
    my @workers = $self->list_potential_cc();
    my @list = ();
    foreach my $w(@workers) {
	my $ident = _ident($w);
	my $value = $form->field($ident) || "";
	if($value eq "Add to Cc") {
	    push @list, (@{[$w =~ /<(.+)>/]}[0] || $w);
	}
	
    }
    return @list;
}

sub _ident {
    my $w = shift;
    my $ident = @{[$w =~ /<(.+)>/]}[0];
    if(!defined($ident)) {
	$ident = $w;
    }
    $ident =~ s/[\.@+]/_/g;
    return $ident;
}

sub pre_validate_hook {
    my $self = shift;
    return 1 if($self->{type} eq "hours");
    my $base = "<table><td><th colspan=\"2\">This schedule request might affect floor shift coverage.</th></td><tr><th>All Workers:</th><td>You must copy your supervisor and any other supervisors of affected areas</td></tr><tr><th>Management:</th><td>Alert Directors</td></tr><tr><th>Directors:</th><td>Alert Schedulers</td></tr></table>\n";
    if($self->{form}->submitted) {
	my @results = query_rt_group($management_group, "realname || ' <' || emailaddress || '>'");
	foreach my $w(@results) {
	    my $ident = _ident($w);
	    my $value = $self->{form}->field($ident) || "";
	    if($value eq "Add to Cc") {
		$self->{form}->text($base);
		return 1;
	    }
	}
	$self->{form}->text("<span style=\"color: #cc0000;\"><b>Error: You must Cc at least one management member.</b></span><br/>\n" . $base . $self->validate_end_hook);
	return 0;
    } else {
	$self->{form}->text($base . $self->validate_end_hook);
	return 1;
    }
}

sub user_is_allowed {
    my $self = shift;
    my $user = shift;
    my @results = query_rt_group($access_group, "users.id");
    my $u = RT::Client::REST::User->new(
					   rt  => $self->{rt},
					   id  => $user,
					)->retrieve;
    my $uid = $u->id;
    return(grep /^$uid$/, @results);
}

sub query_rt_group {
    my ($group, $column) = @_;
# parse the configuration file in an ugly way

    my @lines = `cat $siteconfig | grep -E "^Set.*Database(Name|User|Password)" | sort | cut -d "'" -f 2`;
    my ($name, $password, $user);
    if(scalar(@lines) == 3) {
	($name, $password, $user) = @lines;
    } elsif(scalar(@lines) == 2) {
	($name, $password, $user) = ('rtdb', $lines[0], $lines[1]);
    } else {
	die "Could not process configuration."
	}
    chomp($name, $password, $user);

# query the database for the list

    my $dbh = DBI->connect("dbi:Pg:dbname=$name" . ($ENV{FG_RT_HOST} ? (";host=" . $ENV{FG_RT_HOST}) : ""), $user, $password, {AutoCommit => 0}) or die "Couldn't connect to database: " . DBI->errstr;
    my $sth = $dbh->prepare("SELECT DISTINCT " . $column . " FROM users INNER JOIN cachedgroupmembers ON cachedgroupmembers.memberid = users.id AND cachedgroupmembers.groupid = " . $group . " INNER JOIN principals ON principals.disabled = 0 AND principals.principaltype LIKE 'User' AND principals.objectid = users.id WHERE emailaddress != '' ORDER BY 1;");
    $sth->execute() or die "Couldn't execute statement: " . $sth->errstr;
    my @results = ();
    while (my @data = $sth->fetchrow_array()) {
	push @results, $data[0];
    }
    $dbh->disconnect();

    return @results;
}

sub list_staff {
    my @results = query_rt_group($all_staff_group, "realname || ' <' || emailaddress || '>'");

# sort the list to return

    sub cleanup {
      my $in = uc(shift);
      $in =~ s/^"//;
      return $in;
    }
    @results = sort {cleanup($a) cmp cleanup($b)} @results;

    return @results;
}

sub validate_end_hook {
    my $self = shift;
    my $str = "";
    if(defined($self->{tid})) {
	 my $ticket = RT::Client::REST::Ticket->new(
						    rt  => $self->{rt},
						    id  => $self->{tid},
						    )->retrieve;
	my $transactions = $ticket->transactions;
	my $iterator = $transactions->get_iterator;
	$str .= "<h2>Your past comments:</h2>";
	while (my $tr = &$iterator) {
	    if($tr->creator eq $self->{user} && $tr->content ne "This transaction appears to have no content") {
		my $c = $tr->content;
		$c =~ s/\n/<br \/>/g;
		$str .= "<fieldset><h3>On " . $tr->created . ":</h3>" . $c . "</fieldset>";
	    }
	}
    }
    return $str;
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

sub parse_new_action {
    # this is done later on if editing, to include extra people
    my $self = shift;
    my $form = $self->{form};
    my @workers = $self->list_potential_cc();
    my @management = query_rt_group($management_group, "realname || ' <' || emailaddress || '>'");
    @management = map {_ident($_)} @management;
    foreach my $w(@workers) {
	my $ident = _ident($w);
	my $css_class = 'hide';
	my $label = $w;
	if(grep /$ident/, @management) {
	    $css_class = '';
	    $label =~ s/ </ (management) </g;
	}
	$form->field(name => $ident, label => escapeHTML($label), type => 'checkbox', options => ['Add to Cc'], class => $css_class);
    }
}

sub parse {
    my $self = shift;
    my $form = $self->{form};
    my $subject = $self->{subject};
    my $char = $self->{char};

    # needed even if submitted, defines form fields
    if(!$self->{new_only}) {
	$self->parse_new_action();
    }

    unless($form->submitted) {
	my @cc = $self->current_cc($self->{tid});
	foreach my $w(@cc) {
	    my $ident = _ident($w);
	    $form->field(name => $ident, value => 'Add to Cc');
	}

	if($char eq "o") {
	    my $name = $subject;
	    $form->field(name => 'name', value => $name);
	} else {
	    my @parts = @{[$subject =~ /^(.)\.\s+([^- ]+)(?:-([^ ]+))?(?:\s+at\s+([^,]+))?,\s+(.+)/]};
	    my $date = $parts[1];
	    $form->field(name => 'date', value => $date);
	    if($char eq "v" or $char eq "b") {
		my $end_date = $parts[2];
		$form->field(name => 'end_date', value => $end_date);
	    } elsif($char eq "m") {
		my $time = $parts[3];
		$form->field(name => 'time', value => $time);
	    }
	    my $name = $parts[4];
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
    } elsif($type eq "meeting") {
	my $time = $form->field('time');
	$subject = $char . ". " . $date . " at " . $time . ", " . $name; # {CHAR}. {START_DATE}, {NAME}
    } else {
	$subject = $char . ". " . $date . ", " . $name; # {CHAR}. {START_DATE}, {NAME}
    }
    $self->{subject} = $subject;
    $self->do_save($subject, $text);
}

1;
