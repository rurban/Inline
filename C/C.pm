package Inline::C;

use strict;
require Inline;
require Inline::C::grammar;
use Parse::RecDescent;
use Config;
use Data::Dumper;
use FindBin;
use Carp;
use Cwd;

$Inline::C::VERSION = '0.30';
@Inline::C::ISA = qw(Inline);

#==============================================================================
# Register this module as an Inline language support module
#==============================================================================
sub register {
    return {
	    language => 'C',
	    aliases => ['c'],
	    type => 'compiled',
	    suffix => $Config{so},
	   };
}

#==============================================================================
# Validate the C config options
#==============================================================================
sub usage_validate {
    my $key = shift;
    return <<END;
The value of config option '$key' must be a string or an array ref

END
}

sub validate {
    my $o = shift;

    $o->{C} = {};
    $o->{C}{XS} = {};
    $o->{C}{MAKEFILE} = {};
    $o->{C}{AUTO_INCLUDE} ||= <<END;
#include "EXTERN.h"
#include "perl.h"
#include "XSUB.h"
#include "INLINE.h"
END

    while (@_) {
	my ($key, $value) = (shift, shift);
	if ($key eq 'LIBS') {
	    add_list($o->{C}{MAKEFILE}, $key, $value, []);
	    next;
	}
	if ($key eq 'INC') {
	    add_string($o->{C}{MAKEFILE}, $key, $value, '');
	    next;
	}
	if ($key eq 'MYEXTLIB') {
	    add_string($o->{C}{MAKEFILE}, $key, $value, '');
	    next;
	}
	if ($key eq 'TYPEMAPS') {
	    add_list($o->{C}{MAKEFILE}, $key, $value, []);
	    next;
	}
	if ($key eq 'AUTO_INCLUDE') {
	    add_text($o->{C}, $key, $value, '');
	    next;
	}
	if ($key eq 'BOOT') {
	    add_text($o->{C}{XS}, $key, $value, '');
	    next;
	}
	if ($key eq 'PREFIX') {
	    croak "Invalid value for 'PREFIX' option"
	      unless ($value =~ /^\w*$/ and
		      $value !~ /\n/);
	    $o->{C}{XS}{PREFIX} = $value;
	    next;
	}
#	if ($key eq 'MANGLE') {
#	    $value = '' unless $value;
#	    $value = 'Inline_' if $value eq '1';
#	    croak "Invalid value for 'MANGLE' option"
#	      unless ($value =~ /^\w*$/ and
#		      $value !~ /\n/);
#	    $o->{C}{XS}{MANGLE} = $value;
#	    $o->{C}{XS}{PREFIX} = $value;
#	    next;
#	}
	croak "'$key' is not a valid config option for Inline::C\n";
    }
}

sub add_list {
    my ($ref, $key, $value, $default) = @_;
    $value = [$value] unless ref $value;
    croak usage_validate($key) unless ref($value) eq 'ARRAY';
    for (@$value) {
	if (defined $_) {
	    push @{$ref->{$key}}, $_;
	}
	else {
	    $ref->{$key} = $default;
	}
    }
}

sub add_string {
    my ($ref, $key, $value, $default) = @_;
    $value = [$value] unless ref $value;
    croak usage_validate($key) unless ref($value) eq 'ARRAY';
    for (@$value) {
	if (defined $_) {
	    $ref->{$key} .= ' ' . $_;
	}
	else {
	    $ref->{$key} = $default;
	}
    }
}

sub add_text {
    my ($ref, $key, $value, $default) = @_;
    $value = [$value] unless ref $value;
    croak usage_validate($key) unless ref($value) eq 'ARRAY';
    for (@$value) {
	if (defined $_) {
	    chomp;
	    $ref->{$key} .= $_ . "\n";
	}
	else {
	    $ref->{$key} = $default;
	}
    }
}

#==============================================================================
# Parse and compile C code
#==============================================================================
sub build {
    my $o = shift;
#    $o->{parser} = undef;print Dumper $o;exit;
    $o->parse;
    $o->write_XS;
    $o->write_Inline_headers;
    $o->write_Makefile_PL;
    $o->compile;
}

#==============================================================================
# Return a small report about the C code..
#==============================================================================
sub info {
    my $o = shift;
    my $text = '';
    $o->parse unless $o->{parser};
    if (defined $o->{parser}{data}{functions}) {
	$text .= "The following Inline $o->{language} function(s) have been successfully bound to Perl:\n";
	my $parser = $o->{parser};
	my $data = $parser->{data};
	for my $function (sort @{$data->{functions}}) {
	    my $return_type = $data->{function}{$function}{return_type};
	    my @arg_names = @{$data->{function}{$function}{arg_names}};
	    my @arg_types = @{$data->{function}{$function}{arg_types}};
	    my @args = map {$_ . ' ' . shift @arg_names} @arg_types;
	    $text .= "\t$return_type $function(" . join(', ', @args) . ")\n";
	}
    }
    else {
	$text .= "No $o->{language} functions have been successfully bound to Perl.\n\n";
    }
    return $text;
}

sub config {
    my $o = shift;
}

#==============================================================================
# Parse the function definition information out of the C code
#==============================================================================
sub parse {
    my $o = shift;
    return if $o->{parser};
    my $grammar = Inline::C::grammar::grammar()
      or croak "Can't find C grammar\n";
    $o->get_maps;
    $o->get_types;

    $::RD_HINT++;
    my $parser = $o->{parser} = Parse::RecDescent->new($grammar);

    $parser->c_code($o->{code})
      or croak "Bad C code passed to Inline at @{[caller(2)]}\n";
#    print STDERR Data::Dumper::Dumper $parser->{data};
}

#==============================================================================
# Gather the path names of all applicable typemap files.
#==============================================================================
sub get_maps {
    my $o = shift;
    unshift @{$o->{C}{MAKEFILE}{TYPEMAPS}}, "$Config::Config{installprivlib}/ExtUtils/typemap";
    if (-f "$FindBin::Bin/typemap") {
	push @{$o->{C}{MAKEFILE}{TYPEMAPS}}, "$FindBin::Bin/typemap";
    }
}

#==============================================================================
# This routine parses XS typemap files to get a list of valid types to create
# bindings to. This code is mostly hacked out of Larry Wall's xsubpp program.
#==============================================================================
sub get_types {
    my (%type_kind, %proto_letter, %input_expr, %output_expr);
    my $o = shift;

    my $proto_re = "[" . quotemeta('\$%&*@;') . "]";
    foreach my $typemap (@{$o->{C}{MAKEFILE}{TYPEMAPS}}) {
	next unless -e $typemap;
	# skip directories, binary files etc.
	warn("Warning: ignoring non-text typemap file '$typemap'\n"), next 
	  unless -T $typemap;
	open(TYPEMAP, $typemap) 
	  or warn ("Warning: could not open typemap file '$typemap': $!\n"), next;
	my $mode = 'Typemap';
	my $junk = "";
	my $current = \$junk;
	while (<TYPEMAP>) {
	    next if /^\s*\#/;
	    my $line_no = $. + 1; 
	    if (/^INPUT\s*$/)   {$mode = 'Input';   $current = \$junk;  next}
	    if (/^OUTPUT\s*$/)  {$mode = 'Output';  $current = \$junk;  next}
	    if (/^TYPEMAP\s*$/) {$mode = 'Typemap'; $current = \$junk;  next}
	    if ($mode eq 'Typemap') {
		chomp;
		my $line = $_;
		TrimWhitespace($_);
		# skip blank lines and comment lines
		next if /^$/ or /^\#/;
		my ($type,$kind, $proto) = 
		  /^\s*(.*?\S)\s+(\S+)\s*($proto_re*)\s*$/ or
		    warn("Warning: File '$typemap' Line $. '$line' TYPEMAP entry needs 2 or 3 columns\n"), next;
		$type = TidyType($type);
		$type_kind{$type} = $kind;
		# prototype defaults to '$'
		$proto = "\$" unless $proto;
		warn("Warning: File '$typemap' Line $. '$line' Invalid prototype '$proto'\n") 
		  unless ValidProtoString($proto);
		$proto_letter{$type} = C_string($proto);
	    }
	    elsif (/^\s/) {
		$$current .= $_;
	    }
	    elsif ($mode eq 'Input') {
		s/\s+$//;
		$input_expr{$_} = '';
		$current = \$input_expr{$_};
	    }
	    else {
		s/\s+$//;
		$output_expr{$_} = '';
		$current = \$output_expr{$_};
	    }
	}
	close(TYPEMAP);
    }

    %Inline::C::valid_types = 
      map {($_, 1)}
    grep {defined $input_expr{$type_kind{$_}}}
    keys %type_kind;

    %Inline::C::valid_rtypes = 
      map {($_, 1)}
    grep {defined $output_expr{$type_kind{$_}}}
    keys %type_kind;
    $Inline::C::valid_rtypes{void} = 1;
}

sub ValidProtoString ($) {
    my $string = shift;
    my $proto_re = "[" . quotemeta('\$%&*@;') . "]";
    return ($string =~ /^$proto_re+$/) ? $string : 0;
}

sub TrimWhitespace {
    $_[0] =~ s/^\s+|\s+$//go;
}

sub TidyType {
    local $_ = shift;
    s|\s*(\*+)\s*|$1|g;
    s|(\*+)| $1 |g;
    s|\s+| |g;
    TrimWhitespace($_);
    $_;
}

sub C_string ($) {
    (my $string = shift) =~ s|\\|\\\\|g;
    $string;
}

#==============================================================================
# Generate the XS glue code
#==============================================================================
sub write_XS {
    my $o = shift;
    my ($pkg, $module, $modfname) = @{$o}{qw(pkg module modfname)};
    my $prefix = (($o->{C}{XS}{PREFIX}) ?
		  "PREFIX = $o->{C}{XS}{PREFIX}" :
		  '');
		  
    $o->mkpath($o->{build_dir});
    open XS, "> $o->{build_dir}/$modfname.xs"
      or croak $!;
    print XS <<END;
$o->{C}{AUTO_INCLUDE}
$o->{code}

MODULE = $module	PACKAGE = $pkg	$prefix

PROTOTYPES: DISABLE
END
    my $parser = $o->{parser};
    my $data = $parser->{data};

    warn("Warning. No Inline C functions bound to Perl\n" .
	 "Check your C function definition(s) for Inline compatibility\n\n")
      if ((not defined$data->{functions}) and ($^W));
    
    for my $function (@{$data->{functions}}) {
	my $return_type = $data->{function}->{$function}->{return_type};
	my @arg_names = @{$data->{function}->{$function}->{arg_names}};
	my @arg_types = @{$data->{function}->{$function}->{arg_types}};

	print XS ("\n$return_type\n$function (", 
		  join(', ', @arg_names), ")\n");

	for my $arg_name (@arg_names) {
	    my $arg_type = shift @arg_types;
	    last if $arg_type eq '...';
	    print XS "\t$arg_type\t$arg_name\n";
	}

	my $listargs = '';
	$listargs = pop @arg_names if (@arg_names and 
				       $arg_names[-1] eq '...');
	my $arg_name_list = join(', ', @arg_names);

	if ($return_type eq 'void') {
	    print XS <<END;
	PREINIT:
	I32* temp;
	PPCODE:
	temp = PL_markstack_ptr++;
	$function($arg_name_list);
	if (PL_markstack_ptr != temp) {
          /* truly void, because dXSARGS not invoked */
	  PL_markstack_ptr = temp;
	  XSRETURN_EMPTY; /* return empty stack */
        }
        /* must have used dXSARGS; list context implied */
	return; /* assume stack size is correct */
END
	}
	elsif ($listargs) {
	    print XS <<END;
	PREINIT:
	I32* temp;
	CODE:
	temp = PL_markstack_ptr++;
	RETVAL = $function($arg_name_list);
	PL_markstack_ptr = temp;
	OUTPUT:
        RETVAL
END
	}
    }
    print XS "\n";

    if (defined $o->{C}{XS}{BOOT} and
	$o->{C}{XS}{BOOT}) {
	print XS <<END;
BOOT:
$o->{C}{XS}{BOOT}
END
    }

    close XS;
}

#==============================================================================
# Generate the INLINE.h file.
#==============================================================================
sub write_Inline_headers {
    my $o = shift;

    open HEADER, "> $o->{build_dir}/INLINE.h"
      or croak;

    print HEADER <<'END';
#define Inline_Stack_Vars	dXSARGS
#define Inline_Stack_Items      items
#define Inline_Stack_Item(x)	ST(x)
#define Inline_Stack_Reset      sp = mark
#define Inline_Stack_Push(x)	XPUSHs(x)
#define Inline_Stack_Done	PUTBACK
#define Inline_Stack_Return(x)	XSRETURN(x)
#define Inline_Stack_Void       XSRETURN(0)

#define INLINE_STACK_VARS	Inline_Stack_Vars
#define INLINE_STACK_ITEMS	Inline_Stack_Items
#define INLINE_STACK_ITEM(x)	Inline_Stack_Item(x)
#define INLINE_STACK_RESET	Inline_Stack_Reset
#define INLINE_STACK_PUSH(x)    Inline_Stack_Push(x)
#define INLINE_STACK_DONE	Inline_Stack_Done
#define INLINE_STACK_RETURN(x)	Inline_Stack_Return(x)
#define INLINE_STACK_VOID	Inline_Stack_Void

#define inline_stack_vars	Inline_Stack_Vars
#define inline_stack_items	Inline_Stack_Items
#define inline_stack_item(x)	Inline_Stack_Item(x)
#define inline_stack_reset	Inline_Stack_Reset
#define inline_stack_push(x)    Inline_Stack_Push(x)
#define inline_stack_done	Inline_Stack_Done
#define inline_stack_return(x)	Inline_Stack_Return(x)
#define inline_stack_void	Inline_Stack_Void
END

    close HEADER;
}

#==============================================================================
# Generate the Makefile.PL
#==============================================================================
sub write_Makefile_PL {
    my $o = shift;
    $o->{xsubppargs} = '';
    for (@{$o->{C}{MAKEFILE}{TYPEMAPS}}) {
	$o->{xsubppargs} .= "-typemap $_ ";
    }

    my %options = (
		   VERSION => '0.00',
		   %{$o->{C}{MAKEFILE}},
		   NAME => $o->{module},
		  );
    
    open MF, "> $o->{build_dir}/Makefile.PL"
      or croak;
    
    print MF <<END;
use ExtUtils::MakeMaker;
my %options = %\{       
END

    local $Data::Dumper::Terse = 1;
    local $Data::Dumper::Indent = 1;
    print MF Data::Dumper::Dumper(\ %options);

    print MF <<END;
\};
WriteMakefile(\%options);
END
    close MF;
}

#==============================================================================
# Run the build process.
#==============================================================================
sub compile {
    my ($o, $perl, $make, $cmd, $cwd);
    $o = shift;
    my ($module, $modpname, $modfname, $build_dir, $install_lib) = 
      @{$o}{qw(module modpname modfname build_dir install_lib)};

    -f ($perl = $Config::Config{perlpath})
      or croak "Can't locate your perl binary";
    ($make = $Config::Config{make})
      or croak "Can't locate your make binary";
    $cwd = &cwd;
    for $cmd ("$perl Makefile.PL > out.Makefile_PL 2>&1",
	      \ &fix_make,   # Fix Makefile problems
	      "$make > out.make 2>&1",
	      "$make install > out.make_install 2>&1",
	     ) {
	if (ref $cmd) {
	    $o->$cmd();
	}
	else {
	    chdir $build_dir;
	    system($cmd) and do {
		$o->error_copy;
		croak <<END;

A problem was encountered while attempting to compile and install your Inline
$o->{language} code. The command that failed was:
  $cmd

The build directory was:
$build_dir

To debug the problem, cd to the build directory, and inspect the output files.

END
	    };
	    chdir $cwd;
	}
    }

    if ($o->{config}{CLEAN_AFTER_BUILD} and 
	not $o->{config}{REPORTBUG}
       ) {
	$o->rmpath($o->{config}{BLIB}, $modpname);
	unlink "$install_lib/auto/$modpname/.packlist";
	unlink "$install_lib/auto/$modpname/$modfname.bs";
	unlink "$install_lib/auto/$modpname/$modfname.exp"; #MSWin32 VC++
	unlink "$install_lib/auto/$modpname/$modfname.lib"; #MSWin32 VC++
    }
}

#==============================================================================
# This routine fixes problems with the MakeMaker Makefile.
#==============================================================================
my %fixes = (
	     INSTALLSITEARCH => 'install_lib',
	     INSTALLDIRS => 'installdirs',
	     XSUBPPARGS => 'xsubppargs',
	    );

sub fix_make {
    use strict;
    my (@lines, $fix);
    my $o = shift;

    $o->{installdirs} = 'site';
    
    open(MAKEFILE, "< $o->{build_dir}Makefile")
      or croak "Can't open Makefile for input: $!\n";
    @lines = <MAKEFILE>;
    close MAKEFILE;

    open(MAKEFILE, "> $o->{build_dir}Makefile")
      or croak "Can't open Makefile for output: $!\n";
    for (@lines) {
	if (/^(\w+)\s*=\s*\S+.*$/ and
	    $fix = $fixes{$1}
	   ) {
	    print MAKEFILE "$1 = $o->{$fix}\n"
	}
	else {
	    print MAKEFILE;
	}
    }
    close MAKEFILE;
}

1;

__END__
