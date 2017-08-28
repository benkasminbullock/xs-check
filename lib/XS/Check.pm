package XS::Check;
use warnings;
use strict;
use Carp;
use utf8;
our $VERSION = '0.08';
use C::Tokenize '0.14', ':all';
use Text::LineNumber;
use File::Slurper 'read_text';
use Carp qw/croak carp cluck confess/;

sub new
{
    my ($class, %options) = @_;
    my $o = bless {};
    if (my $r = $options{reporter}) {
	if (ref $r ne 'CODE') {
	    carp "reporter should be a code reference";
	}
	else {
	    $o->{reporter} = $r;
	}
    }
    return $o;
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
    if (my $r = $o->{reporter}) {
	&$r (file => $file, line => $line, message => $message);
    }
    else {
	warn "$file$line: $message.\n";
    }
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

my %equiv = (
    malloc => 'Newx/Newxc',
    calloc => 'Newxz',
    free => 'Safefree',
    realloc => 'Renew',
);

# Look for malloc/calloc/realloc/free and suggest replacing them.

sub check_malloc
{
    my ($o) = @_;
    while ($o->{xs} =~ /\b((?:m|c|re)alloc|free)\b/g) {
	# Bad function
	my $badfun = $1;
	my $equiv = $equiv{$badfun};
	if (! $equiv) {
	    $o->report ("(BUG) No equiv for $badfun");
	}
	else {
	    $o->report ("Change $badfun to $equiv");
	}
    }
}

# Look for a Perl_ prefix before functions.

sub check_perl_prefix
{
    my ($o) = @_;
    while ($o->{xs} =~ /\b(Perl_$word_re)\b/g) {
	$o->report ("Remove the 'Perl_' prefix from $1");
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

sub set_file
{
    my ($o, $file) = @_;
    if (! $file) {
	$file = undef;
    }
    $o->{file} = $file;
}

# Clear up old variables, inputs, etc.

sub cleanup
{
    my ($o) = @_;
    for (qw/vars xs file/) {
	delete $o->{$_};
    }
}

my $void_re = qr/
		    $word_re\s*
		    \(\s*void\s*\)\s*
		    (?=
			# CODE:, PREINIT:, etc.
			[A-Z]+:
#		    |
			# Normal C function start
#			\{
		    )
/xsm;

sub check_void_arg
{
    my ($o) = @_;
    while ($o->{xs} =~ /$void_re/g) {
	$o->report ("Don't use (void) in function arguments");
    }
}

# Check the XS.

sub check
{
    my ($o, $xs) = @_;
    $o->{xs} = $xs;
    $o->{xs} = strip_comments ($o->{xs});
    $o->line_numbers ();
    $o->read_declarations ();
    $o->check_svpv ();
    $o->check_malloc ();
    $o->check_perl_prefix ();
    $o->check_void_arg ();
    # Final line
    $o->cleanup ();
}

sub check_file
{
    my ($o, $file) = @_;
    $o->set_file ($file);
    my $xs = read_text ($file);
    $o->check ($xs);
}

1;
