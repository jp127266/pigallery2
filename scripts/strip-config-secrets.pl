#!/usr/bin/perl
# git clean filter for config/config.json.
#
# PiGallery2 generates sessionSecret at runtime and writes it back into
# config.json. Those keys sign login cookies, so they must never reach the
# repo -- but the live file on disk needs to keep them, or restarting the
# container invalidates every session.
#
# A clean filter resolves that: the working file keeps its secrets, while the
# blob git stores has sessionSecret emptied. Because the filter normalises
# both sides, `git status` stays quiet instead of reporting a permanent diff.
#
# Reads config.json on stdin, writes the sanitised version to stdout.
# Byte-for-byte identical apart from the sessionSecret array contents.
use strict;
use warnings;

local $/;                      # slurp
my $config = <STDIN>;
$config = '' unless defined $config;
$config =~ s/("sessionSecret"\s*:\s*)\[[^\]]*\]/${1}[]/s;
print $config;
