#!/usr/bin/env perl
# $Id: directoryScrub.pl,v 1.23 2009/12/14 23:44:44 givans Exp $

use strict;
use Carp;
use warnings;
no warnings "recursion";
use Cwd;
use Sys::Hostname qw/ hostname /;
use Getopt::Std;
use vars qw/ $opt_d $opt_D $opt_v $opt_L $opt_l $opt_b $opt_a $opt_h $opt_o $opt_x $opt_e $opt_z /;

getopts('d:D:vLlbahoxz');
my ($dir,$days,$debug,$log,$verbose,$help,$all,$usage,%deletes,$list,$empty);
$debug = 0 || $opt_z;
$log = 0;
$verbose = 0 || $opt_v || $opt_z;
$help = 0 || $opt_h;
$all = 0 || $opt_a;
$list = $opt_l || $opt_o;
#$empty = $opt_e;
$usage = "directoryScrub.pl -D <directory name> -d <oldest file to keep, in days> (-x or -l or -o)";
if ($help) {

print <<HELP;

This script removes files and folders from a user-specified directory
based on a user-specified file age.

usage:  $usage

Option		Description
-D		full path to directory to delete files from
-d		oldest file to keep, in days
-x		delete files
-l		display sorted list of files that will be deleted 
-o		display list of files to be deleted when they are identified 
        -l waits until the end and sorts the list of file names
        Neither -o or -l actually deletes the files, invoking either just lists files
-L		log information to LOG file called /tmp/scrub.log
-v		print verbose information to stdout
-b		debugging output to stdout
-a		remove every file (some files are usually spared, ie. CVS)
-h		print this help menu

HELP
exit(0);
}



if ($opt_L) {
  $log = 1;
  open(LOG,">/tmp/scrub.log") or die "can't open LOG file: $!";
  print LOG hostname(), "\n";
  print LOG "+" x 50, "\ndirectoryScrub: ", scalar(localtime()), "\n\n";
  select(LOG);
}

if ($opt_b) {
  $debug = 1;
  print "debugging ON\n";
}

if (!($opt_D && $opt_d)) {
  print "usage:  $usage\n";
  exit(0);
}

if (!-e $opt_D) {
  print "'$opt_D' doesn't exist\n";
  exit(0);
} elsif (!-d $opt_D) {
  print "'$opt_D' isn't a directory\n";
  exit(0);
} else {
  $dir = $opt_D;
}

if ($opt_d < 0) {
  print "number of days must be positive\n";
  exit(0);
} elsif ($opt_d =~ /\D/) {
  print "number of days should only contain digits\n";
  exit(0);
} else {
  $days = $opt_d;
}

print "-" x 40, "\n";
print hostname(), "\n";
print "directoryScrub started:  ", scalar(localtime), "\n";
print "scrubbing '$dir' for files older than $days days\n";
print "only listing files that would be deleted given these parameters\n" if ($list);
print "\n";

my $files = getFileNames($dir);

deleteLoop($files,$days);

if ($opt_l) {
#  foreach my $file (sort {$a cmp $b} sort {length($b) <=> length($a) } keys %deletes) {
#  foreach my $file (sort {length($b) <=> length($a) } keys %deletes) {
  foreach my $file (sort filesort keys %deletes) {
    print "$file\n";
  }
}

sub filesort {
  length($b) <=> length($a)
    or
  $a cmp $b
}

sub getFileNames {
  my $dir = shift;
  my @files;

  if (!chdir($dir)) {
    croak("can't chdir to '$dir': $!");
  } else {
    print "chdir to '$dir' successful\n" if ($debug);
  }

  opendir(THIS, ".") or croak("can't opendir this directory: $!");
  @files = readdir(THIS);
#   foreach my $file (readdir(THIS)) {
#     push(@files,"$dir" . "/$file");
#   }
  closedir(THIS);

  if ($debug) {
    print "files in '$dir':\n";
    foreach my $file (@files) {
      print "$file\n";
    }
  }

  return \@files;
}

sub deleteLoop {
  my $files = shift;
  my $age = shift;
  $age = $days if (!$age);
  my $dir = cwd();

  foreach my $file (@$files) {
 #   next unless (-r $file && -w $file);
    my $ldir = cwd();
    print "file '($ldir) $dir/$file'\n" if ($debug);
    next if ($file eq '..' || $file eq '.' || (!$all && $file eq 'CVS'));
    print "checking if file is a symlink\n" if ($debug);
    next if (-l $file); # don't follow symbolic links
    print "making sure this is either a file or directory\n" if ($debug);
    #next unless (-f $file || -d $file);
    next unless (-e $file);
    print "preliminaries finished, now checking age of file '$dir/$file'\n" if ($debug);

    if ($age) {
        eval {
            if ( -M $file > $age ) {
                print "$dir/$file age is > $age days\n" if ($debug);
                if ( -f $file ) {
                    print "deleting '$dir/$file'\n" if ( $verbose || $debug );

                    #if (!$debug) {
                    if (1) {
                        if ( !$list && $opt_x ) {
                            if ( unlink($file) ) {
                                print "$dir/$file was deleted successfully\n"
                                  if ($verbose);
                            }
                            else {
                                print "$dir/$file was NOT deleted: $@\n"
                                  if ($verbose);
                            }
                        }
                        else {
                            print "f:  '" . cwd() . "/$file'\n" if ($opt_o);
                            ++$deletes{ "f:  " . cwd() . "/$file" } if ($opt_l);
                        }
                    }
                }
                elsif ( -d $file ) {
                    print "deleting directory '$dir/$file'\n" if ($verbose);
                    deleteDir( "$dir/$file", $age );

                    #	deleteDir("$dir" . "/$file");
                }
                else {
                    print "'$dir/$file' is not a plain file\n" if ($debug);
                }
            }
            else {
                print "'$dir/$file' is newer than $age days\n" if ($debug);
            }
        };    #end of eval statement
    }

    if ($@) {
      print "trouble with file: '$file'\n";
      exit();
    }

    deleteDir("$dir/$file",$age) if (-d $file);
    print "going back to top of loop\n\n" if ($debug);
  }


}

sub deleteDir {
  my $dir = shift;
  my $age = shift;
  my $deleteDir = 0;

  if (!chdir($dir)) {
    die "can't chdir to '$dir': $!";
  }

  $deleteDir = 1 if (-M $dir > $age);
  
  print "checking files inside of directory '$dir'\n" if ($debug || $verbose);
  my $dirfiles = getFileNames($dir);
  deleteLoop($dirfiles,$age);
  if (!chdir('..')) {
    die "can't chdir out of '$dir': $!";
  }

#  if (!$debug) {
  # if I check the modification date now, the directory won't
  # be deleted because I just deleted a file, above. So, the
  # modification date will be now(). Technically, I've already
  # checked the date.
  #if (-M $dir > $age) {
  if ($deleteDir) {
#    print "checking files inside of directory '$dir'\n" if ($debug || $verbose);
#    my $dirfiles = getFileNames($dir);
#    deleteLoop($dirfiles,$age);
#    if (!chdir('..')) {
#        die "can't chdir out of '$dir': $!";
#    }
    if (!$list && $opt_x) {
      if (!rmdir($dir)) {
	print "can't remove directory '$dir': $!\n" if ($verbose || $debug);
      } else {
	print "directory '$dir' deleted\n" if ($debug);
      }
    } else {
      print "d:  '$dir'\n" if ($opt_o);
      ++$deletes{"d:  $dir"} if ($opt_l);
    }
  }


}
