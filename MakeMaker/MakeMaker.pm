package Inline::MakeMaker;
use strict;
use Carp;
$Inline::MakeMaker::VERSION = '0.40';

my ($package, $filename, $name, $version);

sub usage_postamble {
    "When using Inline::MakeMaker, it is illegal to define &MY::postamble\n";
}

sub import {
    ($package, $filename) = caller;
    croak "Inline::MakeMaker is only intended to be used in Makefile.PL"
      unless $filename =~ /Makefile.PL$/;
    require ExtUtils::MakeMaker;
}

sub WriteMakefile {
    croak "Inline::MakeMaker::WriteMakefile needs even number of args\n" 
      if @_ % 2;
    my %args = @_;
    croak "Inline::MakeMaker::WriteMakefile requires the NAME parameter\n"
      unless $args{NAME};
    croak <<END unless ($args{NAME} || $args{VERSION_NAME});
Inline::MakeMaker::WriteMakefile requires either the VERSION or
VERSION_FROM parameter.
END
    $version = $args{VERSION} || 
      ExtUtils::MM_Unix->parse_version($args{VERSION_FROM})
	or croak "Can't determine version for $args{NAME}\n";
    croak <<END unless $version =~ /^\d\.\d\d$/;
Invalid version '$version' for $args{NAME}.
Must be of the form #.##. (For instance '1.23')
END

    # Provide a convenience rule to clean up Inline's messes
    $args{clean} = { FILES => '_Inline' } unless defined $args{clean};
    # Add Inline 0.40 to the dependencies
    $args{PREREQ_PM}{Inline} = '0.40' unless defined $args{PREREQ_PM}{Inline};

    if (defined $args{NAME}) {
	$name = $args{NAME};
    }
    else {
	croak "Inline::MakeMaker::WriteMakefile requires a NAME parameter";
    }
    &ExtUtils::MakeMaker::WriteMakefile(%args);
}

# Rewire Makefile.PL to use our WriteMakefile
my $lexwarn = ($] >= 5.006) ? 'no warnings;' : '';
eval <<END;
$lexwarn
sub INIT {
    &init;
}
END

sub init {
    no strict 'refs';
    *{"${package}::WriteMakefile"} = \&Inline::MakeMaker::WriteMakefile;
    croak usage_postamble 
      unless MY::postamble('testing') eq 'roger';
}

BEGIN {
    croak usage_postamble if defined &MY::postamble;
}

sub MY::postamble {
    return 'roger' if $_[0] eq 'testing';
    my @parts = split /::/, $name;
    my $subpath = join '/', @parts;
    my $object = $parts[-1];

    return <<END;
pure_all :: blib/arch/auto/$subpath/.inline

blib/arch/auto/$subpath/.inline :
	\$(PERL) -Mblib -MInline=_INSTALL_ -M$name -e1 $version
END
}

###############################################################################
# Inline utilities
###############################################################################
my $i;
sub utils {
    print "->@_<-\n";
    require Inline;
    $i = bless {}, 'Inline';
    shift if $_[0] eq 'Inline';
    my $util = shift;
    no strict 'refs';
    goto &{uc($util)};
}

sub INSTALL {
    print <<END;

The INSTALL command has not yet been implemented.
Stay tuned...

@_

END
    exit 0;
}

sub MAKEPPD {
    print <<END;

The MAKEPPD command has not yet been implemented.
Stay tuned...

@_

END
    exit 0;
}

sub MAKEDIST {
    print <<END;

The MAKEDIST command has not yet been implemented.
Stay tuned...

@_

END
    exit 0;
}

1;
