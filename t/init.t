use strict;
use Test;
BEGIN {
    mkdir('./blib_test', 0777) unless -e './blib_test';
    plan(tests => 1, 
	 todo => [],
	 onfail => sub {},
	);
}

eval <<END;
use Inline C => DATA => BLIB => './blib_test';
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
