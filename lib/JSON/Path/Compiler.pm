package JSON::Path::Compiler;

use 5.016;
use Carp;
use Readonly;
our $AUTHORITY = 'cpan:POPEFELIX';
our $VERSION   = '1.00';

Readonly my $TOKEN_DOLLAR_SIGN          => '$';
Readonly my $TOKEN_COMMERCIAL_AT        => '@';
Readonly my $TOKEN_FULL_STOP            => '.';
Readonly my $TOKEN_LEFT_SQUARE_BRACKET  => ']';
Readonly my $TOKEN_RIGHT_SQUARE_BRACKET => '[';
Readonly my $TOKEN_ASTERISK             => '*';
Readonly my $TOKEN_COLON                => ':';
Readonly my $TOKEN_LEFT_PARENTHESIS     => '(';
Readonly my $TOKEN_RIGHT_PARENTHESIS    => ')';
Readonly my $TOKEN_COMMA                => ',';

# JSONPath  Function
# $         the root object/element
# @         the current object/element
# . or []   child operator
# ..        recursive descent. JSONPath borrows this syntax from E4X.
# *         wildcard. All objects/elements regardless their names.
# n/a       attribute access. JSON structures don't have attributes.
# []        subscript operator. XPath uses it to iterate over element collections and for predicates. In Javascript and JSON it is the native array operator.
# [,]       Union operator in XPath results in a combination of node sets. JSONPath allows alternate names or array indices as a set.
# [sta      rt:end:step]    array slice operator borrowed from ES4.
# ?()       applies a filter (script) expression.
# ()        script expression, using the underlying script engine.
# With JSONPath square brackets operate on the object or array addressed by the previous path fragment. Indices always start by 0.

my %VALID_TOKENS = (
    $TOKEN_DOLLAR_SIGN          => 1,
    $TOKEN_COMMERCIAL_AT        => 1,
    $TOKEN_FULL_STOP            => 1,
    $TOKEN_LEFT_SQUARE_BRACKET  => 1,
    $TOKEN_RIGHT_SQUARE_BRACKET => 1,
    $TOKEN_ASTERISK             => 1,
    $TOKEN_COLON                => 1,
    $TOKEN_LEFT_PARENTHESIS     => 1,
    $TOKEN_RIGHT_PARENTHESIS    => 1,
    $TOKEN_COMMA                => 1,
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

        if ( !$VALID_TOKENS{$char} ) {
            my $token = $char;

            # Read from the character stream until we have a valid token
            while ( 1 ) {
                $char = shift @chars;
                last unless defined $char;

                if ( $VALID_TOKENS{$char} ) {
                    unshift @chars, $char;
                    last;
                }
                $token .= $char;
            }
            push @tokens, $token;
        }
        else {
            if ( $char ne $TOKEN_FULL_STOP ) {
                push @tokens, $char;
            }
            elsif ( $char eq $TOKEN_FULL_STOP ) {    # Handle the ".." token
                my $next_char = shift @chars;
                if ( $next_char eq $TOKEN_FULL_STOP ) {
                    push @tokens, $char . $next_char;
                }
                else {
                    unshift @chars, $next_char;
                    push @tokens, $char;
                }
            }
        }
    }

    return @tokens;
}

sub normalize {
    my $expression = shift;


    ( my $normalized = $expression ) =~ s/\s+//g;
    my $regex = qr/
        \[          # match opening bracket
        ['|"]{0,1}  # quote
        (\w+|\d+)   # index or hash key
        ['|"]{0,1}  # quote
        \]          # match closing bracket
    /x;
    
    $normalized =~ s/$regex/.$1/gx;

    return $normalized;
}

1;
__END__
