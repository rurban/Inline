use warnings;
use strict;

package PROTO5;

use Inline C => Config =>
     DIRECTORY => '_Inline_test',
     PROTOTYPES => 'RUBBISH',
     PROTOTYPE => {foo => 'DISABLE'},
     BUILD_NOISY => $ENV{TEST_VERBOSE},
     CLEAN_AFTER_BUILD => !$ENV{TEST_VERBOSE},
     ;

use Inline C => <<'EOC';

int foo(SV * x) {
     return 23;
}

EOC

my $x = foo(1, 2);
