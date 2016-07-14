use 5.016;

use Test::Most;
use JSON::Path::Compiler;

my %EXPRESSIONS = (
    # map { $_->{id} } ITEMAT( $root, 'ALL' ) 
    q{$.[*].id}                                   => ['$', '*', 'id'], 
    
    # map { $_->{id} } ITEMAT( $root, 0 )
    q{$.[0].title}                                => ['$', '0', 'title'],

    # grep { $_.login eq 'laurilehmijoki'}  map { $_->{user} } ITEMAT( $root, 'ALL' )
    q{$.[*].user[?(@.login == 'laurilehmijoki')]} => ['$', '*', 'user',    'FILTER(', '@',  q{login == 'laurilehmijoki'}, ')'],

    # map { $_->{title} } grep { $_.price < 10 } map { $_->{book} } map { $_->{store} } $root 
    q{$.store.book[?(@.price < 10)].title}        => ['$', 'store', 'book',  'FILTER(', '@', q{price < 10}, ')', 'title'],

    # grep { $_->{name} eq 'bug' } RECURSIVE( { exists $_->{labels} }, $root ) 
    q{$..labels[?(@.name==bug)]}                  => ['$', '..', 'labels',   'FILTER(', '@',  q{name==bug}, ')'],

    # grep { $_->{addresstype}{id} eq "D84002" } map { $_->{addresses} } $root
    q{$.addresses[?(@.addresstype.id == D84002)]} => ['$', 'addresses',      'FILTER(', '@', 'addresstype', q{id == D84002}, ')'],

    # map { $_->{title} } ITEMAT( $_, length (@$_) - 1 ) 
    q{$.store.book[(@.length-1)].title}           => ['$', 'store', 'book',  'SCRIPTENGINE(', '@', q{length-1}, ')', 'title'],

    # map { $->{author} } ITEMAT( $_, 0 ) map { $_->{book} } map { $_->{store} } $root
    q{$['store']['book'][0]['author']}            => ['$', 'store', 'book', '0', 'author'],

    # map { $->{author} } ITEMAT( $_, 1 ) map { $_->{book} } map { $_->{store} } $root
    q{$['store']['book'][1]['author']}            => ['$', 'store', 'book', '1', 'author'],
);

for my $expression (keys %EXPRESSIONS) {
    my @tokens = JSON::Path::Compiler::tokenize($expression);
    my @normalized = JSON::Path::Compiler::normalize(@tokens);
    is_deeply \@normalized, $EXPRESSIONS{$expression}, qq{Expression "$expression" tokenized correctly};
}

done_testing;
