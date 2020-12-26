# Copied from /home/ben/projects/perl-build/lib/Perl/Build.pm
package Perl::Build;
require Exporter;
use warnings;
use strict;
our @ISA = qw(Exporter);
our @EXPORT = qw/perl_build get_version get_commit get_info/;
our @EXPORT_OK = qw/add dist clean c $badfiles build_dist/;
our %EXPORT_TAGS = (all => \@EXPORT_OK);
our $VERSION = '99999999.99';
use Getopt::Long;
use Deploy 'do_system';
use Template;
use FindBin '$Bin';
use Purge;
use File::Path;
use Carp;
use C::Maker 'make_c_file';
use File::Copy;
use IPC::Run3;
use Path::Tiny;

my $dir = __FILE__;
$dir =~ s/\.pm//;
my $template_dir = "$dir/templates";
my $tt;

our $badfiles = qr!(\.tmpl|-out\.txt|(?:make-pod|build)\.pl|xt\/.*\.t)$!;

sub perl_build
{
    my (%inputs) = @_;

    my $ok = GetOptions (
    "clean" => \my $clean,
    "dist" => \my $dist,
    "pan" => \my $pan,
    "add" => \my $add,
    "install" => \my $install,
    "kover" => \my $cover,
    "verbose" => \my $verbose,
    );

    if (! $ok) {
	print <<EOF;
Options:

--clean
--dist
--pan
--add
--install
--kover
--verbose
EOF
	exit;
    }

    if ($verbose) {
        $inputs{verbose} = 1;
    }

    # Change the makefile behaviour if there are C files.

    if ($inputs{c} || $inputs{cmaker}) {
        if ($inputs{makefile}) {
            croak "Cannot specify a makefile with the c/cmaker options";
        }
        $inputs{makefile} = 'makeitfile';
    }
    if ($clean) {
        clean (%inputs);
    }
    elsif ($dist) {
        dist (%inputs);
    }
    elsif ($pan) {
        pan (%inputs);
    }
    elsif ($add) {
        add (%inputs);
    }
    elsif ($install) {
        install (%inputs);
    }
    elsif ($cover) {
        cover (%inputs);
    }
    else {
        build (%inputs);
    }
    exit;
}

sub install
{
    my %inputs = @_;
    build (%inputs);
    if (-f 'Makefile.PL' && -f 'Makefile') {
        do_system ("make install > /dev/null");
    }
    if ($inputs{makefile}) {
	do_system ("make install");
    }
}

sub cover
{
    my %inputs = @_;
    build (%inputs);
    do_system ("cover -test -outputdir /usr/local/www/data/cover/");
}

sub build
{
    my %inputs = @_;
    my $make_pod = $inputs{make_pod};
    if (! $make_pod && -f './make-pod.pl') {
	$make_pod = './make-pod.pl';
    }
    if ($make_pod) {
	eval {
	    # Use "perl" here since $make_pod probably contains local
	    # Perl path.
	    do_system ("perl $make_pod");
	};
	if ($@) {
	    warn "Pod build failed: $@\n";
	}
    }
    if ($inputs{pod}) {
        if (ref $inputs{pod} ne 'ARRAY') {
            croak "Use an array reference as argument to pod => ";
        }
        for my $pod (@{$inputs{pod}}) {
            my $pod_tmpl = "$pod.tmpl";
            if ($inputs{verbose}) {
                print "Turning $pod_tmpl into $pod.\n";
            }
            make_pod ($pod, %inputs);
        }
    }
    if ($inputs{c}) {
        push @{$inputs{stems}}, c (%inputs);
    }
    if ($inputs{cmaker}) {
        push @{$inputs{stems}}, cmaker (%inputs);
    }
    if ($inputs{pre}) {
        my $pre = $inputs{pre};
        if ($inputs{verbose}) {
            print "Running pre-build script '$pre'.\n";
        }
        do_system ($pre);
    }
    if ($inputs{stems}) {
        make_makefile (%inputs);
    }
    if ($inputs{makefile}) {
        my $makefile = $inputs{makefile};
        if ($inputs{verbose}) {
            print "Making with '$makefile'.\n";
        }
        do_system ("make -f $makefile");
    }
    if (-f 'Makefile.PL') {
	# Use do_system here, we MUST stop the build if the tests
	# fail.  This caused bad deploys for games-commentator when it
	# was "system".
	my $devnull = '> /dev/null';
	if ($inputs{verbose}) {
	    $devnull = '';
	}
        do_system ("perl Makefile.PL $devnull;make $devnull;make test",
		   $inputs{verbose});
    }
    elsif ($inputs{makefile}) {
        my $makefile = $inputs{makefile};
        if ($inputs{verbose}) {
            print "Testing with '$makefile'.\n";
        }
        do_system ("make -f $makefile test", $inputs{verbose});
    }
    elsif ($inputs{test}) {
	do_system ($inputs{test});
    }
}

sub c
{
    my (%inputs) = @_;
    my $c = $inputs{c};
    if (ref $c ne 'ARRAY') {
        croak "c's value should be an array reference";
    }
    my @stems;
    for my $x (@$c) {
        my $stems = $x->{stems};
        my $c_dir = $x->{dir};
        if (! $stems) {
            croak "No stems for C files";
        }
        if (! $c_dir) {
            croak "No dir for C files";
        }
        for my $stem (@$stems) {
            my $c_file = "$stem.c";
            my $h_file = "$stem.h";
	    my $rhfile = "$c_dir/$h_file";
	    # Try to make the .h file if it doesn't exist.
	    if (! -f $rhfile) {
		do_system ("make -C $c_dir $h_file");
	    }
            for my $file ($c_file, $h_file) {
                my $rfile = "$c_dir/$file";
                if (! -f $file || -f $rfile && -M $file > -M $rfile) {
                    if ( -f $file) {
			chmod 0644, $file;
                        unlink $file;
                    }
                    copy $rfile, $file;
		    chmod 0444, $file;
                }
            }
            push @stems, $stem;
        }
    }
    return @stems;
}

sub cmaker
{
    my (%inputs) = @_;
    my @stems;
    my $cmaker = $inputs{cmaker};
    for my $base (@$cmaker) {
        make_c_file ($base, $FindBin::Bin);
        push @stems, $base;
    }
    return @stems;
}

sub clean
{
    my (%inputs) = @_;
    if (-f "Makefile") {
        system ("make clean > /dev/null");
    }
    my @unneeded = qw/Makefile.old MANIFEST.bak cover_db/;
    # If there is a file called this, then the manifest can be
    # regenerated automatically from it, so the manifest can also be
    # removed as part of the cleanup.
    if (-f 'MANIFEST.SKIP') {
	if (-f 'MANIFEST') {
	    print "Removing generated MANIFEST.\n";
	    push @unneeded, 'MANIFEST';
	}
    }
    if (-f 'README') {
	my $is_auto_readme;
	open my $in, "<", 'README' or die $!;
	while (<$in>) {
	    if (/About - what the module does/) {
		$is_auto_readme = 1;
		last;
	    }
	}
	close $in or die $!;
	if ($is_auto_readme) {
	    print "Removing generated README.\n";
	    push @unneeded, 'README';
	}
    }
    if (-f '') {

    }
    for my $file (@unneeded) {
        if (-f $file) {
            unlink $file or die $!;
        }
        elsif (-d $file) {
            rmtree ($file);
        }
    }
    if ($inputs{pod}) {
        for my $pod (@{$inputs{pod}}) {
            if (-f $pod) {
                unlink $pod or die $!;
            }
        }
    }
    if ($inputs{clean}) {
	if ($inputs{verbose}) {
	    print "Cleaning with $inputs{clean}.\n";
	}
        system ("$inputs{clean}");
    }
    if ($inputs{makefile}) {
        my $makefile = $inputs{makefile};
	if (-f $makefile) {
	    print "Making clean with '$makefile'.\n";
	    system ("make -f $makefile clean");
	}
    }
    if ($inputs{cmaker}) {
	if ($inputs{no_cmaker_clean}) {
	    print "Not cleaning for cmaker.\n";
	}
	else {
	    print "Cleaning for cmaker.\n";
	    my @cmaker = @{$inputs{cmaker}};
	    for my $stem (@cmaker) {
		for my $suffix (qw/c h/) {
		    my $file = "$stem.$suffix";
		    if (-f $file) {
			unlink $file;
		    }
		}
	    }
	}
    }
    my @targz = <*.tar.gz>;
    if (@targz) {
        for my $file (@targz) {
            if ($file =~ /(^[A-Z].*[\d]+\.[\d_]+)\.tar\.gz$/) {
		my $untarred = $1;
                print "Removing old tarball '$file'.\n";
                unlink $file or die "Can't remove '$file': $!";
		if (-d $untarred) {
		    print "Removing untarred tarball '$untarred'.\n";
		    rmtree ($untarred);
		}
            }
            else {
                print "Not removing tarball '$file'.\n";
            }
        }
    }
    purge_dir ($FindBin::Bin, recursive => 1);
}

sub add
{
    my %inputs = @_;
    clean (%inputs);
    # Don't check the return value here, because if there is nothing
    # to commit, this returns an empty value.
    system ("git add $FindBin::Bin; git commit -a");
}

sub dist
{
    my %inputs = @_;
    if (! -f 'MANIFEST.SKIP') {
        if (! -f 'MANIFEST') {
            die "No manifest in this directory";
        }
    }
    if (! $inputs{nodistclean}) {
	clean (%inputs);
    }
    build (%inputs);
    if (-f 'MANIFEST.SKIP') {
        do_system ("make manifest > /dev/null");
    }
    do_system ("make dist > /dev/null");
}

sub get_tt
{
    if (! $tt) {
        $tt = Template->new (
            ABSOLUTE => 1,
            RELATIVE => 1,
            INCLUDE_PATH => [
                $template_dir,
            ],
            ENCODING => 'utf8',
        );
    }
    return $tt;
}

# Make for CPAN.

sub pan
{
    my %inputs = @_;

    clean (%inputs);
    build (%inputs);
    # Make README before making distribution tarfile, so it's included
    # in MANIFEST.

    # Make MYMETA.json
    do_system ("perl Makefile.PL");
    # Make the README
    my $readme = 'README';
    if (-f $readme) {
	unlink $readme or die "Can't remove $readme: $!";
    }
    if (! -f 'PRIVATE') {
	do_system ("makereadme > $readme");
	if (! -f $readme) {
	    die "Failed to make $readme";
	}
    }
    dist (%inputs, nodistclean => 1);
    if (system ("prove ~/bin/check-changes") != 0) {
	clean (%inputs);
	die "Bad Changes file.\n";
    }
    if (-d "xt") {
	print "Running extra tests\n";
	my $blib = "-I blib/lib -I blib/arch";
	for my $file (<xt/*.t>) {
	    print "Running tests in $file.\n";
	    do_system ("prove $blib $file");
	}
    }
    print "Running 'make disttest'.\n";
    do_system ("make disttest > /dev/null");
}

sub make_pod
{
    my ($pod, %inputs) = @_;
    my $pod_tmpl = "$pod.tmpl";
    my $tt = get_tt ();
    if ($inputs{verbose}) {
	print "$pod $pod_tmpl\n";
    }
    my %vars;
    my $version = get_version (%inputs);
    my $base = base (%inputs);
    $tt->process ("$base/$pod_tmpl", \%vars, $pod, binmode => 'utf8')
        or die ''. $tt->error ();
}

sub base
{
    my (%inputs) = @_;
    my $base = $inputs{base};
    if (! $base) {
	$base = $Bin;
    }
    return $base;
}

sub get_info
{
    my (%inputs) = @_;
    my %info;
    my $base = base (%inputs);
    # Local base directory of the distribution.
    $info{base} = $base;
    my $makefilepl = "$base/Makefile.PL";
    if (! -f $makefilepl) {
	if ($inputs{verbose}) {
	    print "get_info: No $makefilepl found.\n";
	}
	return \%info;
    }
    my $mpath = path ($makefilepl);
    my $mtext = $mpath->slurp ();
    my %mvars;
    # Only match top-level variables
    while ($mtext =~ /^my\s*\$(\w+)\s*=\s*['"]([^'"]+)['"]/gsm) {
	$mvars{$1} = $2;
    }
    # Remove all dollar variables
    for my $k (keys %mvars) {
	my $v = $mvars{$k};
#	print "$k $v\n";
	$v =~ s/\$(\w+)/$mvars{$1}/g;
#	print "$k $v\n";
	$mvars{$k} = $v;
    }

    if ($mvars{pod}) {
	$info{pod} = $mvars{pod};
    }
    if ($mvars{pm}) {
	my $pm = $mvars{pm};
	$info{pm} = $pm;
	my $pmpath = path ("$base/$pm");
	my $pmtext = $pmpath->slurp ();
	if ($pmtext =~ /VERSION\s*=\s*['"]([^'"]+)['"]/) {
	    my $version = $1;
	    if ($inputs{verbose}) {
		print "get_info: Found version $version.\n";
	    }
	    $info{version} = $version;
	}
	elsif ($inputs{verbose}) {
	    print "get_info: No version info found in $pm.\n";
	}
	$info{name} = $info{pm};
	$info{name} =~ s!/!-!g;
	$info{name} =~ s!lib-|\.pm$!!g;
	$info{colon} = $info{name};
	$info{colon} =~ s/-/::/g;
    }
    else {
	if ($inputs{verbose}) {
	    print "get_info: No \$pm found in $makefilepl.\n";
	}
    }
    $info{repo} = $mvars{repo};
    return \%info;
}

# Get the version of the module.

sub get_version
{
    my $info = get_info (@_);
    return $info->{version};
}

sub make_makefile
{
    print "Making makefile.\n";
    my (%inputs) = @_;
    my @stems = @{$inputs{stems}};
    my @c_files = map {"$_.c"} @stems;

    run3 (["makedepend", "-f-", @c_files], undef, \my $dependencies, \my $errors);
    if ($errors) {
        carp "Makedepend: $errors";
    }
    my $tt = get_tt ();
    my %vars;
    $vars{dependencies} = $dependencies;
    $vars{no_clean} = $inputs{no_clean};
    if (! $inputs{no_cmaker_clean}) {
	$vars{clean} = join ' ', (map {"$_.[cho]"} @stems);
    }
    $vars{objs} = join ' ', (map {"$_.o"} @stems);
    for my $file (qw/makeitfile/) {
        $tt->process ("$file.tmpl", \%vars, $file)
            or die '' . $tt->error ();
    }
}

# Get the git commit

sub get_commit
{
    my (%inputs) = @_;
    my $base = base (%inputs);
    chdir $base or die "Error chdir to $base: $!";
    my $temp = Path::Tiny->tempfile ();
    do_system ("git log -n 1 > $temp");
    my @lines = $temp->lines ();
    if (! @lines) {
	die "no lines";
    }
    my %vals;
    for (@lines) {
	if (/^commit\s+(.*)/) {
	    $vals{commit} = $1;
	    next;
	}
	if (/^Date:\s*(.*)$/) {
	    $vals{date} = $1;
	    next;
	}
    }
    die "no date or commit" unless $vals{date} && $vals{commit};
    return \%vals;
}

sub build_dist
{
    my ($base) = @_;
    my $info = get_info (base => $base);
    if (! $info) {
	die; 
    }
    my $v = $info->{version};
    if (! $v) {
	die; 
    }
    my $n = $info->{name};
    if (! $n) {
	die; 
    }
    chdir $base or die $!;
    do_system ("./build.pl -p");
    my $tf = "$n-$v.tar.gz";
    if (! -f $tf) {
	die; 
    }
    return $tf;
}

1;

=head1 NAME

Perl::Build - perl build stuff

=head1 SYNOPSIS

Basic usage:

    use Perl::Build;
    perl_build (
    );

Usage with options:

    use Perl::Build;
    perl_build (
        makefile => 'mymakefile',
    );

=head1 DESCRIPTION

This module is used from a script called F<build.pl>. Without options,
it assumes that it is being required to build a Perl module.

=head1 ARGUMENTS

=head2 base

Base directory for building.

=head2 c

Specify c files to copy from another directory. The argument is an
array consisting of hash references like

    c => [{
        dir => '/my/cool/dir',
        stems => [qw/monkey funky junkie/],
    },
    ],

All the files are copied from there. In the above case,
F</my/cool/dir/monkey.c>, F</my/cool/dir/monkey.h>,
F</my/cool/dir/funky.c>, etc. If this is used, it also adds an
argument to C<makefile> of C<makeitfile>. Using the L<makefile> option
together with this causes a fatal error.

=head2 clean

Specify a script to run to clean the directory. This script is run
before "make clean" and the built-in cleanups.

=head2 cmaker

    cmaker => ['stem', 'stem2'],

Use L<C::Maker> to generate files from inputs. C::Maker is a macro
preprocessor which converts C programs written according to some
conventions, and writes header files for them.

=head2 makefile

Specify a makefile which is run before the usual Perl build process
itself. This is also used for the command-line option

=head2 make_pod

    make_pod => 'script-to-make-pod.pl',

Specify a script to use to make the pod documentation files. This is
run before L</pod>.

=head2 pod

    pod => ['pod-file.pod.tmpl', ],

Specify pod files to generate using the standard templates. The value
must be an array reference containing pod file templates. Not using an
array reference causes a fatal error.

=head2 pre

    pre => 'do-this-first.pl',

Specify a script to run before running "make" for the build case, the
case that the script is run without any command line options.

=head2 test

    test => 'test-script',

A script to run to test the output of the build. This is overridden by
the existence of F<Makefile.PL> in the current directory, or by the
L</makefile> value in C<%inputs>. The script is only run if neither a
file F<Makefile.PL> nor an option C<makefile> are present.

=head1 COMMAND-LINE OPTIONS

Without a command line option, it builds and tests the module. The
following command line options affect the behaviour as described.

=over

=item --clean

This makes "build.pl" do "make clean" and whatever else is
specified. If L</makefile> is specified, it also runs C<make -f
makefile-name clean>. If L</cmaker> is specified, it removes all of
the C files copied, and also runs C<make -f makeitfile clean>.

=item --add

This makes "build.pl" run as if called with "--clean", then does "git add .; git
commit -a".

=item --install

Run the build process followed by C<make install>.

=item --dist

Run the build process followed by C<make dist>. It does not run "make
disttest", upload the distribution, or update the version number.

=item --kover

Run coverage test.

=item --verbose

Turn on messages.

=back

=head1 FUNCTIONS

=head2 perl_build

This function runs the main program. It reads command-line
options. Its default behaviour is to build the Perl module whose top
directory is the same directory that F<build.pl> is to be found in.

=head2 c

    c (%inputs);

Copy C files from the directories and files specified by
C<$inputs{c}>. This is not exported by default.

=head2 clean

    clean (%inputs);

Clean up generated files. This is equivalent to the --clean command
line option. This is not exported by default.

=head2 add

    add (%inputs);

Clean out the directory and then add all the files under git. This is not exported by default.

=head2 dist

    dist (%inputs);

Make a distribution, like "make dist". Also does L</clean> and
L</build> and makes a manifest if a file F<MANIFEST.SKIP> exists in
the current directory.

=head2 get_info

    my $info = get_info (%inputs);

Returns a hash reference containing all of the variables defined in
F<Makefile.PL> such as C<$repo>, C<$pm>, etc., as hash keys and values
(the hash keys don't contain a dollar). This also gets the module
version by looking at C<$pm>, opening the file, and getting its
$VERSION value.

Use C<< verbose => 1 >> to get informational messages. This obsoletes
L</get_version>.

The keys and values of the returned object are:

=over

=item pm

The module's file name, like C<lib/Perl/Build.pm>.

=item base

The base directory of the distribution.

=item colon

The module's CPAN name, like C<Perl::Build>.

=item name

The module's hyphenated name, like C<Perl-Build>.

=item pod

The pod file of the distribution, if it exists.

=item repo

The github repository, extracted from C<Makefile.PL>.

=item version

The version of the distribution, extracted from L</pm>.

=back

=head2 get_version

This is obsolete, use L</get_info> and C<< $info->{version} >> now.

    my $version = get_version (%inputs);

Get the version. Specify a base directory like this:

    my $version = get_version (base => "$Bin/..");

=head2 get_commit

    my $commit = get_commit (%inputs);

The inputs are similar to L</get_version>. The output is a hash reference which has the following information:

=over

=item commit

The git commit, the hexadecimal digits themselves.

=item date

The date of the commit.

=back

=head1 EXPORTS

L</perl_build>, L</get_info>, L</get_version>, and L</get_commit> are
exported by default.

    use Perl::Build ':all';

to get the unexported-by-default functions exported.

=head1 STATUS

This module is currently not distributed.

=cut
