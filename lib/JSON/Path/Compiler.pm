package JSON::Path::Compiler;

use 5.016;
use Carp;
use Readonly;
use Scalar::Util qw/looks_like_number blessed/;
use Storable qw/dclone/;
our $AUTHORITY = 'cpan:POPEFELIX';
our $VERSION   = '1.00';

our @TOKEN_STREAM;

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
Readonly my $EQUAL_SIGN           => '=';
Readonly my $EXCLAMATION_MARK     => '!';
Readonly my $GREATER_THAN_SIGN    => '>';
Readonly my $LESS_THAN_SIGN       => '<';

Readonly my $TOKEN_ROOT                => $DOLLAR_SIGN;
Readonly my $TOKEN_CURRENT             => $COMMERCIAL_AT;
Readonly my $TOKEN_CHILD               => $FULL_STOP;
Readonly my $TOKEN_RECURSIVE           => $FULL_STOP . $FULL_STOP;
Readonly my $TOKEN_ALL                 => $ASTERISK;
Readonly my $TOKEN_FILTER_OPEN         => $LEFT_SQUARE_BRACKET . $QUESTION_MARK . $LEFT_PARENTHESIS;
Readonly my $TOKEN_SCRIPT_OPEN         => $LEFT_SQUARE_BRACKET . $LEFT_PARENTHESIS;
Readonly my $TOKEN_FILTER_SCRIPT_CLOSE => $RIGHT_PARENTHESIS . $RIGHT_SQUARE_BRACKET;
Readonly my $TOKEN_SUBSCRIPT_OPEN      => $LEFT_SQUARE_BRACKET;
Readonly my $TOKEN_SUBSCRIPT_CLOSE     => $RIGHT_SQUARE_BRACKET;
Readonly my $TOKEN_UNION               => $COMMA;
Readonly my $TOKEN_ARRAY_SLICE         => $COLON;
Readonly my $TOKEN_SINGLE_EQUAL        => $EQUAL_SIGN;
Readonly my $TOKEN_DOUBLE_EQUAL        => $EQUAL_SIGN . $EQUAL_SIGN;
Readonly my $TOKEN_TRIPLE_EQUAL        => $EQUAL_SIGN . $EQUAL_SIGN . $EQUAL_SIGN;
Readonly my $TOKEN_GREATER_THAN        => $GREATER_THAN_SIGN;
Readonly my $TOKEN_LESS_THAN           => $LESS_THAN_SIGN;
Readonly my $TOKEN_NOT_EQUAL           => $EXCLAMATION_MARK . $EQUAL_SIGN;
Readonly my $TOKEN_GREATER_EQUAL       => $GREATER_THAN_SIGN . $EQUAL_SIGN;
Readonly my $TOKEN_LESS_EQUAL          => $LESS_THAN_SIGN . $EQUAL_SIGN;

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
    $EQUAL_SIGN           => 1,
    $EXCLAMATION_MARK     => 1,
    $GREATER_THAN_SIGN    => 1,
    $LESS_THAN_SIGN       => 1,
);

my %OPERATORS => (
    $TOKEN_ROOT                => 1,
    $TOKEN_CURRENT             => 1,
    $TOKEN_CHILD               => 1,
    $TOKEN_RECURSIVE           => 1,
    $TOKEN_ALL                 => 1,
    $TOKEN_FILTER_OPEN         => 1,
    $TOKEN_SCRIPT_OPEN         => 1,
    $TOKEN_FILTER_SCRIPT_CLOSE => 1,
    $TOKEN_SUBSCRIPT_OPEN      => 1,
    $TOKEN_SUBSCRIPT_CLOSE     => 1,
    $TOKEN_UNION               => 1,
    $TOKEN_ARRAY_SLICE         => 1,
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
    while ( defined( my $char = shift @chars ) ) {
        my $token = $char;
        if ( $RESERVED_SYMBOLS{$char} ) {
            if ( $char eq $FULL_STOP ) {    # distinguish between the '.' and '..' tokens
                my $next_char = shift @chars;
                if ( $next_char eq $FULL_STOP ) {
                    $token .= $next_char;
                }
                else {
                    unshift @chars, $next_char;
                }
            }
            elsif ( $char eq $LEFT_SQUARE_BRACKET ) {
                my $next_char = shift @chars;

                # $.addresses[?(@.addresstype.id == D84002)]

                if ( $next_char eq $LEFT_PARENTHESIS ) {
                    $token .= $next_char;
                }
                elsif ( $next_char eq $QUESTION_MARK ) {
                    $token .= $next_char;
                    my $next_char = shift @chars;
                    if ( $next_char eq $LEFT_PARENTHESIS ) {
                        $token .= $next_char;
                    }
                    else {
                        die qq{filter operator "$token" must be followed by '('\n};
                    }
                }
                else {
                    unshift @chars, $next_char;
                }
            }
            elsif ( $char eq $RIGHT_PARENTHESIS ) {
                my $next_char = shift @chars;
                no warnings qw/uninitialized/;
                die qq{Unterminated expression: '[(' or '[?(' without corresponding ')]'\n}
                unless $next_char eq $RIGHT_SQUARE_BRACKET;
                use warnings qw/uninitialized/;
                $token .= $next_char;
            }
            elsif ($char eq $EQUAL_SIGN ) { # Build '=', '==', or '===' token as appropriate
                my $next_char = shift @chars;
                if (!defined $next_char) { 
                    die qq{Unterminated comparison: '=', '==', or '===' without predicate\n};
                }
                if ($next_char eq $EQUAL_SIGN) {
                    $token .= $next_char;
                    $next_char = shift @chars;
                    if (!defined $next_char) { 
                        die qq{Unterminated comparison: '==' or '===' without predicate\n};
                    }
                    if ($next_char eq $EQUAL_SIGN) {
                        $token .= $next_char;
                    }
                    else { 
                        unshift @chars, $next_char;
                    }
                }
                else {
                    unshift @chars, $next_char;
                }
            }
            elsif ($char eq $LESS_THAN_SIGN || $char eq $GREATER_THAN_SIGN) {
                my $next_char = shift @chars;
                if (!defined $next_char) { 
                    die qq{Unterminated comparison: '=', '==', or '===' without predicate\n};
                }
                if ($next_char eq $EQUAL_SIGN) {
                    $token .= $next_char;
                }
                else { 
                    unshift @chars, $next_char;
                }
            }
        }
        else {
            # Read from the character stream until we have a valid token
            while ( defined( $char = shift @chars ) ) {
                if ( $RESERVED_SYMBOLS{$char} ) {
                    unshift @chars, $char;
                    last;
                }
                $token .= $char;
            }
        }
        push @tokens, $token;
    }

    return @tokens;
}

sub generate_code {
    my @tokens = reverse @_;

    #    $TOKEN_ROOT                => 1,
    #    $TOKEN_CURRENT             => 1,
    #    $TOKEN_CHILD               => 1,
    #    $TOKEN_RECURSIVE           => 1,
    #    $TOKEN_ALL                 => 1,
    #    $TOKEN_FILTER_OPEN         => 1,
    #    $TOKEN_SCRIPT_OPEN         => 1,
    #    $TOKEN_FILTER_SCRIPT_CLOSE => 1,
    #    $TOKEN_SUBSCRIPT_OPEN      => 1,
    #    $TOKEN_SUBSCRIPT_CLOSE     => 1,
    #    $TOKEN_UNION               => 1,
    #    $TOKEN_ARRAY_SLICE         => 1,

    my @stack;

    # TOKEN STREAM:
    # )] /login="laurilehmijoki"/ . @ [?( user .. $
    # )] /id == D84002/ . addresstype . @ [?( addresses . $
    # )] /name==bug/ . @ [?( labels .. $
    # )] length-1 . @ [( book .. $
    # author . * . book . store . $
    # title . 0 . book . store . $
    while ( defined( my $token = shift @tokens ) ) {
        if ( $OPERATORS{$token} ) {
        }
        if ( $token eq $TOKEN_ROOT ) {
            last;
        }
        elsif ( $token eq $TOKEN_CURRENT ) {

            # TODO
        }
        elsif ( $token eq $TOKEN_CHILD ) {

            # assumed
            next;
        }
        elsif ( $token eq $TOKEN_RECURSIVE ) {

            # TODO
        }
        elsif ( $token eq $TOKEN_FILTER_SCRIPT_CLOSE ) {
            my $is_filter;

            # )] /login="laurilehmijoki"/ . @ [?( user .. $
            # )] /id == D84002/ . addresstype . @ [?( addresses . $
            # )] /name==bug/ . @ [?( labels .. $
            # )] length-1 . @ [( book .. $
            my @filter = shift @tokens;

            while ( defined( $token = shift @tokens ) ) {
                if ( $token eq $TOKEN_FILTER_OPEN ) {
                    $is_filter = 1;
                    last;
                }
                elsif ( $token eq $TOKEN_SCRIPT_OPEN ) {
                    last;
                }
                unshift @filter, $token;
            }
            1;

            if ($is_filter) {
                my $expression = pop @filter;
                my ( $left, $operator, $right ) = (
                    $expression =~ m/
                    ([^=!>< ]+)\s*              # Match whatever is on the LHS (excluding operator symbols) and exclude spaces
                    (==|===|=|!=|!==|>|<|>=|<=) # JS boolean operator list
                    \s*([^=!>< ]+)              # Match whatever is on the RHS (excluding operator symbols) and exclude spaces
                    /x
                );
                1;
                push @filter, $left;

                # punt!
                my $condition;
                for my $token (@filter) {
                    if ( $token eq $TOKEN_CURRENT ) {
                        $condition .= '$_';
                    }
                    elsif ( $token eq $TOKEN_CHILD ) {
                        $condition .= '->';
                    }
                    elsif ( $OPERATORS{$token} ) {
                        die qq{Invalid token "$token" in filter expression "$expression"\n};
                    }
                    else {
                        $condition .= qq({$token});
                    }
                }
                if ( !looks_like_number($right) ) {
                    $operator = 'eq' if $operator =~ /^=/;
                    $operator = 'ne' if $operator =~ /^!/;
                    $operator = 'lt' if $operator eq '<';
                    $operator = 'gt' if $operator eq '>';
                    $operator = 'le' if $operator eq '<=';
                    $operator = 'ge' if $operator eq '>=';
                }
                else {
                    if ( $operator eq '===' ) {
                        $operator = 'eq';
                    }
                    elsif ( $operator eq '!==' ) {
                        $operator = 'ne';
                    }
                }
                $condition .= qq{ $operator $right};
                push @stack, sub {
                    my @items = ref $_[0] eq 'ARRAY' ? @{ $_[0] } : ( $_[0] );
                    eval qq{grep { $condition } \@items};
                };
                ## no critic
                ## use critic
                # grep { $_->{addresstype}{id} == ... }
            }
        }
        else {
            push @stack, sub {
                my @items = ref $_[0] eq 'ARRAY' ? @{ $_[0] } : ( $_[0] );
                map { $_->{$token} } @items;
            };
        }
    }
}

sub _hashlike {
    my $object = shift;
    return ( ref $object eq 'HASH' || ( blessed $object && $object->can('typeof') && $object->typeof eq 'HASH' ) );
}

sub _arraylike {
    my $object = shift;
    return ( ref $object eq 'ARRAY' || ( blessed $object && $object->can('typeof') && $object->typeof eq 'ARRAY' ) );
}

my $root;
sub walk_recursive { # This assumes that the token stream is syntactically valid
    my ($obj, $token_stream) = @_;

    $root ||= $obj;
    $token_stream ||= [];

    return $obj unless @{$token_stream};

    my @match;
    while (defined (my $token = shift @{$token_stream})) {
        next if $token eq $TOKEN_CURRENT;
        if ($token eq $TOKEN_ROOT) {
            push @match, walk_recursive($root, $token_stream);
        }
        elsif ($token eq $TOKEN_CURRENT) {
            #push @match, walk_recursive($obj, $token_stream);
        }
        elsif ($token eq $TOKEN_CHILD || $token eq $TOKEN_SUBSCRIPT_OPEN) {
            my $next_token = shift @{$token_stream};
            my $index;
            if ($next_token eq $TOKEN_SUBSCRIPT_OPEN) {
                $index = shift @{$token_stream};
                my $close = shift @{$token_stream};
            }
            else {
                $index = $next_token;
                if ($token eq $TOKEN_SUBSCRIPT_OPEN) {
                    $next_token = shift @{$token_stream};
                    unshift @{$token_stream}, $next_token unless $next_token eq $TOKEN_SUBSCRIPT_CLOSE;
                }
            }

            $index = normalize($index);
            if (_arraylike($obj)) {
                if ($index ne $TOKEN_ALL) {
                    return unless looks_like_number($index);
                    push @match, walk_recursive($obj->[$index], $token_stream); 
                }
                else { 
                    return map { walk_recursive($obj->[$_], dclone($token_stream)) } (0 .. $#{$obj});
                }
            }
            else { 
                confess qq{ASSERTION FAILED! Did not get a hashref, got "$obj"} unless _hashlike($obj);
                if ($index ne $TOKEN_ALL) {
                    push @match, walk_recursive($obj->{$index}, $token_stream);
                }
                else { 
                    return map { walk_recursive( $obj->{$_}, dclone($token_stream) ) } values %{$obj};
                }
            }
        }
        elsif ($token eq $TOKEN_FILTER_OPEN) { 
            my @sub_stream;
            # Build a stream of just the tokens between the filter open and close
            while (defined (my $token = shift @{$token_stream})) {
                last if $token eq $TOKEN_FILTER_SCRIPT_CLOSE;
                if ($token eq $TOKEN_CURRENT) { 
                    push @sub_stream, $token, $TOKEN_CHILD, $TOKEN_ALL;
                }
                else {
                    push @sub_stream, $token;
                }
            }
            # FIXME: what about [?(@.foo)] ? that's a valid filter
            my $rhs = pop @sub_stream;
            $rhs = normalize($rhs);
            
            my $operator = pop @sub_stream;
            my @lhs = walk_recursive( $obj, [ @sub_stream] );
            for ( 0 .. $#lhs ) {
                if (compare($operator, $lhs[$_], $rhs)) {
                    push @match, $obj->[$_];
                }
            }
        }
        elsif ($token eq $TOKEN_RECURSIVE) {
            my $index;
            my $next_token = shift @{$token_stream};
            if (_arraylike($obj)) {
                for (0 .. $#{$obj}) {
                    push @match, $obj->[$_] if $_ eq $index;
                }
            }
            else {
            }
        }
    }
    return @match;
}

sub _match_recursive { 
    my ($obj, $index) = @_;
    my @match;
    if (_arraylike($obj)) {
        for (0 .. $#{$obj}) {
            push @match, $obj->[$_] if $_ eq $index;
            push @match, _match_recursive($obj->[$_], $index);
        }
    }
    elsif (_hashlike($obj)) {
        push @match, $obj->{$index} if exists $obj->{$index};
        push @match, _match_recursive($_, $index) for values %{$obj};
    }
    return @match;
}

sub normalize {
    my $string = shift;
            
    # NB: Stripping spaces *before* stripping quotes allows the caller to quote spaces in an index.
    # So an index of 'foo ' will be correctly normalized as 'foo', but '"foo "' will normalize to 'foo '. 
    $string =~ s/\s+$//; # trim trailing spaces
    $string =~ s/^\s+//; # trim leading spaces
    $string =~ s/^['"](.+)['"]$/$1/; # Strip quotes from index
    return $string;
}

sub compare {
    my ($operator, $lhs, $rhs) = @_;

    my $use_numeric = looks_like_number($lhs) && looks_like_number($rhs);
    
    if ($operator eq '=' || $operator eq '==' || $operator eq '===') {
        return $use_numeric ? ($lhs == $rhs) : $lhs eq $rhs;
    }
    if ($operator eq '<') {
        return $use_numeric ? ($lhs < $rhs) : $lhs lt $rhs;
    }
    if ($operator eq '>') {
        return $use_numeric ? ($lhs > $rhs) : $lhs gt $rhs;
    }
    if ($operator eq '<=') {
        return $use_numeric ? ($lhs <= $rhs) : $lhs le $rhs;
    }
    if ($operator eq '>=') {
        return $use_numeric ? ($lhs >= $rhs) : $lhs ge $rhs;
    }
    if ($operator eq '!=' || $operator eq '!==') { 
        return $use_numeric ? ($lhs != $rhs) : $lhs ne $rhs;
    }
}
1;
__END__
