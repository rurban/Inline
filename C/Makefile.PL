use ExtUtils::MakeMaker;
WriteMakefile(
	      NAME => 'Inline::C',
	      VERSION_FROM => 'C.pm',
	      clean => {FILES => 'blib_test/'},
	     );
