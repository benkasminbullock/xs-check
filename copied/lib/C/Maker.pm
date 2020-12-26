# Copied from /home/ben/projects/c-maker/lib/C/Maker.pm
package C::Maker;
use warnings;
use strict;
require Exporter;
our @ISA = qw(Exporter);
our @EXPORT_OK = qw/create_header make_c_file/;
our %EXPORT_TAGS = (
    all => \@EXPORT_OK,
);

our $VERSION = '0.01';
use C::Utility ':all';
use Template;
use File::Slurper qw/read_text write_text/;
use Table::Readable qw/read_table/;
use Carp;
use Cwd;
use C::Tokenize ':all';

# The directory where the templates are found.

my $template_dir = __FILE__;
$template_dir =~ s!\.pm!/templates!;

sub make_c_file
{
    my ($orig_name_space, $dir) = @_;
    my $name_space = $orig_name_space;
    # Allow hyphens in the namespace, and convert them to underscores
    # in the C file.
    $name_space =~ s/-/_/g;
    if (! valid_c_variable ($name_space)) {
	if ($name_space =~ /\.c(\.in)?/) {
	    croak "Use the name without the '.c' or '.c.in' suffixes";
	}
	else {
	    croak "'$name_space' is not a valid C variable name";
	}
    }
    my $uc_ns = uc $name_space;
    if (! $dir) {
        $dir = getcwd ();
    }
    my $source = "$dir/$orig_name_space.c.in";
    my $c = read_text ($source);

    # Add default statuses (malloc failure, success).

    my @table = default_statuses ();

    # Defines for used libraries.

    my $udefs = '';

    while ($c =~ s/\bUSE\s*\(([^)]+)\)\s*;?/#include "$1.h"/) {
	my $name = $1;
	my $ucname = uc ($name);
	my $error = $name . '_error';
	push @table, {
	    status => $error,
	    description => "$name library error",
	};
	$udefs .= "#define ${ucname}_USER_ERROR ${name_space}_status_$error\n";
    }
    # Add statuses if found in the file.

    if ($c =~ m!/\*\s*statuses:\s*(.*?)\*/!sm) {
        my $statuses = $1;
        push @table, read_table ($statuses, scalar => 1);
    }
    else {
#	warn "'statuses:' key not found in $source";
    }

    # Add descriptions for statuses which lack them.

    add_default_descriptions (\@table);

    # Tidy the descriptions
    for (@table) {
	my $d = $_->{description};
	$d =~ s/\s/ /g;
	$d =~ s/"/\\"/g;
	$_->{description} = $d;
#	print $_->{status}, " ", $_->{description}, "\n";
    }

    # This contains the variables which are passed to the Template
    # Toolkit.

    my %vars;

    # Set up the things to include in the output file.

    $vars{name_space} = $name_space;
    $vars{uc_ns} = $uc_ns;
    $vars{orig_name_space} = $orig_name_space;
    $vars{c} = $c;
    $vars{statuses} = \@table;
    $vars{original_file} = $source;
    $vars{udefs} = $udefs;

    # The name of the output C file.

    my $output = "$dir/$orig_name_space.c";

    # Get a Template Toolkit instance using the include path
    # "$template_dir" which is defined when this module loads.

    my $tt = Template->new (
        ABSOLUTE => 1,
        INCLUDE_PATH => [
            $template_dir,
        ],
        ENCODING => 'UTF-8',
    );

    # Write the C file using the template variables.

    my $out;

    my $headerx = make_header (
        name_space => $name_space, 
        orig_name_space => $orig_name_space,
        dir => $dir,
        c => $c,
        source => $source,
        tt => $tt,
        vars => \%vars,
    );

    $vars{header} = $headerx;

    $tt->process ('c-file', \%vars, \$out, {binmode => 'utf8'})
        or die $tt->error ();

    my $func_re = qr!FUNC\s*\((.*?)\)!;

    $out =~ s/^((?:STATIC|static)(\s+))$func_re/static$2${name_space}_status_t ${name_space}_$3/gsm;
    $out =~ s/^$func_re/${name_space}_status_t ${name_space}_$1/gsm;
    $out =~ s/STATIC/static/g;

    write_text ($output, $out);

    # Make the header file using the same variables.

}

# Make the header file component of the C file.

sub make_header
{
    my (%inputs) = @_;
    my $name_space = $inputs{name_space};
    my $tt = $inputs{tt};
    my $output = '';
    my $vars = $inputs{vars};
    my $call = uc $name_space;
    $vars->{call} = $call;
    $vars->{name_space} = $name_space;
    $tt->process ('h-file', $vars, \$output, {binmode => 'utf8'})
        or die $tt->error ();
    if ($inputs{header}) {
        $output .= $inputs{header} . "\n";
    }
    return $output;
}

# This returns a hash reference containing the two statuses which are
# always present in every output file.

sub default_statuses
{
    return ({
        status => 'ok',
        description => 'normal operation',
    }, {
        status => 'memory_failure',
        description => 'out of memory',
    }, {
	status => 'null_pointer',
	description => 'a pointer contained a zero value',
    },);
}

# This adds default descriptions for statuses which don't have any.

sub add_default_descriptions
{
    my ($table_ref) = @_;
    for my $status (@$table_ref) {
        if (! $status->{description}) {
            my $default_description = $status->{status};
            # Substitute spaces for underscores.
            $default_description =~ s/_/ /g;
            $status->{description} = $default_description;
        }
    }
}

1;
