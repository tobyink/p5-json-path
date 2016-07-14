package JSON::Path::Tokenizer;

use 5.016;
use Carp;
use Readonly;
use JSON::Path::Constants qw(:symbols);
use Exporter::Easy ( OK => [ 'tokenize' ] );

Readonly my %RESERVED_SYMBOLS => (
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
            elsif ( $char eq $EQUAL_SIGN ) {    # Build '=', '==', or '===' token as appropriate
                my $next_char = shift @chars;
                if ( !defined $next_char ) {
                    die qq{Unterminated comparison: '=', '==', or '===' without predicate\n};
                }
                if ( $next_char eq $EQUAL_SIGN ) {
                    $token .= $next_char;
                    $next_char = shift @chars;
                    if ( !defined $next_char ) {
                        die qq{Unterminated comparison: '==' or '===' without predicate\n};
                    }
                    if ( $next_char eq $EQUAL_SIGN ) {
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
            elsif ( $char eq $LESS_THAN_SIGN || $char eq $GREATER_THAN_SIGN ) {
                my $next_char = shift @chars;
                if ( !defined $next_char ) {
                    die qq{Unterminated comparison: '=', '==', or '===' without predicate\n};
                }
                if ( $next_char eq $EQUAL_SIGN ) {
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

1;
__END__
