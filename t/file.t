use strict;
use Test;

BEGIN {
    plan(tests => 1, 
	 todo => [],
	 onfail => sub {},
	);
}

use Inline C => './t/file',
           DIRECTORY => './_Inline_test';

# test 1
# Make sure that the syntax for reading external files works.
ok(add(3, 7) == 10);
