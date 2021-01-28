use strict;
use warnings;
use 5.008;

package JSON::Path::Constants;

# ABSTRACT: Constants used in the JSON::Path distribution

# VERSION

use Readonly;

use Exporter::Easy (
    TAGS => [
        symbols => [
            '$DOLLAR_SIGN',          '$COMMERCIAL_AT',     '$FULL_STOP',      '$LEFT_SQUARE_BRACKET',
            '$RIGHT_SQUARE_BRACKET', '$ASTERISK',          '$COLON',          '$LEFT_PARENTHESIS',
            '$RIGHT_PARENTHESIS',    '$COMMA',             '$QUESTION_MARK',  '$EQUAL_SIGN',
            '$EXCLAMATION_MARK',     '$GREATER_THAN_SIGN', '$LESS_THAN_SIGN', '$QUOTATION_MARK',
            '$APOSTROPHE'
        ],
        operators => [
            '$TOKEN_ROOT',           '$TOKEN_CURRENT',
            '$TOKEN_CHILD',          '$TOKEN_RECURSIVE',
            '$TOKEN_ALL',            '$TOKEN_FILTER_OPEN',
            '$TOKEN_SCRIPT_OPEN',    '$TOKEN_FILTER_SCRIPT_CLOSE',
            '$TOKEN_SUBSCRIPT_OPEN', '$TOKEN_SUBSCRIPT_CLOSE',
            '$TOKEN_UNION',          '$TOKEN_ARRAY_SLICE',
            '$TOKEN_SINGLE_EQUAL',   '$TOKEN_DOUBLE_EQUAL',
            '$TOKEN_TRIPLE_EQUAL',   '$TOKEN_GREATER_THAN',
            '$TOKEN_LESS_THAN',      '$TOKEN_NOT_EQUAL',
            '$TOKEN_GREATER_EQUAL',  '$TOKEN_LESS_EQUAL',
        ],
    ]
);

Readonly our $QUOTATION_MARK       => q{"};
Readonly our $APOSTROPHE           => q{'};
Readonly our $DOLLAR_SIGN          => '$';
Readonly our $COMMERCIAL_AT        => '@';
Readonly our $FULL_STOP            => '.';
Readonly our $LEFT_SQUARE_BRACKET  => '[';
Readonly our $RIGHT_SQUARE_BRACKET => ']';
Readonly our $ASTERISK             => '*';
Readonly our $COLON                => ':';
Readonly our $LEFT_PARENTHESIS     => '(';
Readonly our $RIGHT_PARENTHESIS    => ')';
Readonly our $COMMA                => ',';
Readonly our $QUESTION_MARK        => '?';
Readonly our $EQUAL_SIGN           => '=';
Readonly our $EXCLAMATION_MARK     => '!';
Readonly our $GREATER_THAN_SIGN    => '>';
Readonly our $LESS_THAN_SIGN       => '<';

Readonly our $TOKEN_ROOT                => $DOLLAR_SIGN;
Readonly our $TOKEN_CURRENT             => $COMMERCIAL_AT;
Readonly our $TOKEN_CHILD               => $FULL_STOP;
Readonly our $TOKEN_RECURSIVE           => $FULL_STOP . $FULL_STOP;
Readonly our $TOKEN_ALL                 => $ASTERISK;
Readonly our $TOKEN_FILTER_OPEN         => $LEFT_SQUARE_BRACKET . $QUESTION_MARK . $LEFT_PARENTHESIS;
Readonly our $TOKEN_SCRIPT_OPEN         => $LEFT_SQUARE_BRACKET . $LEFT_PARENTHESIS;
Readonly our $TOKEN_FILTER_SCRIPT_CLOSE => $RIGHT_PARENTHESIS . $RIGHT_SQUARE_BRACKET;
Readonly our $TOKEN_SUBSCRIPT_OPEN      => $LEFT_SQUARE_BRACKET;
Readonly our $TOKEN_SUBSCRIPT_CLOSE     => $RIGHT_SQUARE_BRACKET;
Readonly our $TOKEN_UNION               => $COMMA;
Readonly our $TOKEN_ARRAY_SLICE         => $COLON;
Readonly our $TOKEN_SINGLE_EQUAL        => $EQUAL_SIGN;
Readonly our $TOKEN_DOUBLE_EQUAL        => $EQUAL_SIGN . $EQUAL_SIGN;
Readonly our $TOKEN_TRIPLE_EQUAL        => $EQUAL_SIGN . $EQUAL_SIGN . $EQUAL_SIGN;
Readonly our $TOKEN_GREATER_THAN        => $GREATER_THAN_SIGN;
Readonly our $TOKEN_LESS_THAN           => $LESS_THAN_SIGN;
Readonly our $TOKEN_NOT_EQUAL           => $EXCLAMATION_MARK . $EQUAL_SIGN;
Readonly our $TOKEN_GREATER_EQUAL       => $GREATER_THAN_SIGN . $EQUAL_SIGN;
Readonly our $TOKEN_LESS_EQUAL          => $LESS_THAN_SIGN . $EQUAL_SIGN;

1;
__END__
