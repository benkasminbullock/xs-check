# Copied from /home/ben/projects/perl-build/lib/Perl/Build/Pod.pm
package Perl::Build::Pod;
use Perl::Build qw/get_info get_commit/;
use parent Exporter;
our @EXPORT_OK = qw/
		       make_pod
		       extract_vars
		       get_dep_section
		       make_examples
		       pbtmpl
		       pod_checker
		       pod_encoding_ok
		       pod_link_checker
		       pod_no_cut
		       xtidy
		       pod_exports
		   /;
our %EXPORT_TAGS = (all => \@EXPORT_OK);
use warnings;
use strict;
use utf8;
use FindBin '$Bin';
use Carp;
use Pod::Checker;
use File::Slurper qw/read_text read_lines/;
use JSON::Create;
use Deploy qw/do_system older/;
use Pod::Select;
use Test::Pod;

=head1 NAME

Pearl::Build::Pod - pod support for Pearl::Build

=head1 FUNCTIONS

=head2 pbtmpl

    my $template_dir = pbtmpl ();

Returns the directory where templates may be found.

=cut

sub pbtmpl
{
    return '/home/ben/projects/perl-build/lib/Perl/Build/templates';
}

=head2 xtidy

   my $tidy = xtidy ($text);

This removes some obvious boilerplate from the examples, to shorten
the documentation, and indents it to show POD that it is code. It's
basically a filter for the template toolkit.

=cut

sub xtidy
{
    my ($text) = @_;

    # Remove shebang.

    $text =~ s/^#!.*$//m;

    # Remove sobvious.

    $text =~ s/use\s+(strict|warnings);\s+//g;
    $text =~ s/^\s*binmode\s+STDOUT.*?utf8.*\n//gm;
#    $text =~ s/use\s+JSON::Parse.*?;\s+//;

    # Replace tabs with spaces.

    $text =~ s/ {0,7}\t/        /g;

    # Add indentation.

    $text =~ s/^(.*)/    $1/gm;

    return $text;
}

=head2 pod_encoding_ok

    ok (pod_encoding_ok ($file));

Check that the pod doesn't contain broken encodings.

=cut

sub pod_encoding_ok
{
    my ($file) = @_;
    my $pod = read_text ($file);
    if ($pod =~ /^=encoding\s+(?:(?i)utf)-?8/i) {
	return 1;
    }
    # Check there is no UTF-8 in the file using my module (hackaround).
    my $jc = JSON::Create->new ();
    $jc->fatal_errors (1);
    eval {
	$jc->run ($pod);
    };
    if ($@) {
	return 0;
    }
    return 1;
}

=head2 pod_no_cut

    ok (pod_no_cut ($file));

Check there is no "=cut" in a .pod file.

=cut

sub pod_no_cut
{
    my ($file) = @_;
    my $pod = read_text ($file);
    if ($pod =~ /^=cut/m) {
	return 0;
    }
    return 1;
}

=head2 pod_checker

    my $lines = pod_checker ($file);

Return the lines of Pod::Checker, with some things removed.

=cut

sub pod_checker
{
    my ($filepath) = @_;
    my @oklines;

    my $text = read_text ($filepath);
    if ($text !~ /^=/sm) {
	push @oklines, "No pod in $filepath";
    }
    my %options;
    my $checker = Pod::Checker->new (%options);

    open my $out, ">", \my $output or die $!;
    $checker->parse_from_file ($filepath, $out);
    if (! $output) {
	return \@oklines;
    }
    my @lines = split /\n/, $output;
    my $errors = 0;
    for my $line (@lines) {
	$line =~ s/\*{3} //;
	$line =~ s/^(.*) at line ([0-9]+) in file (.*)$/$3:$2: $1/;
	$line =~ s/WARNING/warning/g;
	$line =~ s/ERROR/error/g;
	if ($line =~ /line containing nothing but whitespace/) {
	    next;
	}
	if ($line =~ /^\s*$/) {
	    next;
	}
	push @oklines, $line;
	print "# $line\n";
	$errors++;
    }
    return \@oklines;
}

=head2 pod_link_checker

    my $errors = pod_link_checker ($pod);

Search the pod for errors where L<function> should be L</function>.

C<$pod> is the file name of the pod file. The return value is an array
reference containing the errors. A second argument switches on
verbosity:

    my $errors = pod_link_checker ($pod);

This functionality was introduced on 2016-08-25.

=cut

sub pod_link_checker
{
    my ($pod, $verbose) = @_;
    my @lines = read_lines ($pod);
    @lines = map {s/\n$//r} @lines;
    my %headers;
    my %links;
    my $count = 0;
    for (@lines) {
	$count++;
	if (/^=head[0-9]+\s+(.*?)\s*$/) {
	    my $header = $1;
	    chomp ($header);
	    if ($verbose) {
		print "Found header '$1'.\n";
	    }
	    $headers{$header} = $count;
	}
	while (/L<([^><]+)>/g) {
	    $links{$1} = $count;
	    if ($verbose) {
		print "Found link '$1'.\n";
	    }
	}
    }
    my @errors;
    for my $link (keys %links) {
	if ($verbose) {
	    print "link to $link at line $links{$link}\n";
	}
	if (my $line = $headers{$link}) {
	    my $error = "$pod:$line: link to $link should be L</$link>?";
	    if ($verbose) {
		print "$error\n";
	    }
	    push @errors, $error;
	}
	if (my $fault = unlikely_link ($link)) {
	    my $line = $links{$link};
	    my $error = "$pod:$line: link to L<$link> looks unlikely: $fault";
	    push @errors, $error;
	}
    }
    return \@errors;
}

sub unlikely_link
{
    my ($link) = @_;
    if ($link =~ /[a-z]\.[a-z]/) {
	if ($link !~ m!(?:ftp|https?)://!) {
	    return "URL without http:// etc?";
	}
    }

    # not sure what this was doing
    # if ($link =~ m!^.+/!) {
    # 	if ($link !~ m!^\w+::.*/.*$!) {
    # 	    if ($link !~ /mikan/) {
    # 		return "Unexpected slash";
    # 	    }
    # 	}
    # }
    # Allow it
    return undef;
}

=head2 make_examples

    make_examples ($dir, $verbose, $force);

Go into F<$dir> and run all the scripts called *.pl, and save their
output and error output into *-out.txt, where * is the name of the
script minus .pl. If an file -out.txt exists and is newer than *.pl,
the script is not run.

C<$verbose> switches on debugging messages. C<$force> forces a rebuild
of all the outputs, regardless of whether the scripts is older or
newer.

=cut

sub make_examples
{
    my ($dir, $verbose, $force) = @_;
    my @examples = <$dir/*.pl>;
    for my $example (@examples) {
	my $output = $example;
	$output =~ s/\.pl$/-out.txt/;
	if (older ($output, $example) || $force) {
	    do_system ("perl -I$Bin/blib/lib -I$Bin/blib/arch $example > $output 2>&1", $verbose);
	}
    }
}

# Helper to get exported variables.

sub get_exports
{
    my ($module) = @_;
    my @exports;
    eval "use lib \"$Bin/lib\";use $module ':all';\@exports = \@${module}::EXPORT_OK";
    if ($@) {
	croak $@;
    }
    return @exports;
}

=head2 extract_vars

    extract_vars ('Moby', \%vars);

Extract all the exported variables from the specified module, so if
Moby exports C<$data_dir> then 

    $vars{data_dir} = $Moby::data_dir

This examines C<@EXPORT_OK> in Moby to get the list of variables, and
also evaluates Moby. It assumes that it is being run from a
F<make-pod.pl> which is situated such that Moby is in F<lib/Moby.pm>.

Thus this is strongly dependent on a specific file layout.

Use

    extract_vars ($pm, \%vars, verbose => 1);

for debugging.

=cut

sub extract_vars
{
    my ($module, $vars, %options) = @_;
    if ($module =~ m!/!) {
	warn "$module looks wrong; use \$info->{colon} not \$info->{pm}";
    }
    my $verbose = $options{verbose};
    if ($verbose) {
	print "Module is $module.\n";
    }
    my $evals = "use lib \"$Bin/lib\";use $module ':all';";

    if ($verbose) {
	print "Evaling '$evals'.\n";
    }
    eval $evals;
    if ($verbose) {
	print "Getting exports from $module.\n";
    }
    my @exports = get_exports ($module);
    for my $var (@exports) {
	if ($var =~ /\$(.*)/) {
	    if ($verbose) {
		print "Adding $var to variables.\n";
	    }
	    my $nodollar = $1;
	    $vars->{$nodollar} = eval "\$$module::$nodollar";
	}
	elsif ($var =~ /((\@|\%)(.*))/) {
	    my $variable = $1;
	    my $sigil = $2;
	    my $nosigil = $3;
	    my $export = "\\$sigil$module::$nosigil";
	    if ($verbose) {
		print "Adding $variable as $export.\n";
		
	    }
	    $vars->{$nosigil} = eval $export;
	}
    }
}

sub get_section
{
    my ($pod, $section) = @_;
    my $dependencies;
    if (! -f $pod) {
	croak "No such file '$pod'";
    }
    open my $out, ">", \$dependencies or die $!;
    podselect ({-sections => [$section], -output => $out}, $pod);
    close $out or die $!;
    return $dependencies;
}

sub get_dep_section
{
    my ($pod) = @_;
    return get_section ($pod, "DEPENDENCIES");
}

sub pod_exports
{
    my ($pod, $pm) = @_;
    my @exports = get_exports ($pm);
    # Remove exported variables.
    @exports = grep !/\$|\@|\%/, @exports;
    my $functions = get_section ($pod, 'FUNCTIONS');
    if (! $functions && ! @exports) {
	# Consider this a successful test
	return 1;
    }
    if (@exports && ! $functions) {
	carp "Exports @exports in $pm, but no function section in $pod";
	return undef;
    }
    if ($functions && ! @exports) {
	carp "No exports in $pm but FUNCTIONS section in $pod";
    }
    my $ok = 1;
    for my $function (@exports) {
	if ($functions =~ /=head.*\s+$function\b/) {
	    next;
	}
	carp "$function is exported but not documented";
	$ok = undef;
    }
    return $ok;
}

use FindBin '$Bin';

sub make_pod
{
    my (%options) = @_;
    my $verbose = $options{verbose};
    my %pbv = (
	base => $Bin,
	verbose => $verbose,
    );
    my $info = get_info (%pbv);
    my $commit = get_commit (%pbv);
    # Names of the input and output files containing the documentation.

    my $pod = $info->{pod};
    my $input = "$pod.tmpl";
    my $output = $pod;

    # Template toolkit variable holder

    my %vars = (
	info => $info,
	commit => $commit,
    );

    my $tt = Template->new (
	ABSOLUTE => 1,
	INCLUDE_PATH => [
	    $Bin,
	    pbtmpl (),
	    "$Bin/examples",
	],
	ENCODING => 'UTF8',
	FILTERS => {
	    xtidy => [
		\& xtidy,
		0,
	    ],
	},
	STRICT => 1,
    );

    my @examples = <$Bin/examples/*.pl>;
    for my $example (@examples) {
	my $output = $example;
	$output =~ s/\.pl$/-out.txt/;
	if (older ($output, $example) || $options{force}) {
	    do_system ("perl -I$Bin/blib/lib -I$Bin/blib/arch $example > $output 2>&1", $verbose);
	}
    }

    chmod 0644, $output;
    $tt->process ($input, \%vars, $output, binmode => 'utf8')
    or die '' . $tt->error ();
    chmod 0444, $output;
}

1;
