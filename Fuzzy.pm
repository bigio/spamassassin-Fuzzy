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

=head1 NAME

Fuzzy - checks fuzzy body signature

=head1 SYNOPSIS

  loadplugin    Mail::SpamAssassin::Plugin::Fuzzy

=head1 DESCRIPTION

This plugin checks emails body against a list of email body signatures

=cut

package Mail::SpamAssassin::Plugin::Fuzzy;

use strict;
use warnings;

use Digest::ssdeep qw/ssdeep_compare ssdeep_hash/;
use List::Util qw( max );
use Redis;

use Mail::SpamAssassin::Plugin;
use Mail::SpamAssassin::PerMsgStatus;
use Mail::SpamAssassin::Util qw(untaint_var);

use vars qw(@ISA);
@ISA = qw(Mail::SpamAssassin::Plugin);

my $VERSION = 0.1;

sub dbg { my $msg = shift; Mail::SpamAssassin::Plugin::dbg("Fuzzy: $msg", @_); }

sub new {
  my $class = shift;
  my $mailsaobject = shift;

  $class = ref($class) || $class;
  my $self = $class->SUPER::new($mailsaobject);
  bless ($self, $class);

  $self->set_config($mailsaobject->{conf});
  $self->register_eval_rule('fuzzy_check_100',  $Mail::SpamAssassin::Conf::TYPE_BODY_EVALS);
  $self->register_eval_rule('fuzzy_check_90_100',  $Mail::SpamAssassin::Conf::TYPE_BODY_EVALS);
  $self->register_eval_rule('fuzzy_check_80_90',  $Mail::SpamAssassin::Conf::TYPE_BODY_EVALS);

  return $self;
}

=head1 SYNOPSIS

=over 4

loadplugin Mail::SpamAssassin::Plugin::Fuzzy Fuzzy.pm

ifplugin Mail::SpamAssassin::Plugin::Fuzzy

  body            FUZZY100        eval:fuzzy_check_100()
  describe        FUZZY100        Message body present in body signature database

  body            FUZZY90_100     eval:fuzzy_check_90_100()
  describe        FUZZY90_100     Message body present in body signature database

endif

  fuzzy_check_100()
    Calculate the signature of the email body and check if it's spam

=back

=cut

sub set_config {
  my ($self, $conf) = @_;
  my @cmds = ();

=over 4

=item fuzzy_redis_srv (default: 127.0.0.1:6379)

Set the Redis server from where to read fuzzy hashes.

=back

=cut

  push(@cmds, {
    setting => 'fuzzy_redis_srv',
    default => '127.0.0.1:6379',
    type => $Mail::SpamAssassin::Conf::CONF_TYPE_STRING,
  });

=over 4

=item fuzzy_redis_db (default: 1)

Set the Redis database to use.

=back

=cut

  push(@cmds, {
    setting => 'fuzzy_redis_db',
    default => 1,
    type => $Mail::SpamAssassin::Conf::CONF_TYPE_NUMERIC,
  });

  $conf->{parser}->register_commands(\@cmds);
}

sub parsed_metadata {
  my ($self, $opts) = @_;

  _check_fuzzy($self, $opts->{permsgstatus});
}

sub fuzzy_check_100 {
  my ($self, $pms) = @_;

  return 0 if not defined $pms->{fuzzy_score};
  if($pms->{fuzzy_score} eq 100) {
    return 1;
  } else {
    return 0;
  }
}

sub fuzzy_check_90_100 {
  my ($self, $pms) = @_;

  return 0 if not defined $pms->{fuzzy_score};
  if(($pms->{fuzzy_score} > 90) and ($pms->{fuzzy_score} < 100)) {
    return 1;
  } else {
    return 0;
  }
}

sub fuzzy_check_80_90 {
  my ($self, $pms) = @_;

  return 0 if not defined $pms->{fuzzy_score};
  if(($pms->{fuzzy_score} > 80) and ($pms->{fuzzy_score} < 90)) {
    return 1;
  } else {
    return 0;
  }
}

sub _check_fuzzy {
  my ($self, $pms) = @_;

  my ($textbody, $body);
  foreach my $part ($pms->{msg}->find_parts(qr/./, 1)) {
    if($part->{type} eq 'text/html') {
      $body .= $part->decode;
    } elsif($part->{type} eq 'text/plain') {
      $textbody .= $part->decode;
    }
  }

  if(defined $body) {
    $body =~ s/=$//gms;
    # remove newlines
    $body =~ s/\R//g;
    # remove href links if there is a parameter on the link
    $body =~ s/((?:href|src)[^>]*)[?#][^>]*>/$1/gms;
  } elsif(not defined $body) {
    $body = $textbody;
  }

  my ($hash, $hex);
  if(defined $body) {
    $hash = ssdeep_hash($body);
    dbg("Calculated hash: $hash");
  }

  return 0 if not defined $hash;

  my @res;
  my $score = 0;
  my %match;
  if(defined $pms->{conf}->{fuzzy_redis_srv}) {
    my $redis_srv = untaint_var($pms->{conf}->{fuzzy_redis_srv});
    my $redis_db = untaint_var($pms->{conf}->{fuzzy_redis_db});

    my $redis = Redis->new(server => $redis_srv);
    $redis->select($redis_db);
    my @hash = split(':', $hash);
    my @keys = $redis->keys($hash[0] . ':*');
    foreach my $k ( @keys ) {
      $score = ssdeep_compare($hash, $k);
      push(@res, $score);
      $match{$score} = $k;
    }
    $redis->quit;
  }

  $pms->{fuzzy_score} = max @res;
  return 0 if not defined $pms->{fuzzy_score};

  dbg("Found a fuzzy score of $pms->{fuzzy_score} that matches hash $match{$score}");
  return 1;
}

1;
