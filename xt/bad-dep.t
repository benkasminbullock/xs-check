use warnings;
use strict;
use utf8;
use FindBin '$Bin';
use Test::More;
my $builder = Test::More->builder;
binmode $builder->output,         ":utf8";
binmode $builder->failure_output, ":utf8";
binmode $builder->todo_output,    ":utf8";
binmode STDOUT, ":encoding(utf8)";
binmode STDERR, ":encoding(utf8)";
use Perl::Build 'get_info';
use Perl::Build::Dist ':all';

my $info = get_info (base => "$Bin/..");

my $pm = "$info->{base}/$info->{pm}";
my $pod = "$info->{base}/$info->{pod}";
my @modules = depend ($pm);

SKIP: {
    if (! @modules) {
	skip "No dependencies", 2;
    }
    check_bad_modules (\@modules);
    check_dep_section ($pod, \@modules);
    check_makefile_dep (\@modules);
};


done_testing ();
