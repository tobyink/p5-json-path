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
    subkey1 => 'DO NOT WANT',
);

my %EXPRESSIONS = (
    '$.simple'                   => [ $data{simple} ],
    '$.long_hash.key1'           => [ dclone $data{long_hash}{key1} ],
    '$.long_hash.key1.subkey2'   => [ $data{long_hash}{key1}{subkey2} ],
    q{$.complex_array[0]['foo']} => [ $data{complex_array}[0]{foo} ],
    '$.*'                        => [ map { ref $_ ? dclone $_ : $_ } values %data ],
    '$.complex_array[?(@.type.code=="CODE_ALPHA")]' =>
        [ dclone( ( grep { $_->{type}{code} eq 'CODE_ALPHA' } @{ $data{complex_array} } )[0] ) ],
    '$.complex_array[?(@.weight > 10)]' => [ map { dclone $_ } grep { $_->{weight} > 10 } @{ $data{complex_array} } ],
    '$..foo' => [qw/bar baz bak/],
    '$.complex_array[?(@.weight > 10)].classification.quux' =>
        [ map { $_->{classification}{quux} } grep { $_->{weight} > 10 } @{ $data{complex_array} } ],
    '$..key2.subkey1' => ['2value1'],
    '$..complex_array[?(@.weight > 10)].classification.quux' =>
        [ map { $_->{classification}{quux} } grep { $_->{weight} > 10 } @{ $data{complex_array} } ],
        #    '$..classi

#    '$.[*].id'                                      => [qw/$ . [ * ] . id/],
#    q{$.[0].title}                                  => [qw/$ . [ 0 ] . title/],
#    q{$..labels[?(@.name==bug)]}                    => [qw/$ .. labels [?( @ . name == bug )]/],
#    q{$.store.book[(@.length-1)].title}             => [qw/$ . store . book [( @ . length-1 )] . title/],
#    q{$.store.book[?(@.price < 10)].title}          => [ qw/$ . store . book [?( @ . /, 'price ', '<', ' 10', qw/)] . title/ ],
#    q{$.store.book[?(@.price <= 10)].title}          => [ qw/$ . store . book [?( @ . /, 'price ', '<=', ' 10', qw/)] . title/ ],
#    q{$.store.book[?(@.price >= 10)].title}          => [ qw/$ . store . book [?( @ . /, 'price ', '>=', ' 10', qw/)] . title/ ],
#    q{$.store.book[?(@.price === 10)].title}          => [ qw/$ . store . book [?( @ . /, 'price ', '===', ' 10', qw/)] . title/ ],
#    q{$['store']['book'][0]['author']}              => [ '$', '[', q('store'), ']', '[', q('book'), ']', '[', 0, ']', '[', q('author'), ']' ],
#    q{$.[*].user[?(@.login == 'laurilehmijoki')]}   => [ qw/$ . [ * ] . user [?( @ ./,  'login ', '==',  q{ 'laurilehmijoki'}, ')]' ],
);

for my $expression ( keys %EXPRESSIONS ) {
    is_deeply(
        [ JSON::Path::Compiler::evaluate( dclone \%data, $expression ) ],
        $EXPRESSIONS{$expression},
        qq{"$expression" evaluated correctly}
    );
}

done_testing;
