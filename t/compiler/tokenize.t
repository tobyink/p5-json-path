use 5.016;

use Test::Most;
use JSON::Path::Compiler;

my %EXPRESSIONS = (
    q{$.[*].id}                                   => [qw/$ . [ * ] . id/],
    q{$.[0].title}                                => [qw/$ . [ 0 ] . title/],
    q{$.[*].user[?(@.login == 'laurilehmijoki')]} => [qw/$ . [ * ] . user [ ? ( @ . /, q{login == 'laurilehmijoki'}, qw/) ]/],
    q{$..labels[?(@.name==bug)]}                  => [qw/$ .. labels [ ? ( @ . name==bug ) ]/],
    q{$.addresses[?(@.addresstype.id == D84002)]} => [qw/$ . addresses [ ? ( @ . addresstype . /, 'id == D84002', qw/) ]/],
    q{$.store.book[(@.length-1)].title}           => [qw/$ . store . book [ ( @ . length-1 ) ] . title/],
    q{$.store.book[?(@.price < 10)].title}        => [qw/$ . store . book [ ? ( @ ./,  'price < 10', qw/) ] . title/],
    q{$['store']['book'][0]['author']}            => [qw/$ [ 'store' ] [ 'book' ] [ 0 ] [ 'author' ]/],
    q{$['store']['book'][1]['author']}            => [qw/$ [ 'store' ] [ 'book' ] [ 1 ] [ 'author' ]/],
    q{$['store']['book'][2]['author']}            => [qw/$ [ 'store' ] [ 'book' ] [ 2 ] [ 'author' ]/],
    q{$['store']['book'][3]['author']}            => [qw/$ [ 'store' ] [ 'book' ] [ 3 ] [ 'author' ]/],
);

for my $expression (keys %EXPRESSIONS) {
    my @tokens = JSON::Path::Compiler::tokenize($expression);
    is_deeply \@tokens, $EXPRESSIONS{$expression}, qq{Expression "$expression" tokenized correctly};
}

done_testing;
