use 5.016;

use Test::Most;
use JSON::Path::Compiler;

my %EXPRESSIONS = (
    q{$.[*].id}                                   => ['$', '.',     '[',            '*',    ']',    '.',    'id'],
    q{$.[0].title}                                => ['$', '.',     '[',            '0',    ']',    '.',    'title'],
    q{$..labels[?(@.name==bug)]}                  => ['$', '..',    'labels',       '[?(',  '@',    '.',    'name==bug',    ')]'],
    q{$.addresses[?(@.addresstype.id == D84002)]} => ['$', '.',     'addresses',    '[?(',  '@',    '.',    'addresstype',  '.',         'id == D84002', ')]'],
    q{$.store.book[(@.length-1)].title}           => ['$', '.',     'store',        '.',    'book', '[(',   '@',            '.',         'length-1',     ')]', '.',     'title'],
    q{$.store.book[?(@.price < 10)].title}        => ['$', '.',     'store',        '.',    'book', '[?(',  '@',            '.',         'price < 10',   ')]', '.',     'title'],
    q{$['store']['book'][0]['author']}            => ['$', '[',     'store',        ']',    '[',    'book', ']',            '[',         0,              ']', '[',      'author', ']'],
    q{$['store']['book'][1]['author']}            => ['$', '[',     'store',        ']',    '[',    'book', ']',            '[',         1,              ']', '[',      'author', ']'],
    q{$['store']['book'][2]['author']}            => ['$', '[',     'store',        ']',    '[',    'book', ']',            '[',         2,              ']', '[',      'author', ']'],
    q{$['store']['book'][3]['author']}            => ['$', '[',     'store',        ']',    '[',    'book', ']',            '[',         3,              ']', '[',      'author', ']'],
    q{$.[*].user[?(@.login == 'laurilehmijoki')]} => ['$', '.',     '[',            '*',    ']',    '.',    'user',         '[?(',       '@',             '.', q{login == 'laurilehmijoki'}, ')]'],
);

for my $expression (keys %EXPRESSIONS) {
    my @tokens;
    lives_and { is_deeply [ JSON::Path::Compiler::tokenize($expression) ], $EXPRESSIONS{$expression} } qq{Expression "$expression" tokenized correctly};
}

done_testing;
