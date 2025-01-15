#!/bin/perl

# <@LICENSE>
#                   GNU GENERAL PUBLIC LICENSE
#                      Version 2, June 1991
#
# Copyright (C) 1989, 1991 Free Software Foundation, Inc.,
# 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA
# Everyone is permitted to copy and distribute verbatim copies
# of this license document, but changing it is not allowed.
# </@LICENSE>

# Author:  Giovanni Bechis <g.bechis@snb.it>

use strict;
use warnings;

use Encode qw(decode encode);
use Getopt::Std;
use JSON;
use MIME::Parser;
use MIME::Entity;
use Redis;

use Digest::ssdeep qw/ssdeep_hash/;

my %opts = ();
my ($file, $redis_srv, $redis, $min_score);
my $force = 0;

getopts('FS:f:s:', \%opts);

sub usage {
  print "$0 [ -F -S \$score -f \$file -s \$redis_srv ]\n";
  exit;
}

$file = $opts{f};
$redis_srv = $opts{s};
$min_score = $opts{S};
$min_score //= 5;

if($opts{'F'}) {
  $force = 1;
}

if(not defined $file) {
  usage;
}

if ( defined $redis_srv ) {
  # add a default port
  if($redis_srv !~ /\:/) {
    $redis_srv .= ':6379';
  }
}

if(not -f $file) {
  print "Cannot read email file\n";
  exit 255;
}

if(defined $redis_srv) {
  $redis = Redis->new(server => $redis_srv);
}

sub read_body {
  my ($body, $entity) = @_;

  if($entity->is_multipart) {
    foreach my $part ($entity->parts) {
      $body = read_body($body, $part);
    }
  } else {
    # consider only text/html part
    if($entity->mime_type eq 'text/html') {
      $body = $entity->bodyhandle->as_string;
    }
  }

  if(not defined $body) {
    if(defined $entity->bodyhandle) {
      $body = $entity->bodyhandle->as_string;
    } else {
      $body = $entity->body_as_string;
    }
  }

  # remove boundaries
  $body =~ s/^--.*$//gm;
  # remove newlines
  $body =~ s/=$//gms;
  $body =~ s/\R//g;
  # remove href links if there is a parameter on the link
  $body =~ s/((?:href|src)[^>]*)[?#][^>]*>/$1/gms;
  return $body;
}

my $parser = new MIME::Parser;
$parser->output_to_core(1);
my $entity = $parser->parse_open($file);
my $hspam = $entity->head->get('X-Spam-Status');
my $hsubj = $entity->head->get('Subject');

my $decoded_subject = decode("MIME-Header", $hsubj);
$hsubj = encode('utf-8', $decoded_subject);
$hsubj //= '';

my ($body, $hash);
$body = read_body($body, $entity);

my $score = 0;
if(defined $hspam and ($hspam =~ /(?:hits|score)=(\d+(?:\.\d+)?)\s+/)) {
  $score = $1;
}

my ($hex, $shash);
my @shash;
if(defined $body) {
  $hash = ssdeep_hash($body);
  @shash = split(/:/, $hash);
}

my %hash;
$hash{subject} = $hsubj;
$hash{score} = $score;

if(defined $redis_srv) {
  $redis->select(3);
  if(($score > 5) or $force) {
    $redis->set($hash => to_json(\%hash));
    # expire after 1 year
    $redis->expire($hash, 365 * 24 * 60 * 60);
  }
}

print to_json(\%hash);
if ( defined $redis_srv ) {
  if(($score > $min_score) or $force) {
    print " (saved to Redis)";
  }
}
print "\n";
