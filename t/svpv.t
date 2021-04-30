use FindBin '$Bin';
use lib $Bin;
use XSCT;

my $svpv = <<EOF;
char * c;
STRLEN len;
SV * x;
c = SvPV(x, len);
EOF

got_warning ($svpv, "SvPV without bytes or utf8", 1);

done_testing ();
