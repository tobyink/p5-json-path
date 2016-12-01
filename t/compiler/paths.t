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

# ok 1 - "$..foo" evaluated correctly
# ok 2 - "$.complex_array[?(@.quux)]" evaluated correctly
# ok 3 - "$.long_hash.key1" evaluated correctly
# ok 4 - "$.multilevel_array[0][1][0][0][0]" evaluated correctly
# ok 5 - "$.complex_array[0]['foo']" evaluated correctly
my @EXPRESSIONS = (
    '$.complex_array[?(@.type.code=="CODE_ALPHA")]' =>
        [ dclone( ( grep { $_->{type}{code} eq 'CODE_ALPHA' } @{ $data{complex_array} } )[0] ) ],
    '$.complex_array[?(@.weight > 10)]' => [ map { dclone $_ } grep { $_->{weight} > 10 } @{ $data{complex_array} } ],
    '$.complex_array[?(@.weight > 10)].classification.quux' =>
        [ map { $_->{classification}{quux} } grep { $_->{weight} > 10 } @{ $data{complex_array} } ],
    '$..complex_array[?(@.weight > 10)].classification.quux' =>
        [ map { $_->{classification}{quux} } grep { $_->{weight} > 10 } @{ $data{complex_array} } ],

    '$.*' => [ map { ref $_ ? dclone $_ : $_ } values %data ],
    '$.simple'                    => [ $data{simple} ],
    '$.long_hash.key1.subkey2'    => [ $data{long_hash}{key1}{subkey2} ],
    '$.complex_array[?(@.quux)]'  => [ grep { $_->{quux} } @{ $data{complex_array} } ],
    '$..key2.subkey1'             => ['2value1'],
    '$.long_hash.key1'            => [ dclone $data{long_hash}{key1} ],
    q{$.complex_array[0]['foo']}  => [ $data{complex_array}[0]{foo} ],
    '$..foo'                      => [qw/bar baz bak/],
    '$.multilevel_array.1.0.0'    => [ $data{multilevel_array}->[1][0][0] ],
    '$.multilevel_array.0.1[0]'   => [ $data{multilevel_array}->[0][1][0] ],
    '$.multilevel_array[0][0][1]' => [ $data{multilevel_array}->[0][0][1] ],
    '$.nonexistent'               => [],
    '$..nonexistent'              => [],
);

while ( my $expression = shift @EXPRESSIONS ) {
    my $expected = shift @EXPRESSIONS;
    lives_and {
        is_deeply( [ JSON::Path::Compiler::evaluate( dclone \%data, $expression ) ], $expected, )
    }
    qq{"$expression" evaluated correctly};
}

done_testing;
