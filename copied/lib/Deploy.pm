# Copied from /home/ben/projects/deploy/lib/Deploy.pm
package Deploy;
use warnings;
use strict;

require Exporter;
our @ISA = qw(Exporter);

our @EXPORT_OK = qw/
		       add_with_dir
		       batch_edit
		       check_master
		       copy_files
		       copy_those_files
		       copy_to_temp
		       copy_to_temp_ref
		       do_nfsn
		       do_scp
		       do_scp_get
		       do_ssh
		       do_system
		       dump_manifest
		       env_path
		       file_slurp
		       get_log_files
		       get_git_sha
		       gzip_scp_file
		       latest
		       make_date
		       make_date_time
		       make_temp_dir
		       mdate
		       older
		       rm_rf
		       ssh_mkdir
		       upload
		       upload_dir
		       write_ro_file
		   /;

our %EXPORT_TAGS = ('all' => \@EXPORT_OK);
our $VERSION='0.05';

use File::Copy 'copy';
use Cwd 'getcwd';
use Carp qw/carp croak confess/;
use Time::Local;
use File::Temp 'tempfile';
use File::Slurper 'read_text';
use JSON::Parse 'parse_json';

sub mdate
{
    my ($filename) = @_;
    if (!-e $filename) {
        carp "file '$filename' not found";
	return undef;
    }
    my @stat = stat ($filename);
    if (@stat == 0) {
        carp "'stat' failed for '$filename': $@";
	return undef;
    }
    return $stat[9];
}

sub older
{
    my ($file_a, $file_b) = @_;
    if (! -f $file_a) {
        return 1;
    }
    my $mdate_a = mdate ($file_a);
    my $mdate_b = mdate ($file_b);
    return $mdate_a < $mdate_b;
}

sub do_nfsn
{
    my ($command, %options) = @_;
    my $ssh_login = $options{ssh_login};
    my $dir = $options{dir};
    my %topt;
    if ($dir) {
	$topt{DIR} = $dir;
    }
    my (undef, $temp) = tempfile (%topt);
    my $verbose = $options{verbose};
    my $ssh_command = "ssh -x $ssh_login nfsn -j $command > $temp";
    if ($verbose) {
        print "I am going to do '$ssh_command':\n";
    }
    do_system ($ssh_command, $verbose);
    my $text = read_text ($temp);
    my $result = parse_json ($text);
    unlink $temp or die "Can't unlink $temp: $!";
    if ($result->{success}) {
        if ($verbose) {
            print "Successfully completed.\n";
        }
        return;
    }
    if ($options{fail_ok}) {
        if ($verbose) {
            print "Command failed '$text' but ignored.\n";
        }
        return;
    }
    die "'$ssh_command' failed: $text";
}

sub do_ssh
{
    my ($host, $command, $verbose) = @_;
    if ($command =~ /"/) {
	$command =~ s/"/\\"/g;
    }
    my $thing = "ssh -x $host \"$command\"";
    if ($verbose) {
        print "I am going to do '$thing'.\n";
    }
    do_system ($thing, $verbose);
}

sub do_scp
{
    my ($host, $files, $remote_dir, $verbose) = @_;
    my $thing;
    if ($remote_dir) {
	$thing = "scp $files $host:$remote_dir/"
    }
    else {
	$thing = "scp $files $host:"
    }
    do_system ($thing, $verbose);
}

sub do_system
{
    my ($command, $verbose) = @_;
    if ($verbose) {
        print "Doing '$command'.\n";
    }
    system ("$command") == 0 or croak "'$command' failed with error: $!";
}


sub dump_manifest
{
    my ($manifest) = @_;
    for my $k (keys %$manifest) {
	if (! defined $manifest->{$k}) {
	    print "Copy $k -> directory\n";
	}
	else {
	    print "$k: $manifest->{$k}\n";
	}
    }
}


sub rm_rf
{
    my ($dir_name) = @_;
    die "No directory" unless $dir_name;
    croak 'Bad directory name: must end in "_temp"' unless $dir_name =~ /_temp/;
    if (-d $dir_name) {
#	print "removing $dir_name\n";
	system ("rm -rf $dir_name");
    }
    else {
#	print "$dir_name does not exist\n";
    }
}



sub make_temp_dir
{
    my ($temp_dir_name) = @_;
    rm_rf ($temp_dir_name);
    mkdir $temp_dir_name or croak "Couldn't make '$temp_dir_name': $!";
}



sub copy_files
{
    my ($temp_dir_name, $files_ref, $special_files_ref) = @_;
    # Use an empty hash to simplify the logic in the loop over the files.
    $special_files_ref = {} unless $special_files_ref;
    croak "Non-existent directory '$temp_dir_name'" unless -d $temp_dir_name;
    for my $file (@$files_ref) {
	my $action = $special_files_ref->{$file};
	if ($action) {
	    my $file_no_dir = $file;
	    $file_no_dir =~ s:^.*/::;
	    if (ref $action eq "CODE") {
		&{$action}($file, "$temp_dir_name/$file_no_dir");
	    }
            else {
		die "Don't know what to do with the action '$action'";
	    }
	}
        else {
	    local_copy $file, $temp_dir_name
		or die "Copy '$file' to '$temp_dir_name' failed: $!";
	}
    }
}



sub batch_edit
{
    my ($edits_href, $in_file, $out_file, $verbose) = @_;
    die "Input failure" unless $edits_href && $in_file && $out_file;
    my @keys = keys %$edits_href;
    confess "Nothing to edit" unless scalar (@keys) > 0;
    my @matches = sort { length $b <=> length $a } @keys;

    my $text;

    if (! ref $in_file) {
        open my $input,  "<:encoding(utf8)", $in_file
            or croak "Can't open '$in_file': $!";
        while (<$input>) { $text .= $_ }
        close $input or die $!;
    }
    elsif (ref $in_file eq 'SCALAR') {
        $text = $$in_file;
    }
    else {
        croak "Don't know what to do with your second argument of type ", 
            ref $in_file;
    }

#    my $original = $text;

    for my $lhs (@matches) {
	my $rhs = $edits_href->{$lhs};
	if ($text =~ s/\Q$lhs\E/$rhs/egs) {
#	    print "Found $lhs as $&\n";
	}
	else {
	    if ($verbose) {
		carp "Did not find '$lhs' in $text";
	    }
	}
    }

    # if ($text eq $original) {
    # 	carp "Batch edit has not changed the input";
    # 	return;
    # }

    if (!ref $out_file) {
        open my $output, ">:encoding(utf8)", $out_file
            or croak "Can't open '$out_file': $!";
        print $output $text;
        close $output or die $!;
    }
    elsif (ref $out_file eq 'SCALAR') {
        $$out_file = $text;
    }
    else {
        croak "Don't know what to do with your third argument of type ", 
            ref $out_file;
    }
}



sub do_scp_get
{
    my ($host, $files, $local_dir, $verbose) = @_;
    die "No host" unless $host;
    die "No files specified" unless $files;
    $local_dir = "." unless $local_dir;
    my $command = "scp $host:$files $local_dir";
    my $devnull = ' > /dev/null ';
    if ($verbose) {
        print "Doing '$command'.\n";
	$devnull = '';
    }
    system ("$command $devnull") == 0 or die "'$command' failed";
}



sub get_log_files
{
    my ($ssh_login, $remote_log_dir, $local_log_dir) = @_;
    my $files = "$remote_log_dir/*.bz2";
    eval {
        do_scp_get ($ssh_login, $files, $local_log_dir);
    };
    if ($@) {
        # Bug: this should check the error is not some other kind of
        # error.
        print "No log files to copy.\n";
        return;
    }
    my $command;
    eval {
        $command = "rm -f $files /home/tmp/awstats*.txt";
        do_ssh ($ssh_login, $command);
    };
    if ($@) {
	carp "$command failed: $@";
    }
}



# From FileInfo.pm
# BKB 2009-09-22 20:08:07



sub file_slurp
{
    my ($tempfile) = @_;
    open my $in, "<:encoding(utf8)", $tempfile 
	or croak "Could not open $tempfile: $!";
    my $contents;
    while (<$in>) { $contents .= $_ }
    close $in or croak "Could not close $tempfile: $!";
    return $contents;
}



sub ssh_mkdir
{
    my ($host, $dir, $verbose) = @_;
    do_ssh ($host, "if [ ! -d $dir ]; then mkdir -p $dir; fi", $verbose);
#    do_ssh ($host, "if [ ! -d $dir ]; then echo boo; fi", $verbose);
}



sub add_with_dir
{
    my ($dir, $manifest_ref, $file_list) = @_;
    for my $file (@$file_list) {
        $manifest_ref->{"$dir/$file"} = undef;
    }
}



sub local_copy
{
    my ($from_file, $to_file, $verbose) = @_;
    if ($verbose) {
        print "Copying $from_file to $to_file.\n";
    }
    copy $from_file, $to_file
        or confess "Error: copy \"$from_file\", \"$to_file\" failed: $!";
}

sub copy_to_temp
{
    my ($tmp_dir, $base_dir, %manifest) = @_;

    # Recreate the dir from scratch

    rm_rf ($tmp_dir);
    mkdir $tmp_dir or die $!;
    if (!-d $tmp_dir) {
        confess "Directory $tmp_dir not found";
    }

    # Copy the files

    chdir $base_dir or die $!;
    for my $file (keys %manifest) {
        if (ref $file) {
            warn "Non-string $file as key of \%manifest.\n";
            next;
        }
        my $outfile = $file;
        $outfile =~ s:.*/::;
        my $filesub = $manifest{$file};
        if ($filesub) {
            if (ref $filesub eq "CODE") {
                &{$filesub} ($file, "$tmp_dir/$outfile");
            }
            else {
                my $target = "$tmp_dir/$filesub";
                local_copy $file, $target;
            }
        }
        else {
            my $target = "$tmp_dir/$outfile";
            local_copy $file, $target;
        }
    }
}



sub copy_to_temp_ref
{
    my ($tmp_dir, $base_dir, $manifest_ref) = @_;
    copy_to_temp ($tmp_dir, $base_dir, %$manifest_ref);
}




sub upload
{
    my ($tmp_dir, $upload_dir, $cgi_dir, $ssh_login, $verbose) = @_;
    if (! -d $tmp_dir) {
        croak "Temporary directory '$tmp_dir' does not exist";
    }
    if ($verbose) {
	print "Deploy::upload: Changing directory to $tmp_dir.\n";
    }
    chdir "$tmp_dir" or die $!;
    my $this_dir = getcwd ();
    my $dtg = "deploy.tar.gz";
    if (-f $dtg) {
	if ($verbose) {
	    print "Deploy::upload: Removing old upload file $dtg.\n";
	}
	unlink $dtg or die $!;
    }
    if ($verbose) {
	print "Deploy::upload: Creating deploy.tar.gz.\n";
    }
    do_system ("tar cfz /tmp/deploy.tar.gz .", $verbose);
    if ($verbose) {
	print "Deploy::upload: rename /tmp/deploy.tar.gz $this_dir/deploy.tar.gz.\n";
    }
    copy "/tmp/deploy.tar.gz", "$this_dir/deploy.tar.gz" or die $!;
    unlink "/tmp/deploy.tar.gz" or die $!;
    if ($verbose) {
	print "Deploy::upload: Making $cgi_dir on web server.\n";
    }
    ssh_mkdir ($ssh_login, $cgi_dir, $verbose);
    if ($verbose) {
	print "Deploy::upload: Copying $dtg to $dtg on web server.\n";
    }
    do_system ("scp $dtg $ssh_login:$dtg");
    if ($verbose) {
	print "Deploy::upload: Moving $upload_dir/$dtg to $cgi_dir/$dtg on web server.\n";
    }
    do_ssh ($ssh_login, "mv $upload_dir/$dtg $cgi_dir/$dtg");
    if ($verbose) {
	print "Deploy::upload: Removing $tmp_dir on local server.\n";
    }
    chdir ".." or die $!;
    rm_rf ($tmp_dir);

    # Uncompress the remote files.

    if ($verbose) {
	print "Deploy::upload: Uncompressing/untarring $cgi_dir/$dtg on web server.\n";
    }
    do_ssh ($ssh_login, "tar xfz $cgi_dir/$dtg -C $cgi_dir");
    if ($verbose) {
	print "Deploy::upload: Removing $cgi_dir/$dtg from web server.\n";
    }
    do_ssh ($ssh_login, "rm -f $cgi_dir/$dtg");
}



sub upload_dir
{
    my ($local_dir, $ssh_login, $remote_dir) = @_;
    if (! -d $local_dir) {
        croak "First argument '$local_dir' is not a directory";
    }
    my $dir = getcwd ();
    chdir $local_dir or die $!;
    my $base = "upload";
    my $tar_file = "$base.tar";
    my $tgz = "$tar_file.gz";
    do_system ("tar cf upload.tar *");
    do_system ("gzip -f upload.tar");
    do_scp ($ssh_login, $tgz);
    if ($remote_dir) {
        do_ssh ($ssh_login, "mv $tgz $remote_dir/$tgz;cd $remote_dir;tar xfz $tgz;rm $tgz");
    }
    else {
        do_ssh ($ssh_login, "tar xfz $tgz;rm $tgz");
    }
    unlink $tgz or die $!;
    chdir $dir or die $!;
}



sub gzip_scp_file
{
    my ($host, $dir, $log) = @_;
    my $remote = "/home/private/$log";
    my $remote_gz = "/home/private/$log.gz";
    do_ssh ($host, "rm -f $remote $remote_gz;cp $dir/$log $remote;gzip $remote");
    do_scp_get ($host, $remote_gz);
    do_system ("gzip -f -d $log.gz");
    do_ssh ($host, "rm -f $remote $remote_gz");
}

sub copy_clean
{
    my ($path, $new_dir) = @_;
    my $file = $path;
    $file =~ s:.*/::;
    local_copy $path, "$new_dir/$file";
}

sub mkdir_clean
{
    my ($parent, $dir_name) = @_;
    die "$dir_name contains a slash" if $dir_name =~ m:/:;
    my $new_dir = "$parent/$dir_name";
    if (! -d $parent) {
        confess "Parent directory '$parent' does not exist";
    }
    if (-d $new_dir) {
        confess "Directory '$new_dir' already exists";
    }
    mkdir $new_dir or die "mkdir $new_dir failed: $!";
}

# When "diff --recursive x y" finds a subdirectory x/d which is not in
# y, it simply reports the existence of the subdirectory, without
# reporting on the individual contents. This routine assists
# "copy_diff_only" by creating the directory and copying the contents
# of the subdirectory into the new directory. The return value is the
# total number of files copied.

sub copy_subdir
{
    my ($new_dir, $output_dir, $sub_dir, $verbose) = @_;
#    print "Copying subdirectory '$sub_dir' from $new_dir to $output_dir\n";
    my $copied = 0;
    mkdir_clean ($output_dir, $sub_dir);
#    print "* Made subdirectory '$sub_dir'.\n" if $verbose;
    for my $file (<$new_dir/$sub_dir/*>) {
        if ( -d $file) {
            my $dir_name = $file;
            $dir_name =~ s:.*/::;
#            print "* copy_subdir: Recursing into '$file'.\n" if $verbose;
            $copied = copy_subdir ("$new_dir/$sub_dir", "$output_dir/$sub_dir",
                                   $dir_name, $verbose);
        } else {
#            print "* copy_subdir: Copying '$file'.\n" if $verbose;
            copy_clean ($file, "$output_dir/$sub_dir/"); 
            $copied++;
        }
    }
    return $copied;
}

sub check_master
{
    my ($verbose) = @_;
    my $branch = `git branch`;
    if ($branch !~ /\* master/) {
	die <<'EOF';
                                          
,------.                           ,--.   
|  .-.  \  ,---.  ,--,--,  ,---. ,-'  '-. 
|  |  \  :| .-. | |      \| .-. |'-.  .-' 
|  '--'  /' '-' ' |  ||  |' '-' '  |  |   
`-------'  `---'  `--''--' `---'   `--'   
                                          
                                          
               ,--.                  ,--. 
,--.,--. ,---. |  | ,---.  ,--,--. ,-|  | 
|  ||  || .-. ||  || .-. |' ,-.  |' .-. | 
'  ''  '| '-' '|  |' '-' '\ '-'  |\ `-' | 
 `----' |  |-' `--' `---'  `--`--' `---'  
        `--'                              
                                                                         
,--.  ,--.         ,--.                             ,--.                 
|  ,'.|  | ,---. ,-'  '-. ,--,--,--. ,--,--. ,---.,-'  '-. ,---. ,--.--. 
|  |' '  || .-. |'-.  .-' |        |' ,-.  |(  .-''-.  .-'| .-. :|  .--' 
|  | `   |' '-' '  |  |   |  |  |  |\ '-'  |.-'  `) |  |  \   --.|  |    
`--'  `--' `---'   `--'   `--`--`--' `--`--'`----'  `--'   `----'`--'    
                                                                         
DO NOT UPLOAD!!!!! THIS IS NOT THE MASTER BRANCH!!!!!!!

EOF
    }
    if ($verbose) {
	print "Master branch of " . getcwd (). " OK.\n";
    }
}


sub write_ro_file
{
    my ($outfile, $contents) = @_;
    if (-f $outfile) {
	chmod 0644, $outfile or die $!;
    }
    open my $out, ">:encoding(utf8)", $outfile or die $!;
    print $out $contents;
    close $out or die $!;
    chmod 0444, $outfile or die $!;
}

sub get_git_sha
{
    my ($dir) = @_;
    if (! $dir || ! -d $dir) {
	confess "Specify a directory to get_git_sha";
    }
    my $cwd = getcwd ();
    chdir $dir or die $!;
    my $git_sha = `git rev-parse HEAD`;
    $git_sha =~ s/\s+//g;
    my $diff = `git diff`;
    if ($diff) {
	warn "There are uncommited changes in '$dir'.\n";
    }
    chdir $cwd or die $!;
    return ($git_sha, $diff eq '' ? 1 : 0);
}

sub make_date
{
    my ($sep) = @_;
    if (! $sep) {
	$sep = '';
    }
    my (undef, undef, $day, $month, $year) = (localtime())[1,2,3,4,5];
    my $date_time = sprintf ("%04d%s%02d%s%02d",
                             $year + 1900, $sep, $month + 1, $sep, $day);
    return $date_time;
}

sub make_date_time
{
    my ($min, $hour, $day, $month, $year) = (localtime())[1,2,3,4,5];
    my $date_time = sprintf ("%04d%02d%02d%02d%02d",
                             $year + 1900, $month + 1, $day, $hour, $min);
    return $date_time;
}

# Set up path for cron jobs

sub env_path
{
    my @paths = qw!
		      /home/ben/bin
		      /home/ben/software/install/bin
		  !;
    if (! $ENV{PATH}) {
	$ENV{PATH} = '/usr/bin:/usr/local/bin';
    }
    for my $path (@paths) {
	if ($ENV{PATH} !~ m!\Q$path\E!) {
	    $ENV{PATH} .= ":$path";
	}
    }
}

my $datere = qr/
		   (?:^|[^0-9])
		   ([0-9]{4})
		   [^0-9]*
		   ([0-9]{1,2})
		   [^0-9]*
		   ([0-9]{1,2})
		   (?:[^0-9]|$)
	       /x;

sub latest
{
    my ($pattern) = @_;
    my @files = glob ($pattern);
    if (! @files) {
	croak "'$pattern' doesn't match any files";
    }
    my %times;
    for my $file (@files) {
	if ($file =~ /$datere/) {
	    my ($year, $month, $day) = ($1, $2, $3);
	    my $epoch = timegm (0, 0, 0, $day, $month - 1, $year - 1900);
	    $times{$epoch} = $file;
	}
	else {
	    carp "No date found in $file";
	}
    }
    my @times = sort {$a <=> $b} keys %times;
    return $times{$times[-1]};
}

sub copy_those_files
{
    my ($dir, $lib, $verbose) = @_;
    my $files = `cd $dir/lib; find . -name "*"`;
    my @files = split /\n/, $files;
    @files = grep !/\.pod(\.tmpl)?$/, @files;
    @files = grep !m!(/|^\.+)$!, @files;
    @files = grep !m!\.~[0-9+]~!, @files;
    @files = map {s!^\./!!r} @files;
    if ($verbose) {
	print "Files in $dir are @files\n";
    }
    for my $file (@files) {
#	print "$file\n";
#	next;
	my $infile = "$dir/lib/$file";
	my $ofile = "$lib/$file";
	if (-d "$dir/lib/$file") {
	    do_system ("mkdir -p $ofile", $verbose);
	    next;
	}
	if (-f $ofile) {
	    chmod 0644, $ofile or die $!;
	}
	if ($verbose) {
	    print "Copying $infile to $ofile.\n";
	}
	my $text = read_text ($infile);
	open my $out, ">:encoding(utf8)", $ofile or die "Can't open $ofile: $!";
	if ($file =~ /\.pm$/) {
	    if ($verbose) {
		print "Adding header.\n";
	    }
	    print $out <<EOF;
# Copied from $dir/lib/$file
EOF
	}
	print $out $text;
	close $out or die $!;
	chmod 0444, $ofile;
    }
}


1;



