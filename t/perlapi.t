use strict;
use Test;
BEGIN {
    mkdir('./blib_test', 0777) unless -e './blib_test';
    plan(tests => 1,
	 todo => [],
	 onfail => sub {},
	);
}
use Inline Config => BLIB => './blib_test';
use Inline C => 'DATA';

$main::myvar = $main::myvar = "myvalue";

# test 1
ok(lookup('main::myvar') eq "myvalue");

__END__

__C__

SV* lookup(char* var) {
    return perl_get_sv(var, 0);
}
