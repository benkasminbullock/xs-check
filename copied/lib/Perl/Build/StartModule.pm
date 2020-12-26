# Copied from /home/ben/projects/perl-build/lib/Perl/Build/StartModule.pm
package Perl::Build::StartModule;
use Carp;
use Devel::PPPort;
use Cwd;
use Path::Tiny;
use Date::Calc 'Today';
use File::Copy;
require Exporter;
our @ISA = qw(Exporter);
our @EXPORT = qw/mkdir_warn write_or_warn make_build_pl binmode_utf8/;

use Deploy 'do_system';
use Cwd;

sub new
{
    return bless {};
}

=head2 make_manifest

    $sm->make_manifest ();

Make the "MANIFEST.SKIP" file.

=cut

sub make_manifest
{
    my ($sm) = @_;
    my $trunk = $sm->{trunk};
    my $skip = "$sm->{dirname}/MANIFEST.SKIP";
    if (! -f $skip) {
        open my $ms, ">", $skip or die $!;
        print $ms <<EOF;
# Exclude the author-only build scripts
(build|make-pod|clean)\\.pl
# Exclude the built module
blib/.*
# Exclude all git files
\\.gitignore\$
\\.git/.*
# Don't include the Makefile made from Makefile.PL in the distribution.
Makefile\$
# Exclude the stamp file
pm_to_blib
# Exclude the META files made by ExtUtils::MakeMaker
MYMETA\..*
# Exclude backup files made by ExtUtils::MakeMaker
.*\\\.bak
# Exclude untarred distribution files
^$sm->{hyphens}-[0-9\\.]+/\$
# Exclude tarred distribution files
^$sm->{hyphens}-[0-9\\.]+\\\.tar\\\.gz\$
# Template for building pod file.
^$sm->{pod}\\.tmpl\$
# Don't include the outputs from running the examples
^examples/.*-out\\.txt\$
# Author tests
^xt/.*\.t\$
EOF
        if ($sm->{xs}) {
            print $ms <<EOF;
^$trunk\.(?:c|o|bs)\$
EOF
        }
        close $ms or die $!;
    }
}

=head2 make_build_pl

    make_build_pl ($dirname);

Make the F<build.pl> file.

=cut

sub make_build_pl
{
    my ($sm) = @_;
    my $dirname = $sm->{dirname};
    my $podname = $sm->{pod_name};
    $podname =~ s!$dirname/!!;
    my $build_pl =<<EOF;
#!/home/ben/software/install/bin/perl
use warnings;
use strict;
use FindBin '\$Bin';
use Perl::Build;
perl_build (
    make_pod => "\$Bin/make-pod.pl",
);
exit;
EOF
    my $out = "$dirname/build.pl";
    write_or_warn ($out, $build_pl);
    chmod 0744, $out or die $!;
}

sub make_make_pod
{
    my ($sm) = @_;
    my $make_pod =<<'EOF';
#!/home/ben/software/install/bin/perl
use warnings;
use strict;
use Template;
use FindBin '$Bin';
use Perl::Build qw/get_info get_commit/;
use Perl::Build::Pod ':all';
use Deploy qw/do_system older/;
use Getopt::Long;
my $ok = GetOptions (
    'force' => \my $force,
    'verbose' => \my $verbose,
);
if (! $ok) {
    usage ();
    exit;
}
my %pbv = (
    base => $Bin,
    verbose => $verbose,
);
my $info = get_info (%pbv);
my $commit = get_commit (%pbv);
# Names of the input and output files containing the documentation.

my $pod = '%TRUNK%.pod';
my $input = "$Bin/lib/%REST%/$pod.tmpl";
my $output = "$Bin/lib/%REST%/$pod";

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
    if (older ($output, $example) || $force) {
	do_system ("perl -I$Bin/blib/lib -I$Bin/blib/arch $example > $output 2>&1", $verbose);
    }
}

chmod 0644, $output;
$tt->process ($input, \%vars, $output, binmode => 'utf8')
    or die '' . $tt->error ();
chmod 0444, $output;

exit;

sub usage
{
print <<USAGEEOF;
--verbose
--force
USAGEEOF
}

EOF
    $make_pod =~ s/%TRUNK%/$sm->{trunk}/g;
    $make_pod =~ s/%REST%/$sm->{rest}/g;
    my $out = $sm->{dirname} . "/make-pod.pl";
    write_or_warn ($out, $make_pod);
    chmod 0744, $out or die $!;
    mkdir "$sm->{dirname}/examples" or die $!;
}


=head2 mkdir_warn

    mkdir_warn ($dirname);

Make directory F<$dirname> if it does not exist, or warn if it does.

=cut

sub mkdir_warn
{
    my ($dirname) = @_;
    if (-d $dirname) {
        warn "Directory '$dirname' already exists.\n";
    }
    else {
        mkdir $dirname or die $!;
    }
}

=head2 write_or_warn

    write_or_warn ($pmname, $contents);

=cut

sub write_or_warn
{
    my ($pmname, $contents) = @_;
    if (-f $pmname) {
        warn "Module file '$pmname' already exists: not overwriting.\n";
    }
    else {
        open my $pm, ">", $pmname or die "Cannot open '$pmname' for writing: $!";
        print $pm $contents;
        close $pm or die $!;
    }
}

# Make the XS file.

sub make_xs
{
    my ($sm) = @_;
    my $name = $sm->{name};
    my $cfile = "$name-perl.c";
    $cfile =~ s/::/-/g;
    $cfile = lc $cfile;
    my $cobj = $name;
    $cobj =~ s/::/_/g;
    $cobj = lc $cobj;
    $cobj .= "_t";
    my $uname = $name;
    $uname =~ s/::/__/g;
    my $xs_contents = <<EOF;
#include "EXTERN.h"
#include "perl.h"
#include "XSUB.h"
#include "ppport.h"

#include "$cfile"

typedef $cobj * $uname;

MODULE=$name PACKAGE=$name

PROTOTYPES: DISABLE

BOOT:
	/* ${uname}_error_handler = perl_error_handler; */

EOF
    write_or_warn ("$sm->{dirname}/$sm->{xsname}", $xs_contents);
    my $cfile_contents = <<EOF;
typedef struct {

}
$cobj;

static int
perl_error_handler (const char * file, int line_number, const char * msg, ...)
{
    va_list args;
    va_start (args, msg);
    vcroak (msg, & args);
    va_end (args);
    return 0;
}
EOF
    write_or_warn ("$sm->{dirname}/$cfile", $cfile_contents);

    my $typemap_contents = <<EOF;
$cobj * T_PTROBJ
$name T_PTROBJ
EOF
    write_or_warn ("$sm->{dirname}/typemap", $typemap_contents);
    my $dir = getcwd ();
    chdir ($sm->{dirname}) or die $!;
    Devel::PPPort::WriteFile ();
    chdir ($dir) or die $!;
}

=head2 make_gitignore

    $sm->make_gitignore ();

Make the ".gitignore" file for the distribution.

=cut

sub make_gitignore
{
    my ($sm) = @_;
    open my $gitignore, ">", ".gitignore" or die $!;
    print $gitignore <<EOF;
# Generated from Makefile.PL
Makefile
Makefile.old
Makefile.bak
# Ignore distribution files.
$sm->{hyphens}-[0-9]*/
$sm->{hyphens}-[0-9]*.tar.gz
# Ignore outputs of XS compilation.
$sm->{trunk}.c
$sm->{trunk}.bs
# Ignore Perl compilation files.
pm_to_blib
blib/*
MYMETA.*
META.*
ppport.h
$sm->{pod}
MANIFEST
README
examples/*-out.txt
EOF
    close $gitignore or die $!;
}

sub start_git_repo
{
    my ($sm) = @_;
    my $devnull = "> /dev/null";
    if ($sm->{verbose}) {
	$devnull = '';
    }
    my $dirname = $sm->{dirname};
    chdir $dirname or die "Can't change directory to '$dirname': $!";
    $sm->make_gitignore ();
    do_system ("git init . $devnull");
    do_system ("git add . $devnull");
    do_system ("git commit -a -m 'Initial commit of $dirname' $devnull");
}

sub make_pod_contents
{
    my ($sm) = @_;
    my $name = $sm->{name};
    die if $name =~ /-/ && $name !~ /::/;
    my ($year, undef, undef) = Date::Calc::Today ();
    my $pod_contents = <<EOF;
[% start_year=$year %]
[% MACRO example(file) BLOCK %]
[%- pl =  file _ ".pl" -%]
[%- out = file _ "-out.txt" -%]
[% INCLUDE \$pl | xtidy %]

produces output

[% INCLUDE \$out | xtidy %]

(This example is included as L<F<[% pl %]>|https://fastapi.metacpan.org/source/BKB/$sm->{hyphens}-[% info.version %]/examples/[% pl %]> in the distribution.)
[% END %]
[% MACRO since(version) BLOCK -%]
This method was added in version [% version %] of the module.
[%- END %]
=encoding UTF-8

=head1 NAME

[% info.colon %] - abstract here.

=head1 SYNOPSIS

    use [% info.colon %];

=head1 VERSION

This documents version [% info.version %] of [% info.name %]
corresponding to L<git commit [% commit.commit %]|[% info.repo
%]/commit/[% commit.commit %]> released on [% commit.date %].

=head1 DESCRIPTION

=head1 FUNCTIONS

[% INCLUDE "author" %]
EOF
    return $pod_contents;
}

# This makes the text of the ".pm" file, given the name.

sub make_pm_contents
{
    my ($sm) = @_;
    my $name = $sm->{name};
    my $pm_contents = <<EOF;
package $name;
use warnings;
use strict;
use Carp;
use utf8;
require Exporter;
our \@ISA = qw(Exporter);
our \@EXPORT_OK = qw//;
our \%EXPORT_TAGS = (
    all => \\\@EXPORT_OK,
);
our \$VERSION = '0.01';
EOF

    # For an XS module, add the XSLoader stuff.

    if ($sm->{xs}) {
        $pm_contents .= <<EOF;
require XSLoader;
XSLoader::load ('$name', \$VERSION);
EOF
    }

    # Add the trailing "1;" which is required to return a true value.

    $pm_contents .= <<EOF;
1;
EOF
    return $pm_contents;
}

=head2 make_xt

Make the tests in xt/

=cut

sub make_xt
{
    my ($sm) = @_;
    my $dirname = $sm->{dirname};
    mkdir "$dirname/xt" or die "Cannot mkdir $dirname/xt: $!";
    my $git =<<'EOF';
use Test::More;
use Perl::Build::Git ':all';
use FindBin '$Bin';
ok (no_uncommited_changes ($Bin), "no uncommited changes");
ok (branch_is_master ($Bin), "branch is master");
ok (up_to_date ($Bin), "no uncommitted changes");
done_testing ();
EOF
    write_or_warn ("$dirname/xt/git.t", $git);
    my $checkpod =<<EOF;
use warnings;
use strict;
use utf8;
use FindBin '\$Bin';
use Test::More;
EOF
    $checkpod .= binmode_utf8 ();
    $checkpod .=<<EOF;
use Perl::Build::Pod qw/pod_checker pod_link_checker/;
my \$filepath = "\$Bin/../$sm->{pod}";
my \$errors = pod_checker (\$filepath);
ok (\@\$errors == 0, "No errors");
if (\@\$errors > 0) {
    for (\@\$errors) {
	note "\$_";
    }
}
my \$linkerrors = pod_link_checker (\$filepath);
ok (\@\$linkerrors == 0, "No link errors");
if (\@\$linkerrors > 0) {
    for (\@\$linkerrors) {
	note "\$_";
    }
}
done_testing ();
EOF
    write_or_warn ("$dirname/xt/checkpod.t", $checkpod);
my $distro =<<'EOF';
use warnings;
use strict;
use utf8;
use FindBin '$Bin';
use Test::More;
use Perl::Build qw/get_info/;

# Check that the OPTIMIZE flag is not set in Makefile.PL. This causes
# errors on various other people's systems when compiling.

my $file = "$Bin/../Makefile.PL";
open my $in, "<", $file or die $!;
while (<$in>) {
    if (/-Wall/) {
	like ($_, qr/^\s*#/, "Commented out -Wall in Makefile.PL");
    }
}
close $in or die $!;


# Check that the examples have been included in the distribution.

my $info = get_info (base => "$Bin/..");
my $name = $info->{name};
my $version = $info->{version};
my $distrofile = "$Bin/../$name-$version.tar.gz";
if (! -f $distrofile) {
    die "No $distrofile";
}
my @tgz = `tar tfz $distrofile`;
my %badfiles;
my %files;
for (@tgz) {
    if (/(\.tmpl|-out\.txt|(?:make-pod|build)\.pl)$/) {
	$files{$1} = 1;
	$badfiles{$1} = 1;
    }
}
ok (! $files{".tmpl"}, "no templates in distro");
ok (! $files{"-out.txt"}, "no out.txt in distro");
ok (! $files{"make-pod.pl"}, "no make-pod.pl in distro");
ok (! $files{"build.pl"}, "no build.pl in distro");
ok (keys %badfiles == 0, "no bad files");
done_testing ();

EOF
    write_or_warn ("$dirname/xt/distro.t", $distro);
    for my $file (qw/bad-dep vars/) {
	copy "/home/ben/projects/perl-mod-maint/generic-xt/$file.t", "$dirname/xt/$file.t";
    }
}

sub make_changes
{
    my ($sm) = @_;
    my $changes = path("$sm->{dirname}/Changes");
    my ($year, $month, $day) = Today();
    my $date = sprintf("%d-%02d-%02d", $year, $month, $day);
    my $content =<<EOF;
Revision history for Perl module $sm->{name}

0.01 $date

- Initial version

EOF
    write_or_warn ($changes, $content);
}

sub binmode_utf8
{
    return <<EOF;
my \$builder = Test::More->builder;
binmode \$builder->output,         ":utf8";
binmode \$builder->failure_output, ":utf8";
binmode \$builder->todo_output,    ":utf8";
binmode STDOUT, ":encoding(utf8)";
binmode STDERR, ":encoding(utf8)";
EOF
}

1;
