package XS::Check;
use warnings;
use strict;
use Carp;
use utf8;
require Exporter;
# our @ISA = qw(Exporter);
# our @EXPORT_OK = qw//;
# our %EXPORT_TAGS = (
#     all => \@EXPORT_OK,
# );
our $VERSION = '0.01';
use C::Tokenize ':all';
use Text::LineNumber;
use File::Slurper 'read_text';

sub new
{
    my ($class, %options) = @_;
    return bless {};
}

# Report an error $message in $var

sub report
{
    my ($o, $var, $message) = @_;
    my $file = $o->get_file ();
    my $line = $o->get_line_number ($var);
    warn "$file$line: $message";
}

# Match a call to SvPV

my $svpv_re = qr/
		    ($word_re)
		    \s*=\s*
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
    my ($o, $xs) = @_;
    while ($xs =~ /($svpv_re)/g) {
	my $match = $1;
	my $lvar = $2;
	my $arg2 = $4;
	my $lvar_type = $o->get_type ($lvar);
	my $arg2_type = $o->get_type ($arg2);
	if ($lvar_type && $lvar_type !~ /const\s+char\s+\*/) {
	    $o->report ($xs, "$lvar not const char *");
	}
	if ($arg2_type && $arg2_type !~ /STRLEN/) {
	    $o->report ($xs, "$lvar not const char *");
	}
    }
}

# Look for malloc/calloc/realloc/free and suggest replacing them.

sub check_malloc
{
my ($o, $xs) = @_;
while ($xs =~ /((?:m|c|re)alloc|free)/g) {
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
		       \s*(?:=[^;]+)?;
		   /x;

# Read the declarations.

sub read_declarations
{
    my ($o, $xs) = @_;
    while ($xs =~ /$declare_re/g) {
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
    my $type = $o->{vars}{$var};
    if (! $type) {
	warn "No type for $var";
    }
    return $type;
}

sub line_numbers
{
    my ($o, $xs) = @_;
    my $tln = Text::LineNumber->new ($xs);
    $o->{tln} = $tln;
}

sub get_line_number
{
    my ($o, $xs) = @_;
    my $pos = pos ($xs);
    if (! defined ($pos)) {
	warn "Bad pos for XS text";
	return "unknown";
    }
    return $o->{tln}->off2lnr ($pos);
}

sub get_file
{
    my ($o) = @_;
    if (! $o->{file}) {
	return '';
    }
    return "$o->{file}:";
}

# Check the XS.

sub check
{
    my ($o, $xs) = @_;
    $o->line_numbers ($xs);
    $o->read_declarations ($xs);
    $o->check_svpv ($xs);
    $o->check_malloc ($xs);
}

sub check_file
{
    my ($o, $file) = @_;
    $o->{file} = $file;
    my $xs = read_file ($file);
    check ($o, $xs);
    $o->{file} = undef;
}

1;
