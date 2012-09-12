use Test::More;
use Test::Pod::Coverage;

my @modules = qw(JSON::Path);
pod_coverage_ok($_, "$_ is covered") for @modules;
done_testing(scalar @modules);

