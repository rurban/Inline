use strict;
use Test;
BEGIN {
    plan(tests => 1, 
	 todo => [],
	 onfail => sub {},
	);
}

eval <<END;
use Inline C => DATA => 
           DIRECTORY => './_Inline_test';
Inline->init;
# test 1
ok(add(3, 7) == 10);

END

print "$@\nnot ok 1\n" if $@;

__END__

__C__

int add(int x, int y) {
    return x + y;
}
