use ExtUtils::MakeMaker;

WriteMakefile(
	      NAME => 'Inline',
	      VERSION_FROM => 'Inline.pm',
	      PREREQ_PM => {
			    Data::Dumper => 2.10,
			    Digest::MD5 => 2.09,
			    Parse::RecDescent => 1.78,
			   },
	     );
