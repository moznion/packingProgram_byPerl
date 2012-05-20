#!/usr/bin/perl

use strict;
use warnings;
use 5.010;
use File::Path;
use File::Find qw/find/;
use File::Copy qw/copy/;
use File::Copy::Recursive qw/rcopy/;
use JSON qw/decode_json/;
use Archive::Tar;

unless(defined($ARGV[0])){
    say "Invalid command parameter.";
    exit(1);
}

my $inputFileName = $ARGV[0];

(my $targetDirectoryName, my @inputData) = &getData($inputFileName);
&initialize($targetDirectoryName);
my @inputDecodedData = &decodeJSON(@inputData);
&checker(\@inputDecodedData, $targetDirectoryName, $inputFileName);
&copyFiles(\@inputDecodedData, $targetDirectoryName);

# Ignoring specified files.
if(defined($ARGV[1])) {
    my $toIgnoreFileName = $ARGV[1];
    ($_, my @toIgnoreData) = &getData($toIgnoreFileName);
    my @ignoreData = &decodeJSON(@toIgnoreData);
    &removeFiles(\@ignoreData, $targetDirectoryName);
}

&packing($targetDirectoryName);

&finalize(0, $targetDirectoryName);

###########################################################################

sub decodeJSON {
    my(@inputData) = @_;

    my @decodedData;
    foreach (@inputData) {
        push(@decodedData, decode_json($_));
    }

    return @decodedData;
}

sub getData {
    my($inputFileName) = @_;

    open(FH, $inputFileName);

    my $targetDirectoryName = <FH>;
    $targetDirectoryName =~ s/\x0D?\x0A$//g; # chomp

    my @inputData;
    foreach (<FH>) {
        s/\x0D?\x0A$//g; # chomp
        push(@inputData, $_);
    }

    return($targetDirectoryName, @inputData);
}

sub checker {
    my($decodedData, $targetDirectoryName, $inputFileName) = @_;

    say "checking...";

    my $lineNumber = 1;
    foreach (@$decodedData) {
        unless(defined($_->{"location"}) && defined($_->{"type"}) && defined($_->{"target"})) {
            say "[Error] ".$inputFileName.": line ".$lineNumber;
            say "This line has problem about property.";
            &finalize(1, $targetDirectoryName);
        }

        # Is file(directory) exist?
        # And is property of 'type' valid?
        if($_->{"type"} =~ /file/i) {
            unless(-f $_->{"location"}) {
                say "[Error] ".$inputFileName.": line ".$lineNumber;
                say "'".$_->{"location"}."'"." is not exist.";
                &finalize(1, $targetDirectoryName);
            } 
        } elsif ($_->{"type"} =~ /dir/i) {
            unless(-d $_->{"location"}) {
                say "[Error] ".$inputFileName.": line ".$lineNumber;
                say "'[dir] ".$_->{"location"}."'"." is not exist.";
                &finalize(1, $targetDirectoryName);
            }
        } else {
            say "[Error] ".$inputFileName.": line ".$lineNumber;
            say "invalid value of 'type'.";
            &finalize(1, $targetDirectoryName);
        }

        # Make directory structure.
        unless($_->{"target"} eq "/" && -e $targetDirectoryName."/".$_->{"target"}) {
            mkdir $targetDirectoryName."/".$_->{"target"};
        }

        $lineNumber += 1;
    }
}

sub copyFiles {
    my($decodedData, $targetDirectoryName) = @_;

    say "copying...";

    foreach (@$decodedData) {
        if($_->{"type"} =~ /file/i) {
            copy($_->{"location"}, $targetDirectoryName.$_->{"target"});
        } elsif ($_->{"type"} =~ /dir/i) {
            rcopy($_->{"location"}, $targetDirectoryName.$_->{"target"});
        }
        print ".";
    }
    print "\n";
}

sub removeFiles {
    my($decodedData, $targetDirectoryName) = @_;

    say "Removing unnecessary files...";

    foreach (@$decodedData) {
        if($_->{"type"} =~ /file/i) {
            unlink $targetDirectoryName.$_->{"target"};
        } elsif ($_->{"type"} =~ /dir/i) {
            rmtree $targetDirectoryName.$_->{"target"};
        } else {
            next;
        }
        print ".";
    }
    print "\n";
}

sub packing {
    my($targetDirectoryName) = @_;

    say "packing...";

    my $compressRate = 2;
    my $tar = Archive::Tar->new;

    my @targetFiles;
    find(sub {
            push @targetFiles, $File::Find::name;
        }, $targetDirectoryName);

    $tar->add_files(@targetFiles);
    $tar->write($targetDirectoryName.".tar.gz", $compressRate);
}

sub initialize {
    my($targetDirectoryName) = @_;

    say "Initializing...";

    rmtree[$targetDirectoryName];
    unless(-d $targetDirectoryName) {
        umask(0);
        mkdir ($targetDirectoryName, 0755);
    }
    if(-f $targetDirectoryName.".tar.gz"){
        unlink $targetDirectoryName.".tar.gz";
    }
}

sub finalize {
    my($num, $targetDirectoryName) = @_;

    say "finalizing...";

    rmtree[$targetDirectoryName];
    exit($num);
}
