package Promises::Channel::Merged;
# ABSTRACT: A combined channel composed of multiple input sources

=head1 SYNOPSIS

  use Promises::Channel qw(merge chan);

  my $foos = chan;
  my $bars = chan;
  my $chan = merged $foos, $bars;

  $foos->put('foo');
  $bars->put('bar');

  $chan->get->then(sub {
    my ($src, $item) = @_;
    # $src is $foos
    # $item is 'foo'
  });

  $chan->get->then(sub {
    my ($src, $item) = @_;
    # $src is $bars
    # $item is 'bar'
  });

  $chan->shutdown; # both $foos and $bars are now shut down

=head1 DESCRIPTION

A L<Promises::Channel> which merges the output of one or more other
L<Promises::Channel> objects. The merged channel will continually draw
items from its source channels; those items are then available via the
merged channel's own C<get> method.

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

Adds a new channel to the merged channel's set of input sources. The new
channel will immediately begin feeding the merged channel, up to channels
C<limit>.

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

=head1 NOTES AND CAVEATS

=over

=item Input channels may be added to running merged channels

However, an input channel will only be removed once it has been closed by an
external factor. Even then, it will only be removed once it has been fully
drained.

=item Input channels do not prevent other callers from using get()

Any items retrieved from an input channel by an outside caller will not be
available to the merged channel.

=item A merged channel allows new entries using put() from outside sources

A merged channel is a normal channel and may accept inputs from any source in
addition to the input sources defined. There is no restriction on calling
C<put> or any other method of L<Promises::Channel> on a merged channel.

=back

=cut

1;
