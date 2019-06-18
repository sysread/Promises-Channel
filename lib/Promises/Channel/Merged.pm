package Promises::Channel::Merged;
# ABSTRACT: A combined channel composed of multiple input sources

=head1 SYNOPSIS

  use Promises::Channel::Merged;

=head1 DESCRIPTION

=cut

use strict;
use warnings;

use Moo;
use Scalar::Util qw(refaddr);

extends 'Promises::Channel';

=head1 ATTRIBUTES

=head2 sources

A list of instances of L<Promises::Channel>. More may be added using L</add>,
but channels may only be removed by shutting them down; once shut down, they
will be removed once completely drained.

=cut

has sources =>
  is => 'ro',
  required => 1;

=head1 METHODS

=head2 add

Adds a new channel to the set of input sources.

=cut

sub add {
  my ($self, $ch) = @_;
  push @{ $self->sources }, $ch;
  $self->init_channel($ch);
}


#-------------------------------------------------------------------------------
# Set up the initial set of source channels
#-------------------------------------------------------------------------------
sub BUILD {
  my ($self, $args) = @_;
  $self->init_channel($_) for @{ $self->sources };
}

#-------------------------------------------------------------------------------
# Shutdown source channels when the merged channel itself is shut down.
#-------------------------------------------------------------------------------
after shutdown => sub{
  my $self = shift;
  $_->shutdown for @{ $self->sources };
};

#-------------------------------------------------------------------------------
# Initializes the output monitor loop for each source channel and adds a
# handler to remove the channel in case it is shutdown.
#-------------------------------------------------------------------------------
sub init_channel {
  my ($self, $ch) = @_;

  # Begin the channel's output loop.
  $self->_loop($ch);

  # If the channel is shut down, remove it from the source list.
  my $ref = refaddr $ch;
  $ch->on_shutdown->done(sub{
    $self->{sources} = [grep{ $ref ne refaddr $_ } @{ $self->sources }];
  });
}

#-------------------------------------------------------------------------------
# Retrieves the next item from a channel and posts it to this channel; if the
# channel is still alive (not shutdown) or it still has items queued, the loop
# will continue.
#-------------------------------------------------------------------------------
sub _loop {
  my ($self, $ch) = @_;

  $ch->get->done(sub{
    my ($ch, $item) = @_;
    $self->put($item);

    if (!$ch->is_shutdown || !$ch->is_empty) {
      $self->_loop($ch);
    }
  });
}

1;
