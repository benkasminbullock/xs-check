# This is a test for module XS::Check.

use warnings;
use strict;
use Test::More;
use_ok ('XS::Check');
use XS::Check;
my $warning;
$SIG{__WARN__} = sub {
$warning = shift;
};
my $checker = XS::Check->new ();
$checker->check (<<EOF);
const char * x;
STRLEN len;
x = SvPV (sv, len);
EOF
ok (! $warning, "No warning with OK code");
$warning = undef;
$checker->check (<<EOF);
const char * x;
unsigned int len;
x = SvPV (sv, len);
EOF
ok ($warning, "Warning with not STRLEN");
$warning = undef;
$checker->check (<<EOF);
char * x;
STRLEN len;
x = SvPV (sv, len);
EOF
ok ($warning, "Warning with not const char *");
$warning = undef;
$checker->check (<<EOF);
const char * x;
x = malloc (100);
EOF
ok ($warning, "Warning with malloc");

done_testing ();
# Local variables:
# mode: perl
# End:
