use strict;
use ExtUtils::MakeMaker;
use Config;

my ($cc, $exe) = @Config{'cc', '_exe'};
my $found = 0;
for my $lib (split /[:;]/, $ENV{PATH}) {
    $found = -f "$lib/${cc}$exe" and last;
}

if ($found) {
    print <<END;

Inline::C is packaged with Inline.pm because it is the most commonly used
Inline language module. See also: Inline::CPP (C++), ::Java, ::Python, 
::Tcl, ::ASM, and ::CPR.

I have found the C compiler '${cc}$exe' on your system by searching your PATH.

END
}
else {
    print <<END;

The C compiler '${cc}$exe' was not found on your system by searching your 
PATH. You can install Inline.pm without installing Inline::C. But you'll
need to install another Inline language module (like Inline::Java for 
instance) to actually make any use of it.

END
}

my $answer = '';
my $default = $found ? "y" : "n";
while (1) {
    $answer = prompt ('Do you want to install Inline::C?', $default);
    last if $answer =~ /^(y|yes|n|no)$/i;
}

if ($answer =~ /^(y|yes)$/i) {
    WriteMakefile(
		  NAME => 'Inline::C',
		  VERSION_FROM => 'C.pm',
		  clean => {FILES => '_Inline_test/'},
		 )
}
else {
    open MF, "> Makefile" or die "Can't open Makefile for output";
    print MF <<'END';
all::
test::
clean::
END
    close MF;
}
