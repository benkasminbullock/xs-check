# Copied from /home/ben/projects/purge/lib/Purge.pm
=head1 NAME

Purge - remove backup files

=cut
package Purge;
require Exporter;
@ISA = qw(Exporter);
@EXPORT = qw/purge_dir/;
use warnings;
use strict;
use Cwd;
our $VERSION = '0.02';

sub purge_dir
{
    my ($dir, %options) = @_;

    my $cwd = getcwd ();

#    print "verbosity: ", $options{verbose}, "\n";

    # make a list of all the files except . and ..

    opendir (DIR, $dir) || die "purge: can't open '$dir': $!";
    my @allfiles = grep (!/^\.\.?$/, readdir (DIR));
    closedir (DIR) or die $!;

    # Delete files matching a pattern using unlink.

    for my $file (@allfiles) {
        my $full = "$dir/$file";
        remove (qr/~$/, "backup", $dir, $file, $cwd, $options{verbose});
        remove (qr/^#.*#$/, "emacs save", $dir, $file, $cwd, $options{verbose}); 
        remove (qr/^core$/, "core", $dir, $file, $cwd, $options{verbose});
        if (-d $full && $options{recursive}) {
            purge_dir ($full, %options);
        }
    }
}

sub remove
{
    my ($re, $type, $dir, $file, $cwd, $verbose) = @_;
    if ($file =~ $re) {
        if ($verbose) {
            my $f = "$dir/$file";
            $f =~ s/$cwd/./;
	    if ($verbose) {
		print "Removing $type file '$f'\n";
	    }
        }
        my $full = "$dir/$file";
        unlink $full or warn "Could not remove '$full': $!";
    }
}

1;
