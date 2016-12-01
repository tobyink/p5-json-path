use 5.016;

use Test::Most;
use JSON::Path::Compiler;
use Storable qw(dclone);
use Tie::IxHash;

tie my %data, 'Tie::IxHash', (
    simple    => 'Simple',
    hash      => { key => 'value' },
    long_hash => {
        key1 => {
            subkey1 => '1value1',
            subkey2 => '1value2',
            subkey3 => { subsubkey1 => '1value11', subsubkey2 => '1value12' }
        },
        key2 => {
            subkey1 => '2value1',
            subkey2 => '2value2',
            subkey3 => { subsubkey1 => '2value11', subsubkey2 => '2value12' }
        }
    },
    array         => [qw/alpha beta gamma/],
    complex_array => [
        {   type => {
                code => 'CODE_ALPHA',
                name => 'Alpha'
            },
            foo            => 'bar',
            classification => {
                quux => 'omega',
                quuy => 'omicron',
            },
            weight => 20,
            quux   => 1,
        },
        {   type => {
                code => 'CODE_BETA',
                name => 'Beta'
            },
            foo            => 'baz',
            classification => {
                quux => 'lambda',
                quuy => 'nu',
            },
            weight => 10,
            quux   => 0,

        },
        {   type => {
                code => 'CODE_GAMMA',
                name => 'Gamma'
            },
            foo            => 'bak',
            classification => {
                quux => 'eta',
                quuy => 'zeta',
            },
            weight => 30,

        }
    ],
    multilevel_array => [
        [ [qw/alpha beta gamma/], [qw/delta epsilon zeta/], ],
        [ [qw/eta theta iota/],   [qw/kappa lambda mu/], ],
    ],
    subkey1 => 'DO NOT WANT',
);

my %EXPRESSIONS = (
    '$.simple' => sub {
        my ( $refs, $obj ) = @_;
        my ($ref) = @{$refs};
        my $expected = int rand 1000;
        is ref $ref, 'SCALAR', q{Reftype OK};
        ${$ref} = $expected;
        is $obj->{simple}, $expected, q{Value OK};
    },
    '$.long_hash.key1' => sub {
        my ( $refs, $obj ) = @_;
        my ($ref) = @{$refs};
        is ref $ref, 'HASH', q{Reftype OK};
        my $key = sprintf 'abc%d', int rand 1000;
        $ref->{$key} = 'foo';
        is $obj->{long_hash}{key1}{$key}, 'foo', q{Value OK};
    },
    '$.long_hash.key1.subkey2' => sub {
        my ( $refs, $obj ) = @_;
        my ($ref) = @{$refs};
        my $expected = int rand 1000;
        is ref $ref, 'SCALAR', q{Reftype OK};
        ${$ref} = $expected;
        is $obj->{long_hash}{key1}{subkey2}, $expected, q{Value OK};
    },
    '$.complex_array[?(@.type.code=="CODE_ALPHA")]' => sub {
        my ( $refs, $obj ) = @_;
        my ($ref) = @{$refs};

        is ref $ref, 'HASH', q{reftype OK};
        my $key = sprintf 'abc%d', int rand 1000;
        $ref->{$key} = 'foo';
        my ($code_alpha) = grep { $_->{type}{code} eq 'CODE_ALPHA' } @{ $obj->{complex_array} };
        is $ref->{$key}, $code_alpha->{$key}, q{Value OK};
    },
    '$.complex_array[?(@.quux)]' => sub {
        my ( $refs, $obj ) = @_;
        my @expected_refs = grep { $_->{quux} } @{ $obj->{complex_array} };
        for ( 0 .. $#{$refs} ) {
            my $ref = $refs->[$_];
            is ref $ref, 'HASH', qq{Reftype $_ OK};

            my $key = sprintf 'abc%d', int rand 1000;
            $ref->{$key} = 'foo';
            is $expected_refs[$_]->{$key}, 'foo', q{Value OK};
        }
    },
    '$..foo' => sub {
        my ( $refs, $obj ) = @_;
        for ( 0 .. $#{$refs} ) {
            my $ref      = $refs->[$_];
            my $expected = int rand 1000;
            is ref $ref, 'SCALAR', qq{Reftype $_ OK};
            ${$ref} = $expected;
            is $obj->{complex_array}[$_]{foo}, $expected, qq{Value $_ OK};
        }
    },
    '$.nonexistent' => sub {
        my ( $refs, $obj ) = @_;
        is scalar @{$refs}, 0, 'Nonexistent path gives nothing back';
    },
    '$..nonexistent' => sub {
        my ( $refs, $obj ) = @_;
        is scalar @{$refs}, 0, 'Nonexistent path gives nothing back';
    },
    '$.multilevel_array.1.0.0'    => sub { 
        my ($refs, $obj) = @_;
        my ($ref) = @{$refs};
        my $expected = int rand 1000;
        is ref $ref, 'SCALAR', q{Reftype OK};
        ${$ref} = $expected;
        is $obj->{multilevel_array}[1][0][0], $expected, q{Value OK};
    }
);

for my $expression ( keys %EXPRESSIONS ) {
    my $obj = dclone( \%data );
    my (@refs) = JSON::Path::Compiler::evaluate( $obj, $expression, 1 );
    my $test = $EXPRESSIONS{$expression};
    subtest $expression => sub { $test->( \@refs, $obj ); };
}

done_testing;
