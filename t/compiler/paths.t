use Test::Most;
use Test::Deep;
use JSON::MaybeXS qw/encode_json decode_json/;
use JSON::Path::Compiler;
use Storable qw(dclone);
use Tie::IxHash;

my $json = sample_json();
my %data = %{ decode_json($json) };

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
    '$.store.book[0].title'       => [ $data{store}{book}->[0]{title} ],
    '$..book[-1:]'                => [ $data{store}{book}->[-1] ],
);

# my ($results2) = JSON::Path::Compiler->evaluate('$..book[-1:]', $object); 
# 
# is(ref $results2, 'HASH', "hashref value result");
# is($results2->{isbn}, "0-395-19395-8", "hashref seems to be correct");

while ( my $expression = shift @EXPRESSIONS ) {
    my $expected = shift @EXPRESSIONS;
    subtest $expression => sub {
        my @got;
        lives_ok {
            @got = JSON::Path::Compiler::evaluate( $json, $expression );
        }
        q{evaluate() did not die};

        cmp_bag( \@got, $expected, q{Expression evaluated correctly} );
    };
}

done_testing;

sub sample_json {

    my $data = <<END;
{
   "simple" : "Simple",
   "hash" : {
      "key" : "value"
   },
   "long_hash" : {
      "key1" : {
         "subkey1" : "1value1",
         "subkey2" : "1value2",
         "subkey3" : {
            "subsubkey1" : "1value11",
            "subsubkey2" : "1value12"
         }
      },
      "key2" : {
         "subkey1" : "2value1",
         "subkey2" : "2value2",
         "subkey3" : {
            "subsubkey1" : "2value11",
            "subsubkey2" : "2value12"
         }
      }
   },
   "array" : [
      "alpha",
      "beta",
      "gamma"
   ],
   "complex_array" : [
      {
         "quux" : 1,
         "weight" : 20,
         "classification" : {
            "quux" : "omega",
            "quuy" : "omicron"
         },
         "foo" : "bar",
         "type" : {
            "name" : "Alpha",
            "code" : "CODE_ALPHA"
         }
      },
      {
         "quux" : 0,
         "weight" : 10,
         "classification" : {
            "quux" : "lambda",
            "quuy" : "nu"
         },
         "foo" : "baz",
         "type" : {
            "name" : "Beta",
            "code" : "CODE_BETA"
         }
      },
      {
         "weight" : 30,
         "classification" : {
            "quux" : "eta",
            "quuy" : "zeta"
         },
         "foo" : "bak",
         "type" : {
            "name" : "Gamma",
            "code" : "CODE_GAMMA"
         }
      }
   ],
   "multilevel_array" : [
      [
         [
            "alpha",
            "beta",
            "gamma"
         ],
         [
            "delta",
            "epsilon",
            "zeta"
         ]
      ],
      [
         [
            "eta",
            "theta",
            "iota"
         ],
         [
            "kappa",
            "lambda",
            "mu"
         ]
      ]
   ],
   "subkey1" : "DO NOT WANT",
   "store" : {
		"book": [
			{
				"category": "reference",
				"author":   "Nigel Rees",
				"title":    "Sayings of the Century",
				"price":    8.95
			},
			{
				"category": "fiction",
				"author":   "Evelyn Waugh",
				"title":    "Sword of Honour",
				"price":    12.99
			},
			{
				"category": "fiction",
				"author":   "Herman Melville",
				"title":    "Moby Dick",
				"isbn":     "0-553-21311-3",
				"price":    8.99
			},
			{
				"category": "fiction",
				"author":   "J. R. R. Tolkien",
				"title":    "The Lord of the Rings",
				"isbn":     "0-395-19395-8",
				"price":    22.99
			}
		]
   }
}
END
    return $data;
}
