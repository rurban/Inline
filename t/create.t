use strict;
use Test;
BEGIN {
    plan(tests => 1, 
	 todo => [],
	 onfail => sub {},
	);
    delete $ENV{PERL_INLINE_DIRECTORY};
    delete $ENV{HOME};
}

use Inline 'C';

# test 1
# Make sure Inline can generate a new _Inline/ directory.
# (But make sure it's in our own space.)
ok(add(3, 7) == 10);

__END__

__C__

int add(int x, int y) {
    return x + y;
}
