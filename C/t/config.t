use strict;
use Test;
BEGIN {
    plan(tests => 3,
	 todo => [],
	 onfail => sub {},
	);
}
use Inline Config => 
           DIRECTORY => './_Inline_test';

# test 1 - Make sure config options are type checked
BEGIN {
    eval <<'END';
    use Inline(C => "void foo(){}",
	       LIBS => {X => 'Y'},
	      );
END
    ok($@ =~ /must be a string or an array ref/);
}

# test 2 - Make sure bogus config options croak
BEGIN {
    eval <<'END';
    use Inline(C => "void foo(){}",
	       FOO => 'Bar',
	      );
END
    ok($@ =~ /not a valid config option/);
}

# test 3 - Test the PREFIX config option
BEGIN {
    use Inline(C => 'char* XYZ_Howdy(){return "Hello There";}',
	       PREFIX => 'XYZ_',
	      );
    ok(Howdy eq "Hello There");
}

__END__
