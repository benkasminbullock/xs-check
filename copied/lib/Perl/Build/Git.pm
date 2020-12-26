# Copied from /home/ben/projects/perl-build/lib/Perl/Build/Git.pm
=head1

Perl::Build::Git - git tests

=cut

package Perl::Build::Git;
use parent Exporter;
our @EXPORT_OK = qw/no_uncommited_changes branch_is_master up_to_date/;
our %EXPORT_TAGS = (all => \@EXPORT_OK);
use warnings;
use strict;
use utf8;
use Carp;
use Path::Tiny;

=head2 up_to_date

    ok (up_to_date ($Bin), "no unpushed changes");

Check that there are not any unpushed changes in the directory specified.

=cut

sub up_to_date
{
    my ($dir) = @_;
    my $tempfile = Path::Tiny->tempfile ();
    system ("chdir $dir;git status > $tempfile");
    my $status = $tempfile->slurp ();
    my $ok = ($status !~ qr/Your branch is ahead of/i);
    $tempfile->remove ();
    return $ok;
}

=head2 no_uncommited_changes

    ok (no_uncommited_changes ($Bin), "no uncommited changes");

Check that there are not uncommited changes in the specified directory.

=cut

sub no_uncommited_changes
{
    my ($dir) = @_;
    my $tempfile = Path::Tiny->tempfile ();
    system ("chdir $dir;git diff > $tempfile");
    my $ok = ! -s $tempfile;
    $tempfile->remove ();
    return $ok;
}

=head2 branch_is_master

   ok (branch_is_master ($Bin), "branch is master");

Check that we are on the master branch in the specified directory.

=cut

sub branch_is_master
{
    my ($dir) = @_;

    my $filename = Path::Tiny->tempfile ();
    system ("chdir $dir; git branch > $filename");
    my $in = $filename->slurp ();
    my $ok;
    if ($in =~ /\*\h*master/) {
	$ok = 1;
    }
    $filename->remove ();
    return $ok;
}

=head1 DEPENDENCIES

Perl::Build::Git depends on the following modules.

=over

=item Path::Tiny

L<Path::Tiny> is used to supply the temporary file names used for
storing the output of the "git" command.

=back

=cut

1;
