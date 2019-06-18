use Test2::V0;
use Promises qw(collect);
use Promises::Channel qw(chan merge);

my $ch1 = chan;
my $ch2 = chan;

ok my $ch = merge($ch1, $ch2), 'merge';

$ch1->put($_) for (1, 3, 5);
$ch2->put($_) for (2, 4, 6);

my @got;
my @soon = map{ $ch->get->then(sub{ push @got, $_[1] }) } 1..6;

collect(@soon)
  ->then(sub{ is [sort(@got)], [1..6], 'expected items delivered' })
  ->catch(sub{ ok 0, "get failed with: @_" });

$ch->shutdown;
ok $ch->is_shutdown, 'merged channel is shutdown';
ok $ch1->is_shutdown, 'source channel 1 is shutdown';
ok $ch2->is_shutdown, 'source channel 2 is shutdown';

done_testing;
