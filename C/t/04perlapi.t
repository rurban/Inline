use strict;
use Test;
BEGIN {
    plan(tests => 1,
	 todo => [],
	 onfail => sub {},
	);
}
use Inline Config => 
           DIRECTORY => './_Inline_test';
use Inline 'C';

$main::myvar = $main::myvar = "myvalue";

# test 1
ok(lookup('main::myvar') eq "myvalue");

__END__

__C__

SV* lookup(char* var) {
    return perl_get_sv(var, 0);
}
