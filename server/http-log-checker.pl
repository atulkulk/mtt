#!/usr/bin/env perl
#
# Copyright (c) 2008 Sun Microsystems, Inc. All rights reserved.
# $COPYRIGHT$
# 
# Additional copyrights may follow
# 
# $HEADER$
#

#
# This script should be run from Cron. It will send out an e-mail if
# error messages containing a certain pattern (e.g., "submit.php")
# show up in the HTTP(S) log file between invocations. Usage:
#
#   ./http-log-checker.pl
#
# Note: this script requires read/write access to the cache file
# (http-log-checker-cache.txt) in the current working directory

use Getopt::Long;
use File::Basename;
use Data::Dumper;
use strict;

# Set some defaults
my $http_log_file_arg = "/var/log/httpd/www.open-mpi.org/ssl_error_log";
my $email_arg         = "ethan.mallove\@sun.com";

# Kind of icky here. The below pattern matches against known error
# messages. If other submit.php errors are known, they should be added
# here manually.
my $pattern_arg = "gz.*submit\/index\.php";
my $help_arg;
my $debug_arg;
my $verbose_arg;

# Globals variables
my $script_name = basename($0);
my $cache_file = "http-log-checker-cache.txt";

&Getopt::Long::Configure("bundling");
my $ok = Getopt::Long::GetOptions(
    "file|f=s"    => \$http_log_file_arg,
    "email|e=s"   => \$email_arg,
    "pattern|p=s" => \$pattern_arg,
    "help|h"      => \$help_arg,
);

# Print help menu
if ($help_arg) {
    print "
$0 -

 -f|--file   Log file to use  (default: $http_log_file_arg)
 -e|--email  Email recipients (default: $email_arg)
 -h|--help   This help menu
";
    exit;
}

# Read the cache file to determine which lines need to be analyzed (We
# have to keep a cache of which lines have been analyzed becase the
# HTTP log file lines themselves are not timestamped)
my $cache_file = "http-log-checker-cache.txt";
open(CACHE_IN, "$cache_file");

my $analyzed_log_file_lines;
while (<CACHE_IN>) {
    # Ignore commented lines
    next if (/^\s*#/);
    if (/(\d+)\s+(\S+)/) {
        $analyzed_log_file_lines->{$2} = $1;
    }
}
close(CACHE_IN);

# Search for "pattern" in HTTP log files
my $email_body = "
This email was automatically sent by $script_name. You have received
it because some error messages were found in the HTTP(S) logs that
might indicate some MTT results were not successfully submitted by the
server-side PHP submit script (even if the MTT client has not
indicated a submission error). See the below log file for 
more details:

    $http_log_file_arg

";

my $send_email;
my $line_count;
my $line_count_already_analyzed;
my $worrisome_log_messages;
my $worrisome_log_messages_count = 0;
my $worrisome_log_messages_max = 20000;
foreach my $file (keys %$analyzed_log_file_lines) {
    next if (! -r $file);
    open(FILE, $file);

    $line_count_already_analyzed = $analyzed_log_file_lines->{$file};
    $line_count = 0;
    $worrisome_log_messages = "";
    while (<FILE>) {

        next if ($line_count++ < $line_count_already_analyzed);

        if (/$pattern_arg/) {

            # There can be a *ton* of HTTP log messages. The
            # ssl_error_log can reach an upwards of 16GB (!). We can't
            # email all of it (because Perl would run out of memory in
            # such a case). A few thousand lines ought to suffice.
            last if ($worrisome_log_messages_count++ > $worrisome_log_messages_max);
            $worrisome_log_messages .= $_;
            $send_email = 1;
        }
    }

    # If any log messages were found, write them to the email
    if ($worrisome_log_messages) {
        
        $email_body .= "
###############################################################
#
# The below log messages matched \"$pattern_arg\" in 
# $file
#
###############################################################

$worrisome_log_messages

";
    }
}

# Write out the cache file
open(CACHE_OUT, "> $cache_file");
my $wc_cmd = "wc -l $http_log_file_arg";
my $cache_info = `$wc_cmd`;
print CACHE_OUT "# This file was automatically generated by
# $script_name. Changes made to it will likely
# be lost. The format of this file is the same as the output
# of the below command:
#
#   $wc_cmd
#
$cache_info
";
close(CACHE_OUT);

# Send the email
my $mail_agent = "mail";
if ($send_email) {
    my $from    = "$script_name-no-reply\@open-mpi.org";
    my $to      = $email_arg;
    my $subject = "[Alert] Found server-side submit error messages\n";

    open(MAIL, "|$mail_agent $from -s \"$subject\" \"$to\"") or
        die "Could not open pipe to output e-mail\n";
    print MAIL "$email_body\n";
    close(MAIL);
}

exit;
