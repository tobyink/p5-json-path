package JSON::Path::Compiler;

use 5.016;
use Carp;
use Carp::Assert qw(assert);
use JSON::Path::Constants qw(:operators);
use JSON::Path::Tokenizer qw(tokenize);
use Readonly;
use Scalar::Util qw/looks_like_number blessed/;
use Storable qw/dclone/;
use Sys::Hostname qw/hostname/;
our $AUTHORITY = 'cpan:POPEFELIX';
our $VERSION   = '1.00';

my $ASSERT_ENABLE =
    defined $ENV{ASSERT_ENABLE} ? $ENV{ASSERT_ENABLE} : hostname =~ /^lls.+?[.]cb[.]careerbuilder[.]com/;

sub _new {
    my $class = shift;
    my %args  = ref $_[0] eq 'HASH' ? %{ $_[0] } : @_;
    my $self  = {};
    $self->{root} = $args{root};
    bless $self, $class;
    return $self;
}

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
    $TOKEN_SINGLE_EQUAL        => 1,
    $TOKEN_DOUBLE_EQUAL        => 1,
    $TOKEN_TRIPLE_EQUAL        => 1,
    $TOKEN_GREATER_THAN        => 1,
    $TOKEN_LESS_THAN           => 1,
    $TOKEN_NOT_EQUAL           => 1,
    $TOKEN_GREATER_EQUAL       => 1,
    $TOKEN_LESS_EQUAL          => 1,
);

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

sub _hashlike {
    my $object = shift;
    return ( ref $object eq 'HASH' || ( blessed $object && $object->can('typeof') && $object->typeof eq 'HASH' ) );
}

sub _arraylike {
    my $object = shift;
    return ( ref $object eq 'ARRAY' || ( blessed $object && $object->can('typeof') && $object->typeof eq 'ARRAY' ) );
}

sub evaluate {
    my ( $json_object, $expression ) = @_;

    my $self = __PACKAGE__->_new( root => $json_object );
    return $self->_evaluate( $json_object, [ tokenize($expression) ] );
}

sub _evaluate {    # This assumes that the token stream is syntactically valid
    my ( $self, $obj, $token_stream ) = @_;

    $token_stream ||= [];

    return $obj unless @{$token_stream};

    while ( defined( my $token = get_token($token_stream) ) ) {
        next                                       if $token eq $TOKEN_CURRENT;
        next                                       if $token eq $TOKEN_CHILD;
        assert( $token ne $TOKEN_SUBSCRIPT_OPEN )  if $ASSERT_ENABLE;
        assert( $token ne $TOKEN_SUBSCRIPT_CLOSE ) if $ASSERT_ENABLE;
        if ( $token eq $TOKEN_ROOT ) {
            return $self->_evaluate( $self->{root}, $token_stream );
        }
        elsif ( $token eq $TOKEN_FILTER_OPEN ) {
            my @sub_stream;

            # Build a stream of just the tokens between the filter open and close
            while ( defined( my $token = shift @{$token_stream} ) ) {
                last if $token eq $TOKEN_FILTER_SCRIPT_CLOSE;
                if ( $token eq $TOKEN_CURRENT ) {
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

            # Evaluate the left hand side of the comparison first
            my @lhs = $self->_evaluate( $obj, [@sub_stream] );

            # FIXME: What if $obj is not an array?
            # Evaluate the token stream on all elements that pass the comparison in compare()
            my @ret = map { $self->_evaluate( $obj->[$_], dclone($token_stream) ) }
                grep { compare( $operator, $lhs[$_], $rhs ) } ( 0 .. $#lhs );    # returns indexes that pass compare()
            return @ret;
        }
        elsif ( $token eq $TOKEN_RECURSIVE ) {
            my $index = get_token($token_stream);
            my @ret = map { $self->_evaluate( $_, dclone($token_stream) ) } _match_recursive( $obj, $index );
            return @ret;
        }
        else {
            assert( !$OPERATORS{$token}, qq{"$token" is not an operator} );

            my $index = $token;

            $index = normalize($index);
            if ( _arraylike($obj) ) {
                if ( $index ne $TOKEN_ALL ) {
                    return unless looks_like_number($index);
                    return $self->_evaluate( $obj->[$index], $token_stream );
                }
                else {
                    return map { $self->_evaluate( $obj->[$_], dclone($token_stream) ) } ( 0 .. $#{$obj} );
                }
            }
            else {
                assert( _hashlike($obj) ) if $ASSERT_ENABLE;
                if ( $index ne $TOKEN_ALL ) {
                    return $self->_evaluate( $obj->{$index}, $token_stream );
                }
                else {
                    return map { $self->_evaluate( $_, dclone($token_stream) ) } values %{$obj};
                }
            }
        }
    }
}

sub get_token {
    my $token_stream = shift;
    my $token        = shift @{$token_stream};
    return unless $token;

    if ( $token eq $TOKEN_SUBSCRIPT_OPEN ) {
        my $next_token = shift @{$token_stream};
        my $close      = shift @{$token_stream};
        assert( $close eq $TOKEN_SUBSCRIPT_CLOSE ) if $ASSERT_ENABLE;
        return $next_token;
    }
    return $token;
}

sub _match_recursive {
    my ( $obj, $index ) = @_;
    my @match;
    if ( _arraylike($obj) ) {
        for ( 0 .. $#{$obj} ) {
            push @match, $obj->[$_] if $_ eq $index;
            push @match, _match_recursive( $obj->[$_], $index );
        }
    }
    elsif ( _hashlike($obj) ) {
        push @match, $obj->{$index} if exists $obj->{$index};
        push @match, _match_recursive( $_, $index ) for values %{$obj};
    }
    return @match;
}

sub normalize {
    my $string = shift;

    # NB: Stripping spaces *before* stripping quotes allows the caller to quote spaces in an index.
    # So an index of 'foo ' will be correctly normalized as 'foo', but '"foo "' will normalize to 'foo '.
    $string =~ s/\s+$//;                # trim trailing spaces
    $string =~ s/^\s+//;                # trim leading spaces
    $string =~ s/^['"](.+)['"]$/$1/;    # Strip quotes from index
    return $string;
}

sub compare {
    my ( $operator, $lhs, $rhs ) = @_;

    my $use_numeric = looks_like_number($lhs) && looks_like_number($rhs);

    if ( $operator eq '=' || $operator eq '==' || $operator eq '===' ) {
        return $use_numeric ? ( $lhs == $rhs ) : $lhs eq $rhs;
    }
    if ( $operator eq '<' ) {
        return $use_numeric ? ( $lhs < $rhs ) : $lhs lt $rhs;
    }
    if ( $operator eq '>' ) {
        return $use_numeric ? ( $lhs > $rhs ) : $lhs gt $rhs;
    }
    if ( $operator eq '<=' ) {
        return $use_numeric ? ( $lhs <= $rhs ) : $lhs le $rhs;
    }
    if ( $operator eq '>=' ) {
        return $use_numeric ? ( $lhs >= $rhs ) : $lhs ge $rhs;
    }
    if ( $operator eq '!=' || $operator eq '!==' ) {
        return $use_numeric ? ( $lhs != $rhs ) : $lhs ne $rhs;
    }
}
1;
__END__
