package Requestor::Supplies;

use strict;
use warnings;

use Requestor::Base;

use base 'Requestor::Base';

sub hide_other_ticket_f {
    return 1;
}

sub parse_supply {
    my $istr = shift;
    my @list = split /\s/, $istr;
    my $in = 0;
    my $t;
    my @astr;
    my @quant;
    my $by = "";
    while($t = shift @list) {
        if($t =~ /^\(/) {
	    if($t =~ /\)$/) {
		$t =~ s/\)$//g;
	    } else {
		$in = 1;
	    }
            $t =~ s/^\(//g;
            push @quant, $t;
        }elsif($t =~ /\)$/ and $in == 1) {
            $t =~ s/\)$//g;
            push @quant, $t;
            $in = 0;
        }elsif($in == 0 and $t eq "by") {
            my $d = shift @list;
            $by = $d;
        } else {
            if($in) {
                push @quant, $t;
            } else {
                push @astr, $t;
            }
        }
    }
    my $str = join ' ', @astr;
    my $destination = "";
    if($str =~ /^([^:]+): (.+)$/) {
	$destination = $1;
	$str = $2;
    }
    my $quantity = join ' ', @quant;
    return ($str, $quantity, $by, $destination);
}

sub format_supply {
    my ($str, $quant, $by, $destination) = @_;
    if($destination ne "") {
	$destination = $destination . ": ";
    }
    if($quant ne "") {
        $quant = " (" . $quant . ")";
    }
    if($by ne "") {
        $by = " by " . $by;
    }
    return $destination . $str . $quant . $by;
}

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

# save, setup, parse

sub setup {
    my $self = shift;
    my $form = $self->quickform($self->{fname}, 'Submit Supply Request', $self->{mode}, $self->{tid});
    $self->{form} = $form;
    my $type = $self->{type};

    my $dateformat = '/^[0-9]{4}\/?(0?[1-9]|1[0-2])\/?(0?[1-9]|[1-2][0-9]|3[0-1])$/';

    $form->field(name => 'requestor', label => 'Requestor Name', type => 'text', required => 1);
    $form->field(name => 'requestor_email', label => 'Requestor Email address', type => 'text', required => 1);
    $form->field(name => 'name', label => 'Supply Name', type => 'text', required => 1);
    $form->field(name => 'destination', label => 'Where would you like this item delivered?<br />(example: Warehouse, Supply Cabinets)', type => 'text');
    $form->field(name => 'quantity', label => 'Quantity', type => 'text', required => 0);
    $form->field(name => 'date', label => 'Needed By Date (YYYY/MM/DD)', type => 'text', required => 0, validate => $dateformat);
    $form->field(name => 'date_chooser', type => 'button', label => '', value => 'Date Chooser');
    $form->field(name => 'notes', label => 'Notes<br/>(Please include brand or description if possible.)', type => 'textarea',  cols => '80', rows => '10');

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
	my @parts = @{[parse_supply($subject)]};
	$form->field(name => 'name', value => $parts[0]);
	$form->field(name => 'date', value => $parts[2]);
	$form->field(name => 'quantity', value => $parts[1]);
	$form->field(name => 'destination', value => $parts[3]);
    }
}

sub requestor {
    my $self = shift;
    my $form = $self->{form};
    my $name = $form->field('requestor');
    my $email = $form->field('requestor_email');
    my $req = $name . " <" . $email . ">";
    return $req;
}

sub save {
    my $self = shift;
    my $form = $self->{form};
    my $text = $form->field('notes');
    my $name = $form->field('name');
    my $date = $form->field('date');
    my $destination = $form->field('destination');
    my $quantity = $form->field('quantity');
    my $subject = "";
    $subject = format_supply($name, $quantity, $date, $destination);
    $self->{subject} = $subject;
#    if(defined($self->{tid})) {
	$text = "Supply request modified by: " . $self->requestor() . "\n\n" . $text;
#    }
    $self->do_save($subject, $text);
}

1;
