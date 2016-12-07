package JSON::Path::Evaluator;

use strict;
use warnings;
use 5.008;

use Carp;
use Carp::Assert qw(assert);
use Exporter::Tiny ();
use JSON::MaybeXS;
use JSON::Path::Constants qw(:operators);
use JSON::Path::Tokenizer qw(tokenize);
use Readonly;
use Safe;
use Scalar::Util qw/looks_like_number blessed/;
use Storable qw/dclone/;
use Sys::Hostname qw/hostname/;
use Try::Tiny;

our $AUTHORITY = 'cpan:POPEFELIX';
our $VERSION   = '1.00';
our @ISA       = qw/ Exporter::Tiny /;
our @EXPORT_OK = qw/ evaluate_jsonpath /;

Readonly my $OPERATOR_IS_TRUE         => 'IS_TRUE';
Readonly my $OPERATOR_TYPE_PATH       => 1;
Readonly my $OPERATOR_TYPE_COMPARISON => 2;
Readonly my %OPERATORS                => (
    $TOKEN_ROOT                => $OPERATOR_TYPE_PATH,          # $
    $TOKEN_CURRENT             => $OPERATOR_TYPE_PATH,          # @
    $TOKEN_CHILD               => $OPERATOR_TYPE_PATH,          # . OR []
    $TOKEN_RECURSIVE           => $OPERATOR_TYPE_PATH,          # ..
    $TOKEN_ALL                 => $OPERATOR_TYPE_PATH,          # *
    $TOKEN_FILTER_OPEN         => $OPERATOR_TYPE_PATH,          # ?(
    $TOKEN_SCRIPT_OPEN         => $OPERATOR_TYPE_PATH,          # (
    $TOKEN_FILTER_SCRIPT_CLOSE => $OPERATOR_TYPE_PATH,          # )
    $TOKEN_SUBSCRIPT_OPEN      => $OPERATOR_TYPE_PATH,          # [
    $TOKEN_SUBSCRIPT_CLOSE     => $OPERATOR_TYPE_PATH,          # ]
    $TOKEN_UNION               => $OPERATOR_TYPE_PATH,          # ,
    $TOKEN_ARRAY_SLICE         => $OPERATOR_TYPE_PATH,          # [ start:end:step ]
    $TOKEN_SINGLE_EQUAL        => $OPERATOR_TYPE_COMPARISON,    # =
    $TOKEN_DOUBLE_EQUAL        => $OPERATOR_TYPE_COMPARISON,    # ==
    $TOKEN_TRIPLE_EQUAL        => $OPERATOR_TYPE_COMPARISON,    # ===
    $TOKEN_GREATER_THAN        => $OPERATOR_TYPE_COMPARISON,    # >
    $TOKEN_LESS_THAN           => $OPERATOR_TYPE_COMPARISON,    # <
    $TOKEN_NOT_EQUAL           => $OPERATOR_TYPE_COMPARISON,    # !=
    $TOKEN_GREATER_EQUAL       => $OPERATOR_TYPE_COMPARISON,    # >=
    $TOKEN_LESS_EQUAL          => $OPERATOR_TYPE_COMPARISON,    # <=
);

Readonly my $ASSERT_ENABLE => $ENV{ASSERT_ENABLE};

sub new {
    my $class = shift;
    my %args  = ref $_[0] eq 'HASH' ? %{ $_[0] } : @_;
    my $self  = {};
    for my $key (qw/root expression/) {
        croak qq{Missing required argument '$key' in constructor} unless $args{$key};
        $self->{$key} = $args{$key};
    }
    $self->{want_ref}         = $args{want_ref}         || 0;
    $self->{_calling_context} = $args{_calling_context} || 0;
    $self->{script_engine}    = $args{script_engine}    || 'PseudoJS';
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

sub to_string {
    return $_[0]->{expression};
}

sub evaluate_jsonpath {
    my ( $json_object, $expression, %args ) = @_;

    my $want_ref = delete $args{want_ref} || 0;
    if ( !ref $json_object ) {
        try {
            $json_object = decode_json($json_object);
        }
        catch {
            croak qq{Unable to decode $json_object as JSON: $_};
        }
    }

    my $self = __PACKAGE__->new(
        root             => $json_object,
        expression       => $expression,
        _calling_context => wantarray ? 'ARRAY' : 'SCALAR',
        %args
    );
    return $self->_evaluate( $json_object, [ tokenize($expression) ], $want_ref );
}

sub _evaluate {    # This assumes that the token stream is syntactically valid
    my ( $self, $obj, $token_stream, $want_ref ) = @_;

    $token_stream ||= [];

    while ( defined( my $token = _get_token($token_stream) ) ) {
        next                                       if $token eq $TOKEN_CURRENT;
        next                                       if $token eq $TOKEN_CHILD;
        assert( $token ne $TOKEN_SUBSCRIPT_OPEN )  if $ASSERT_ENABLE;
        assert( $token ne $TOKEN_SUBSCRIPT_CLOSE ) if $ASSERT_ENABLE;

        if ( $token eq $TOKEN_ROOT ) {
            return $self->_evaluate( $self->{root}, $token_stream, $want_ref );
        }
        elsif ( $token eq $TOKEN_FILTER_OPEN ) {
            confess q{Filters not supported on hashrefs} if _hashlike($obj);

            my @sub_stream;

            # Build a stream of just the tokens between the filter open and close
            while ( defined( my $token = _get_token($token_stream) ) ) {
                last if $token eq $TOKEN_FILTER_SCRIPT_CLOSE;
                if ( $token eq $TOKEN_CURRENT ) {
                    push @sub_stream, $token, $TOKEN_CHILD, $TOKEN_ALL;
                }
                else {
                    push @sub_stream, $token;
                }
            }

            my @matching_indices;
            if ( $self->{script_engine} eq 'PseudoJS' ) {
                @matching_indices = $self->_process_pseudo_js( $obj, [@sub_stream] );
            }
            elsif ( $self->{script_engine} eq 'perl' ) {
                @matching_indices = $self->_process_perl( $obj, [@sub_stream] );
            }
            else {
                croak qq{Unsupported script engine "$self->{script_engine}"};
            }

            if ( !@{$token_stream} ) {
                return $want_ref ? map { \( $obj->[$_] ) } @matching_indices : map { $obj->[$_] } @matching_indices;
            }

            # Evaluate the token stream on all elements that pass the comparison in compare()
            return map { $self->_evaluate( $obj->[$_], dclone($token_stream), $want_ref ) } @matching_indices;
        }
        elsif ( $token eq $TOKEN_RECURSIVE ) {
            my $index = _get_token($token_stream);

            my $matched = [ _match_recursive( $obj, $index, $want_ref ) ];
            if ( !scalar @{$token_stream} ) {
                return @{$matched};
            }
            return map { $self->_evaluate( $_, dclone($token_stream), $want_ref ) } @{$matched};
        }
        else {
            my $index = normalize($token);

            assert( !$OPERATORS{$index}, qq{"$index" is not an operator} ) if $index ne $TOKEN_ALL;
            assert( ref $index eq 'HASH', q{Index is a hashref} ) if $ASSERT_ENABLE && ref $index;

            if ( !@{$token_stream} ) {
                my $got = _get( $obj, $index );
                if ( ref $got eq 'ARRAY' ) {
                    return $want_ref ? @{$got} : map { ${$_} } @{$got};
                }
                else {
                    return if $want_ref && !${$got};    # KLUDGE

                    return $want_ref ? $got : ${$got};
                }
            }
            else {
                my $got = _get( $obj, $index );
                if ( ref $got eq 'ARRAY' ) {
                    return map { $self->_evaluate( ${$_}, dclone($token_stream), $want_ref ) } @{$got};
                }
                else {
                    return $self->_evaluate( ${$got}, dclone($token_stream), $want_ref );
                }
            }
        }
    }
}

sub _get {
    my ( $object, $index ) = @_;

    $object = ${$object} if ref $object eq 'REF';    # KLUDGE

    assert( _hashlike($object) || _arraylike($object), 'Object is a hashref or an arrayref' ) if $ASSERT_ENABLE;

    my $scalar_context;
    my @indices;
    if ( $index eq $TOKEN_ALL ) {
        @indices = keys( %{$object} )   if _hashlike($object);
        @indices = ( 0 .. $#{$object} ) if _arraylike($object);
    }
    elsif ( ref $index ) {
        assert( ref $index eq 'HASH', q{Index supplied in a hashref} ) if $ASSERT_ENABLE;
        if ( $index->{union} ) {
            @indices = @{ $index->{union} };
        }
        elsif ( $index->{slice} ) {
            confess qq(Slices not supported for hashlike objects) if _hashlike($object);
            @indices = _slice( scalar @{$object}, $index->{slice} );
        }
        else { assert( 0, q{Handling a slice or a union} ) if $ASSERT_ENABLE }
    }
    else {
        $scalar_context = 1;
        @indices        = ($index);
    }
    @indices = grep { looks_like_number($_) } @indices if _arraylike($object);

    if ($scalar_context) {
        return unless @indices;

        my ($index) = @indices;
        if ( _hashlike($object) ) {
            return \( $object->{$index} );
        }
        else {
            no warnings qw/numeric/;
            return \( $object->[$index] );
            use warnings qw/numeric/;
        }
    }
    else {
        return [] unless @indices;

        if ( _hashlike($object) ) {
            return [ map { \( $object->{$_} ) } @indices ];
        }
        else {
            my @ret;
            return [ map { \( $object->[$_] ) } grep { looks_like_number($_) } @indices ];
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

sub _get_token {
    my $token_stream = shift;
    my $token        = shift @{$token_stream};
    return unless defined $token;

    if ( $token eq $TOKEN_SUBSCRIPT_OPEN ) {
        my @substream;
        my $close_seen;
        while ( defined( my $token = shift @{$token_stream} ) ) {
            if ( $token eq $TOKEN_SUBSCRIPT_CLOSE ) {
                $close_seen = 1;
                last;
            }
            push @substream, $token;
        }

        assert($close_seen) if $ASSERT_ENABLE;

        if ( grep { $_ eq $TOKEN_ARRAY_SLICE } @substream ) {

            # There are five valid cases:
            #
            # n:m   -> n:m:1
            # n:m:s -> n:m:s
            # :m    -> 0:m:1
            # ::s   -> 0:-1:s
            # n:    -> n:-1:1
            if ( $substream[0] eq $TOKEN_ARRAY_SLICE ) {
                unshift @substream, undef;
            }

            no warnings qw/uninitialized/;
            if ( $substream[2] eq $TOKEN_ARRAY_SLICE ) {
                @substream = ( @substream[ ( 0, 1 ) ], undef, @substream[ ( 2 .. $#substream ) ] );
            }
            use warnings qw/uninitialized/;

            my ( $start, $end, $step );
            $start = $substream[0] // 0;
            $end   = $substream[2] // -1;
            $step  = $substream[4] // 1;
            return { slice => [ $start, $end, $step ] };
        }
        elsif ( grep { $_ eq $TOKEN_UNION } @substream ) {
            my @union = grep { $_ ne $TOKEN_UNION } @substream;
            return { union => \@union };
        }

        return $substream[0];
    }
    return $token;
}

# See http://wiki.ecmascript.org/doku.php?id=proposals:slice_syntax
#
# in particular, for the slice [n:m], m is *one greater* than the last index to slice.
# This means that the slice [3:5] will return indices 3 and 4, but *not* 5.
sub _slice {
    my ( $length, $spec ) = @_;
    my ( $start, $end, $step ) = @{$spec};

    # start, end, and step are set in get_token
    assert( defined $start ) if $ASSERT_ENABLE;
    assert( defined $end )   if $ASSERT_ENABLE;
    assert( defined $step )  if $ASSERT_ENABLE;

    $start = ( $length - 1 ) if $start == -1;
    $end   = $length         if $end == -1;

    my @indices;
    if ( $step < 0 ) {
        @indices = grep { %_ % -$step == 0 } reverse( $start .. ( $end - 1 ) );
    }
    else {
        @indices = grep { $_ % $step == 0 } ( $start .. ( $end - 1 ) );
    }
    return @indices;
}

sub _match_recursive {
    my ( $obj, $index, $want_ref ) = @_;

    my @match;
    if ( _arraylike($obj) ) {
        for ( 0 .. $#{$obj} ) {
            next unless ref $obj->[$_];
            push @match, _match_recursive( $obj->[$_], $index, $want_ref );
        }
    }
    elsif ( _hashlike($obj) ) {
        if ( exists $obj->{$index} ) {
            push @match, $want_ref ? \( $obj->{$index} ) : $obj->{$index};
        }
        for my $val ( values %{$obj} ) {
            next unless ref $val;
            push @match, _match_recursive( $val, $index, $want_ref );
        }
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

sub _process_pseudo_js {
    my ( $self, $object, $token_stream ) = @_;

    # Treat as @.foo IS TRUE
    my $rhs      = pop @{$token_stream};
    my $operator = pop @{$token_stream};

    # This assumes that RHS is only a single token. I think that's a safe assumption.
    if ( $OPERATORS{$operator} eq $OPERATOR_TYPE_COMPARISON ) {
        $rhs = normalize($rhs);
    }
    else {
        push @{$token_stream}, $operator, $rhs;
        $operator = $OPERATOR_IS_TRUE;
    }

    my $index     = normalize( pop @{$token_stream} );
    my $separator = pop @{$token_stream};

    # Evaluate the left hand side of the comparison first. .
    my @lhs = $self->_evaluate( $object, dclone $token_stream );

    # get indexes that pass compare()
    my @matching;
    for ( 0 .. $#lhs ) {
        my $val = ${ _get( $lhs[$_], $index ) };
        push @matching, $_ if _compare( $operator, $val, $rhs );
    }

    return @matching;
}

sub _process_perl {
    my ( $self, $object, $token_stream ) = @_;

    assert( _arraylike($object), q{Object is an arrayref} ) if $ASSERT_ENABLE;

    my $code = join '', @{$token_stream};
    my $cpt = Safe->new;
    $cpt->permit_only( ':base_core', qw/padsv padav padhv padany/ );
    ${ $cpt->varglob('root') } = dclone( $self->{root} );

    my @matching;
    for my $index ( 0 .. $#{$object} ) {
        local $_ = $object->[$index];
        my $ret = $cpt->reval($code);
        croak qq{Error in filter: $@} if $@;
        push @matching, $index if $cpt->reval($code);
    }
    return @matching;
}

sub _compare {
    my ( $operator, $lhs, $rhs ) = @_;

    no warnings qw/uninitialized/;
    if ( $operator eq $OPERATOR_IS_TRUE ) {
        return $lhs ? 1 : 0;
    }

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
    use warnings qw/uninitialized/;
}

1;
__END__
