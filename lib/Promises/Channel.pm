package Promises::Channel;
# ABSTRACT: a coordination channel implemented with Promises

=head1 SYNOPSIS

  # See notes about recursion in Promises::Cookbook::Recursion
  use Promises backend => ['AE'], 'deferred';
  use Promises::Channel qw(channel);

  my $channel = channel
    limit => 4;


  # Use $channel to invert control on an AnyEvent::Handle
  $ae_handle->on_read(sub {
    my $handle = shift;

    $handle->push_read(line => sub {
      my ($handle, $line) = @_;
      $channel->put($line);
    });
  });

  $ae_handle->on_error(sub {
    $channel->shutdown;
  });

  my $depleted = 0;
  $channel->on_shutdown
    ->then(sub { $depleted = 1 });

  sub reader {
    my ($channel, $line) = @_;
    do_stuff $line;

    # Queue the next read, using done to avoid recursion
    $channel->get->done(\&reader);
  }

  $channel->get->then(\&reader);

=head1 DESCRIPTION

A C<Promises::Channel> is a FIFO queue that produces L<Promises::Promise>s
which resolve to the items added to the queue.

=cut

use strict;
use warnings;

use Moo;
use Promises qw(deferred);

extends 'Exporter';

our @EXPORT_OK = qw(
  channel
  chan
);


=head1 ATTRIBUTES

=head2 limit

Sets an upper boundary on the number of items which may be queued at a time. If
this limit is reached, the promise returned by the next call to L</put> will
not be resolved until there has been a corresponding call to L</get> (or the
channel has been L</shutdown>.

=cut

has limit =>
  is        => 'ro',
  predicate => 'has_limit';

=head2 is_shutdown

Returns true if the channel has been shutdown. The channel will be
automatically shutdown and drained when demolished.

=cut

has shutdown_signal =>
  is      => 'ro',
  default => sub { deferred },
  handles => {
    is_shutdown => 'is_done',
  };

has backlog =>
  is      => 'ro',
  default => sub { [] };

has inbox =>
  is      => 'ro',
  default => sub { [] };

has outbox =>
  is      => 'ro',
  default => sub { [] };

=head1 METHODS

=head2 size

Returns the number of items in the queue. This number is not adjusted to
reflect any queued waiters.

=cut

sub size {
  my $self = shift;
  scalar @{ $self->inbox };
}

=head2 is_full

If a L</limit> has been set, returns true if the channel is full and cannot
immediately accept new items.

=cut

sub is_full {
  my $self = shift;
  return $self->has_limit
      && $self->size == $self->limit;
}

=head2 is_empty

Returns true if there are no items in the queue and there are no pending
deliveries of items from deferred L</put>s.

=cut

sub is_empty {
  my $self = shift;
  return $self->size == 0
      && !@{ $self->backlog };
}

=head2 put

Adds one or more items to the channel and returns a L<Promises::Promise> that
will resolve to the channel instance after the item has been added (which may
be deferred if L</limit> has been set).

=cut

sub put {
  my ($self, $item) = @_;
  my $soon = deferred;

  my $promise = $soon->promise->then(sub {
    $self->drain;
    return $self;
  });

  push @{ $self->backlog }, [$item, $soon];
  $self->pump;
  return $soon->promise;
}

=head2 get

Returns a L<Promises::Promise> which will resolve to the channel and the next
item queued in the channel.

  $chan->get->then(sub {
    my ($chan, $item) = @_;
    ...
  });

=cut

sub get {
  my $self = shift;
  my $soon = deferred;
  push @{ $self->outbox }, $soon;

  my $promise = $soon->promise->then(sub {
    my ($self, $item) = @_;
    $self->pump;
    return ($self, $item);
  });

  $self->drain;

  return $promise;
}

=head2 shutdown

Closes the queue. This does not prevent new items from being added. However,
future calls to L</get> will be resolved immediately with C<undef>. Any
previously deferred calls to get will be immediately resolved until the channel
is empty, after which any remaining deferrals will be resolved with C<undef>.

When the channel goes out of scope, it will be shutdown and drained
automatically.

=cut

sub shutdown {
  my $self = shift;
  $self->shutdown_signal->resolve
    unless $self->is_shutdown;
  $self->drain;
  $self->pump;
}

=head2 on_shutdown

Returns a promise which will be resolved after the channel has been shut down
and drained. As the channel is shut down when demolished, this promise will
be resolved when the channel goes out of scope as well.

=cut

sub on_shutdown {
  my $self = shift;
  return $self->shutdown_signal->promise;
}


sub pump {
  my $self = shift;

  while (@{ $self->backlog } && !$self->is_full) {
    my ($item, $soon) = @{ shift @{ $self->backlog } };
    push @{ $self->inbox }, $item;
    $soon->resolve($self->size);
  }
}

sub drain {
  my $self = shift;

  while (@{ $self->inbox } && @{ $self->outbox }) {
    my $soon = shift @{ $self->outbox };
    my $msg  = shift @{ $self->inbox };
    $soon->resolve($self, $msg);
  }

  if ($self->is_shutdown) {
    while (my $soon = shift @{ $self->outbox }) {
      $soon->resolve($self, undef);
    }
  }

  return;
}

sub DEMOLISH {
  my $self = shift;
  $self->shutdown;
}


=head1 EXPORTS

Nothing is exported by default.

=head2 chan

=head2 channel

Sugar for calling the default constructor. The following lines are equivalent.

  my $ch = chan;
  my $ch = channel;
  my $ch = Promises::Channel->new;

=cut

sub channel { Promises::Channel->new(@_) }
sub chan    { Promises::Channel->new(@_) }

=head1 CONTRIBUTORS

The following people have contributed to this module by supplying new features,
bug reports, or feature requests.

=over

=item Erik Huelsmann (EHUELS)

=back

=cut

1;
