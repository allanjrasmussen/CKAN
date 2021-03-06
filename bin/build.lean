#!/usr/bin/perl
use 5.010;
use strict;
use warnings;
use autodie qw(:all);
use FindBin qw($Bin);
use File::Path qw(remove_tree);
use IPC::System::Simple qw(systemx capturex);
use File::Spec;
use File::Copy::Recursive qw(rcopy);
use autodie qw(rcopy);

# Simple script to build and repack

my $REPACK  = "CKAN/packages/ILRepack.1.25.0/tools/ILRepack.exe";
my $TARGET  = "Release";     # 'Debug' is okay too.
my $OUTNAME = "ckan.exe";   # Or just `ckan` if we want to be unixy
my $BUILD   = "$Bin/../build";
my $SOURCE  = "$Bin/../CKAN";
my $VERSION = capturex(qw(git describe --tags --long));
my @ASSEMBLY_INFO = (
    File::Spec->catdir($BUILD,"CKAN/Properties/AssemblyInfo.cs"),
    File::Spec->catdir($BUILD,"CmdLine/Properties/AssemblyInfo.cs"),
    File::Spec->catdir($BUILD,"GUI/Properties/AssemblyInfo.cs"),
);

# Remove newline
chomp($VERSION);

# Make sure we clean any old build away first.
remove_tree($BUILD);

# Copy our project files over.
copy($SOURCE, $BUILD);

# Remove any old build artifacts
remove_tree(File::Spec->catdir($BUILD, "CKAN/bin"));
remove_tree(File::Spec->catdir($BUILD, "CKAN/obj"));

# Before we build, add our version number in.

foreach my $assembly (@ASSEMBLY_INFO) {
    open(my $assembly_fh, ">>", $assembly);
    say {$assembly_fh} qq{[assembly: AssemblyInformationalVersion ("$VERSION")]};
    close($assembly_fh);
}

# Change to our build directory
chdir($BUILD);

# And build..
system("xbuild", "/property:Configuration=$TARGET", "CKAN.sln");

say "\n\n=== Repacking ===\n\n";

chdir("$Bin/..");

# Repack ckan.exe

my @cmd = (
    $REPACK,
    "--out:ckan.exe",
    "--lib:build/CmdLine/bin/$TARGET",
    "build/CmdLine/bin/$TARGET/CmdLine.exe",
    glob("build/CmdLine/bin/$TARGET/*.dll"),
    "build/CmdLine/bin/$TARGET/CKAN-GUI.exe", # Yes, bundle the .exe as a .dll
);

system(@cmd);

# Repack netkan

@cmd = (
    $REPACK,
    "--out:netkan.exe",
    "--lib:build/NetKAN/bin/$TARGET",
    "build/NetKAN/bin/$TARGET/netkan.exe",
    glob("build/NetKAN/bin/$TARGET/*.dll"),
);

system(@cmd);

say "\n\n=== Tidying up===\n\n";

# We don't tidy up any more, these provide useful debugging.
# unlink("$OUTNAME.mdb");
# unlink("netkan.exe.mdb");

say "Done!";

# Do an appropriate copy for our system
sub copy {
    my ($src, $dst) = @_;

    if ($^O eq "MSWin32") {
        # Use File::Copy::Recursive under Windows
        rcopy($src, $dst);
    }
    else {
        # Use friggin' awesome btrfs magic under Linux.
        # This still works, even if not using btrfs (justh with less magic)
        my @CP      = qw(cp -r --reflink=auto --sparse=always);
        system(@CP,$src,$dst);
    }
    return;
}
