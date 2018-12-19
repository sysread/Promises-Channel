package Promises::Channel;
# ABSTRACT: a coordination channel implemented with Promises

=head1 SYNOPSIS

  use Promises::Channel;

  my $ch = chan;

  my $soon = $ch->get->then(sub {
    my $item = shift;
    do_stuff $item;
  });

  $ch->put('fnord');

=head1 DESCRIPTION

=cut

use strict;
use warnings;

use Moo;
use Promises qw(deferred);

extends 'Exporter';

our @EXPORT_OK = qw(chan);


has inbox =>
  is => 'ro',
  default => sub { [] };

has outbox =>
  is => 'ro',
  default => sub { [] };

has is_shutdown =>
  is => 'ro',
  default => 0;


=head1 METHODS

=cut

sub DEMOLISH {
  my $self = shift;
  $self->shutdown;
}

=head2 size

Returns the number of items in the queue. This number is not adjusted to
reflect any queued waiters.

=cut

sub size {
  my $self = shift;
  scalar @{ $self->inbox };
}

=head2 put

Adds one or more items to the channel. Returns the new size of the channel
after any deferred calls to L</get> are resolved.

=cut

sub put {
  my $self = shift;
  push @{ $self->inbox }, @_;
  $self->drain;
  $self->size;
}

=head2 get

Returns a L<Promises::Promise> which will resolve to the next item queued in
the channel.

=cut

sub get {
  my $self = shift;
  my $soon = deferred;
  push @{ $self->outbox }, $soon;
  $self->drain;
  $soon->promise;
}

=head2 shutdown

Closes the queue. This does not prevent new items from being added. However,
future calls to L</get> will be resolved immediately with C<undef>. Any
previously deferred calls to get will be immediately resolved until the channel
is empty, after which any remaining deferrals will be resolved with C<undef>.

When the channel goes out of scope, it will be shutdown and drained
automatically.

=head2 is_shutdown

Returns true if the channel has been shutdown.

=cut

sub shutdown {
  my $self = shift;
  $self->{is_shutdown} = 1;
  $self->drain;
}

sub drain {
  my $self = shift;

  while (@{ $self->inbox } && @{ $self->outbox }) {
    my $soon = shift @{ $self->outbox };
    my $msg  = shift @{ $self->inbox };
    $soon->resolve($msg);
  }

  if ($self->is_shutdown) {
    while (@{ $self->outbox }) {
      my $soon = shift @{ $self->outbox };
      $soon->resolve(undef);
    }
  }

  return;
}

=head1 EXPORTS

=head2 chan

Sugar for calling the default constructor. The following lines are equivalent.

  my $ch = chan;

  my $ch = Promises::Channel->new;  

=cut

sub chan {
  Promises::Channel->new(@_);
}

1;
