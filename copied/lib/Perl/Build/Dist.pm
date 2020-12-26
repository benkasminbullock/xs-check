# Copied from /home/ben/projects/perl-build/lib/Perl/Build/Dist.pm
package Perl::Build::Dist;
use parent Exporter;
our @EXPORT_OK = qw/
		       bad_modules
		       depend
		       check_bad_modules
		       check_dep_section
		       check_makefile_dep
		   /;
our %EXPORT_TAGS = (all => \@EXPORT_OK);
use warnings;
use strict;
use utf8;
use FindBin '$Bin';
use Carp;
use Module::Extract::Use;
use Test::More;
use Perl::Build::Pod 'get_dep_section';
use JSON::Parse 'json_file_to_perl';
use Deploy qw/do_system older/;

# This is a list of modules which I try not to use in production code.

my @badmods = qw/
		     autodie
		     Path::Tiny
		     File::Slurp
		     IPC::Run3
		     Modern::Perl
		 /;
my %badmods;
@badmods{@badmods} = (1) x @badmods;

sub bad_modules
{
    my ($modules, %options) = @_;
    my %allow;
    if ($options{allow}) {
	for (@{$options{allow}}) {
	    $allow{$_} = 1;
	}
    }
    my @bad;
    for (@$modules) {
	if ($badmods{$_} && ! $allow{$_}) {
	    push @bad, $_;
	}
    }
    return @bad;
}

=head2 check_bad_modules

    check_bad_modules (\@modules);

Check whether there are any bad modules in the list of modules
supplied.

=cut

sub check_bad_modules
{
    my ($modules) = @_;
    my @bad = bad_modules ($modules);
    ok (! @bad, "No bad modules used");
    if (@bad) {
	for (@bad) {
	    note ("Bad module $_");
	}
    }
}

sub check_dep_section
{
    my ($pod, $modules) = @_;
    my $deps = get_dep_section ($pod);
    ok ($deps, "Has dependencies section");
    if ($deps) {
	for my $m (@$modules) {
	    like ($deps, qr!L<\Q$m\E(?:/.*)?>!, "Documented dependence on $m");
	}
    }
}

# Things provided by Perl, we don't need to check this.

my $builtin = qr!(?:
NEVERMATCH		     
|B
|Carp
|Cwd
|DynaLoader
|Encode
|Exporter
|FindBin
|POSIX
|Scalar::Util
|Sys::Hostname
|Test::More
|XSLoader
|base
|constant
|lib
|parent
|perl
|strict
|utf8
|warn
|warnings
)!x;

sub check_makefile_dep
{
    my ($modules) = @_;
    my $meta = "$Bin/../MYMETA.json";
    my $make = "$Bin/../Makefile.PL";
    if (older ($meta, $make)) {
	chdir "$Bin/../";
	do_system ("perl Makefile.PL");
	if (! -f $meta) {
	    die "no $meta";
	}
    }
    my $minfo = json_file_to_perl ($meta);
    my $runreq = $minfo->{prereqs}{runtime}{requires};
    my %mods;
    for my $module (@$modules) {
	next if $module =~ /\b($builtin)\b/;
	$mods{$module} = 1;
	ok (defined $runreq->{$module}, "Requirement for '$module' in module text is in meta file");
    }
    for my $req (keys %$runreq) {
	next if $req =~ /\b($builtin)\b/;
	ok (defined $mods{$req}, "Requirement for '$req' in meta file matches module");
    }
}
sub depend
{
    my ($pm) = @_;
    if (! -f $pm) {
	croak "Cannot locate file '$pm'";
    }
    my $extor = Module::Extract::Use->new;
    my @modules = $extor->get_modules ($pm);
    if ($extor->error) {
	warn "Error from Module::Extract::Use: " . $extor->error;
    }
    @modules = grep !/^$builtin$/, @modules;
    return @modules;
}

1;
