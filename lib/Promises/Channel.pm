package Promises::Channel;
# ABSTRACT: a thing

use strict;
use warnings;
use Promises qw(deferred);

sub new {
  my ($class, %param) = @_;

  bless {
    inbox    => [],
    outbox   => [],
    shutdown => 0,
  }, $class;
}

sub DESTROY {
  my $self = shift;
  $self->shutdown;
}

sub shutdown {
  my $self = shift;
  $self->{shutdown} = 1;
  $self->drain;
}

sub is_shutdown {
  my $self = shift;
  $self->{shutdown};
}

sub size {
  my $self = shift;
  scalar @{ $self->{inbox} };
}

sub put {
  my $self = shift;
  push @{ $self->{inbox} }, @_;
  $self->drain;
  $self->size;
}

sub get {
  my $self = shift;
  my $soon = deferred;
  push @{ $self->{outbox} }, $soon;
  $self->drain;
  $soon->promise;
}

sub drain {
  my $self = shift;

  while (@{ $self->{inbox} } && @{ $self->{outbox} }) {
    my $soon = shift @{ $self->{outbox} };
    my $msg  = shift @{ $self->{inbox} };
    $soon->resolve($msg);
  }

  if ($self->is_shutdown) {
    while (@{ $self->{outbox} }) {
      my $soon = shift @{ $self->{outbox} };
      $soon->resolve(undef);
    }
  }

  return;
}

1;
