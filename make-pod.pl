#!/home/ben/software/install/bin/perl
use warnings;
use strict;
use FindBin '$Bin';

use Getopt::Long;
use Template;

use lib "$Bin/copied/lib";

use Perl::Build qw/get_info get_commit/;
use Perl::Build::Pod ':all';
use Deploy qw/do_system older/;

my $ok = GetOptions (
    'force' => \my $force,
    'verbose' => \my $verbose,
);

if (! $ok) {
    usage ();
    exit;
}

my $pod = "$Bin/lib/XS/Check.pod";

my %vars = (
    verbose => $verbose,
    force => $force,
    base => $Bin,
    pod => $pod,
);

make_pod (%vars);

exit;

sub usage
{
    print <<USAGEEOF;
--verbose        Print debugging messages
--force          Force rebuilding of the examples
USAGEEOF
}

