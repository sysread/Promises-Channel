use Test2::V0;
use Promises::Channel;

isa_ok my $ch = Promises::Channel->new, 'Promises::Channel';
is $ch->size, 0, 'size initially 0';
ok !$ch->is_shutdown, 'is_shutdown initially false';

for my $i (1 .. 10) {
  is $ch->put($i), $i, "put: $i";
  is $ch->size, $i, "size: $i";
}

for my $i (1 .. 10) {
  isa_ok my $item = $ch->get, 'Promises::Promise';

  $item->then(
    sub { is $_[0], $i, "get $i" },
    sub { ok 0, "get $i: @_" },
  );
}


$ch->get->then(
  sub { is $_[0], 42, 'get w/ no items' },
  sub { ok 0, "get w/ no items: @_" },
);

$ch->put(42);


$ch->shutdown;
ok $ch->is_shutdown, 'is_shutdown true after shutdown';

$ch->get->then(
  sub { is $_[0], U, 'get resolved with undef after shutdown' },
  sub { ok 0, 'get rejected after shutdown' },
);


done_testing;
