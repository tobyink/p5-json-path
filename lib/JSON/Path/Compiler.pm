package JSON::Path::Compiler;

use 5.016;
use Carp;
use Readonly;
our $AUTHORITY = 'cpan:POPEFELIX';
our $VERSION   = '1.00';

Readonly my $DOLLAR_SIGN          => '$';
Readonly my $COMMERCIAL_AT        => '@';
Readonly my $FULL_STOP            => '.';
Readonly my $LEFT_SQUARE_BRACKET  => '[';
Readonly my $RIGHT_SQUARE_BRACKET => ']';
Readonly my $ASTERISK             => '*';
Readonly my $COLON                => ':';
Readonly my $LEFT_PARENTHESIS     => '(';
Readonly my $RIGHT_PARENTHESIS    => ')';
Readonly my $COMMA                => ',';
Readonly my $QUESTION_MARK        => '?';

# JSONPath              Function
# $                     the root object/element
# @                     the current object/element
# . or []               child operator
# ..                    recursive descent. JSONPath borrows this syntax from E4X.
# *                     wildcard. All objects/elements regardless their names.
# []                    subscript operator. XPath uses it to iterate over element collections and for predicates. In Javascript and JSON it is the native array operator.
# [,]                   Union operator in XPath results in a combination of node sets. JSONPath allows alternate names or array indices as a set.
# [start:end:step]      array slice operator borrowed from ES4.
# ?()                   applies a filter (script) expression.
# ()                    script expression, using the underlying script engine.
#
# With JSONPath square brackets operate on the object or array addressed by the previous path fragment. Indices always start by 0.

my %RESERVED_SYMBOLS = (
    $DOLLAR_SIGN          => 1,
    $COMMERCIAL_AT        => 1,
    $FULL_STOP            => 1,
    $LEFT_SQUARE_BRACKET  => 1,
    $RIGHT_SQUARE_BRACKET => 1,
    $ASTERISK             => 1,
    $COLON                => 1,
    $LEFT_PARENTHESIS     => 1,
    $RIGHT_PARENTHESIS    => 1,
    $COMMA                => 1,
);

my @STACK;

# EXPRESSION                                    TOKENS
# $.[*].id                                      $ . [ * ] . id
# $.[0].title                                   $ . [ 0 ] . title
# $.[*].user[?(@.login == 'laurilehmijoki')]    $ . [ * ] . user [ ? ( @ . login =='laurilehmijoki' ) ]
# $..labels[?(@.name==bug)]                     $ .. labels [ ? ( @ . name ==bug ) ]
# $.addresses[?(@.addresstype.id == D84002)]    $ . addresses [ ? ( @ . addresstype . id ==D84002 ) ]
# $.store.book[(@.length-1)].title              $ . store . book [ ( @ . length -1 ) ] . title
# $.store.book[?(@.price < 10)].title           $ . store . book [ ? ( @ . price <10 ) ] . title
#
# $['store']['book'][0]['author']
# $['store']['book'][1]['author']
# $['store']['book'][2]['author']
# $['store']['book'][3]['author']
#

# Take an expression and break it up into tokens
sub tokenize {
    my $expression = shift;

    # $expression = normalize($expression);
    my @tokens;
    my @chars = split //, $expression;
    my $char;
    while (1) {
        my $char = shift @chars;
        last unless defined $char;

        if ( !$RESERVED_SYMBOLS{$char} ) {
            my $token = $char;

            # Read from the character stream until we have a valid token
            while (1) {
                $char = shift @chars;
                last unless defined $char;

                if ( $RESERVED_SYMBOLS{$char} ) {
                    unshift @chars, $char;
                    last;
                }
                $token .= $char;
            }
            $token =~ s/^['|"](.+)['|"]$/\1/;    # Remove quotes
            push @tokens, $token;
        }
        else {
            if ( $char eq $FULL_STOP ) {         # distinguish between the '.' and '..' tokens
                my $next_char = shift @chars;
                if ( $next_char eq $FULL_STOP ) {
                    push @tokens, $char . $next_char;
                }
                else {
                    unshift @chars, $next_char;
                    push @tokens, $char;
                }
            }
            elsif ( $char eq $LEFT_SQUARE_BRACKET ) {
                my $token     = $char;
                my $next_char = shift @chars;
                if ( $next_char eq $LEFT_PARENTHESIS ) {
                    $token .= $next_char;
                    push @tokens, $token;
                }
                elsif ( $next_char eq $QUESTION_MARK ) {
                    $token .= $next_char;
                    my $next_char = shift @chars;
                    if ( $next_char eq $LEFT_PARENTHESIS ) {
                        $token .= $next_char;
                        push @tokens, $token;
                    }
                    else {
                        die qq{filter operator "$token" must be followed by '('\n};
                    }
                }
                else {
                    unshift @chars, $next_char;
                    push @tokens, $token;
                }
            }
            elsif ( $char eq $RIGHT_PARENTHESIS ) {
                my $next_char = shift @chars;
                my $token     = $char;
                if ( $next_char eq $RIGHT_SQUARE_BRACKET ) {
                    $token .= $next_char;
                    push @tokens, $token;
                }
                else {
                    die qq{Unterminated expression: '[(' or '[?(' without corresponding ')]'\n};
                }
            }
            else {
                push @tokens, $char;
            }
        }
    }

    return @tokens;
}

# my %EXPRESSIONS = (
#     # map { $_->{id} } ITEMAT( $root, 'ALL' )
#     q{$.[*].id}                                   => ['$', '*', 'id'],
#
#     # map { $_->{id} } ITEMAT( $root, 0 )
#     q{$.[0].title}                                => ['$', '0', 'title'],
#
#     # grep { $_.login eq 'laurilehmijoki'}  map { $_->{user} } ITEMAT( $root, 'ALL' )
#     q{$.[*].user[?(@.login == 'laurilehmijoki')]} => ['$', '*', 'user',    'FILTER(', '@',  q{login == 'laurilehmijoki'}, ')'],
#
#     # map { $_->{title} } grep { $_.price < 10 } map { $_->{book} } map { $_->{store} } $root
#     q{$.store.book[?(@.price < 10)].title}        => ['$', 'store', 'book',  'FILTER(', '@', q{price < 10}, ')', 'title'],
#
#     # grep { $_->{name} eq 'bug' } RECURSIVE( { exists $_->{labels} }, $root )
#     q{$..labels[?(@.name==bug)]}                  => ['$', '..', 'labels',   'FILTER(', '@',  q{name==bug}, ')'],
#
#     # grep { $_->{addresstype}{id} eq "D84002" } map { $_->{addresses} } $root
#     q{$.addresses[?(@.addresstype.id == D84002)]} => ['$', 'addresses',      'FILTER(', '@', 'addresstype', q{id == D84002}, ')'],
#
#     # map { $_->{title} } ITEMAT( $_, length (@$_) - 1 )
#     q{$.store.book[(@.length-1)].title}           => ['$', 'store', 'book',  'SCRIPTENGINE(', '@', q{length-1}, ')', 'title'],
#
#     # map { $->{author} } ITEMAT( $_, 0 ) map { $_->{book} } map { $_->{store} } $root
#     q{$['store']['book'][0]['author']}            => ['$', 'store', 'book', '0', 'author'],
#
#     # map { $->{author} } ITEMAT( $_, 1 ) map { $_->{book} } map { $_->{store} } $root
#     q{$['store']['book'][1]['author']}            => ['$', 'store', 'book', '1', 'author'],
# );
sub normalize {
    my @tokens = @_;

    my @normalized;
    my @stack;

}

1;
__END__
