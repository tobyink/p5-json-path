use Test::Most;
use JSON::Path;

my $orig = { bar => 1 };

my $p = JSON::Path->new("\$foo");

my $res = $p->get($orig);

is_deeply ( $orig, { bar => 1 }, "hashref is unchanged");

done_testing();
