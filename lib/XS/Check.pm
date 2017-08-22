package XS::Check;
use warnings;
use strict;
use Carp;
use utf8;
our $VERSION = '0.05';
use C::Tokenize ':all';
use Text::LineNumber;
use File::Slurper 'read_text';
use Carp qw/croak carp cluck confess/;

sub new
{
    my ($class, %options) = @_;
    return bless {};
}

sub get_line_number
{
    my ($o) = @_;
    my $pos = pos ($o->{xs});
    if (! defined ($pos)) {
	confess "Bad pos for XS text";
	return "unknown";
    }
    return $o->{tln}->off2lnr ($pos);
}

# Report an error $message in $var

sub report
{
    my ($o, $message) = @_;
    my $file = $o->get_file ();
    my $line = $o->get_line_number ();
    confess "No message" unless $message;
    warn "$file$line: $message.\n";
}

# Match a call to SvPV

my $svpv_re = qr/
		    ((?:$word_re(?:->|\.))*$word_re)
		    \s*=[^;]*
		    SvPV
		    \s*\(\s*
		    ($word_re)
		    \s*,\s*
		    ($word_re)
		    \s*\)
		/x;

# Look for problems with calls to SvPV.

sub check_svpv
{
    my ($o) = @_;
    while ($o->{xs} =~ /($svpv_re)/g) {
	my $match = $1;
	my $lvar = $2;
	my $arg2 = $4;
	my $lvar_type = $o->get_type ($lvar);
	my $arg2_type = $o->get_type ($arg2);
	#print "<$match> $lvar_type $arg2_type\n";
	if ($lvar_type && $lvar_type !~ /\bconst\b/) {
	    $o->report ("$lvar not a constant type");
	}
	if ($arg2_type && $arg2_type !~ /\bSTRLEN\b/) {
	    $o->report ("$arg2 is not a STRLEN variable ($arg2_type)");
	}
    }
}

# Look for malloc/calloc/realloc/free and suggest replacing them.

sub check_malloc
{
    my ($o) = @_;
    while ($o->{xs} =~ /\b((?:m|c|re)alloc|free)\b/g) {
	$o->report ("Change $1 to Newx/Newz/Safefree");
    }
}

# Regular expression to match a C declaration.

my $declare_re = qr/
		       (
			   (
			       (?:
				   (?:$reserved_re|$word_re)
				   (?:\b|\s+)
			       |
				   \*\s*
			       )+
			   )
			   (
			       $word_re
			   )
		       )
		       # Match initial value.
		       \s*(?:=[^;]+)?;
		   /x;

# Read the declarations.

sub read_declarations
{
    my ($o) = @_;
    while ($o->{xs} =~ /$declare_re/g) {
	my $type = $2;
	my $var = $3;
	#print "type = $type for $var\n";
	if ($o->{vars}{$type}) {
	    warn "duplicate variable $var of type $type\n";
	}
	$o->{vars}{$var} = $type;
    }
}

# Get the type of variable $var.

sub get_type
{
    my ($o, $var) = @_;
    # We currently do not have a way to store and retrieve types of
    # structure members
    if ($var =~ /->|\./) {
	$o->report ("Cannot get type of $var, please check manually");
	return undef;
    }
    my $type = $o->{vars}{$var};
    if (! $type) {
	$o->report ("(BUG) No type for $var");
    }
    return $type;
}

sub line_numbers
{
    my ($o) = @_;
    my $tln = Text::LineNumber->new ($o->{xs});
    $o->{tln} = $tln;
}

sub get_file
{
    my ($o) = @_;
    if (! $o->{file}) {
	return '';
    }
    return "$o->{file}:";
}

# Clear up old variables

sub cleanup
{
    my ($o) = @_;
    delete $o->{vars};
}

sub strip_comments
{
    my ($o) = @_;
    my $xs = $o->{xs};
    while ($xs =~ /($trad_comment_re)/) {
	my $comment = $1;
	my $subs = '';
	while ($comment =~ /([\n\r])/g) {
	    $subs .= $1;
	}
	$xs =~ s/\Q$comment\E/$subs/;
    }
    # Remove // comments completely.
    $xs =~ s/$cxx_comment_re/\n/g;
    $o->{xs} = $xs;
}

# Check the XS.

sub check
{
    my ($o, $xs) = @_;
    $o->{xs} = $xs;
    $o->strip_comments ();
    $o->line_numbers ();
    $o->read_declarations ();
    $o->check_svpv ();
    $o->check_malloc ();
    $o->{xs} = undef;
    $o->cleanup ();
}

sub check_file
{
    my ($o, $file) = @_;
    $o->{file} = $file;
    my $xs = read_text ($file);
    #print "$xs\n";
    check ($o, $xs);
    $o->{file} = undef;
}

1;
