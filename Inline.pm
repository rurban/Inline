package Inline;

require 5.005;                # Parse::RecDescent requires this.
use strict;
use vars qw($VERSION @ISA);
use AutoLoader 'AUTOLOAD';
require DynaLoader;
@ISA = qw(DynaLoader AutoLoader);
$VERSION = '0.26';

use Inline::Config;
use Config;
use Carp;
use Digest::MD5 qw(md5_hex);

my %supported_languages = (C => 1);

#==============================================================================
# This is where everything starts.
#
# "use Inline" will invoke the import sub automatically.
#==============================================================================
sub import {
    # shield Special vars from user changes (like "perl -l")
    local $/ = "\n";
    local $\;
    local $" = ' ';
    local $,;

    my $o = bless {
		   version => $Inline::VERSION,
		  }, shift;

    @{$o}{qw(pkg script)} = caller;
    return unless defined $_[0];     # ignore "use Inline;"
    if ($supported_languages{$_[0]}) {
	$o->{language} = shift;
    }
    else {
	$o->set_options(@_);
	return;
    }
    $o->receive_code(@_);

    $o->check_module;
    $o->reportbug if $Inline::Config::REPORTBUG;
    $o->print_info if $Inline::Config::PRINT_INFO;

    if (not $o->{mod_exists} or
	$Inline::Config::FORCE_BUILD or
	$Inline::Config::SITE_INSTALL or
	$Inline::Config::REPORTBUG
       ) {
	$o->parse_C;
	$o->write_XS;
	$o->write_Inline_headers;
	$o->write_Makefile_PL;
	$o->compile;
    }
    $o->dynaload;
}

#==============================================================================
# Perform cleanup duties
#==============================================================================
sub DESTROY {
    return unless ref $_[0] eq 'Inline';
    my $o = shift;
    $o->clean_build if $Inline::Config::CLEAN_BUILD_AREA;
}

#==============================================================================
# Set special options from the command line
#==============================================================================
my %valid_options = (
		     CLEAN =>        [CLEAN_BUILD_AREA => 1],
		     FORCE =>        [FORCE_BUILD => 1],
		     INFO =>         [PRINT_INFO => 1],
		     NOCLEAN =>      [CLEAN_AFTER_BUILD => 0],
		     REPORTBUG =>    [REPORTBUG => 1],
		     SITE_INSTALL => [SITE_INSTALL => 1],
		    );

sub set_options {
    my $o = shift;

    for my $option (@_) {
	my $OPTION = uc($option);
	if ($valid_options{$OPTION}) {
	    no strict 'refs';
	    $ {"Inline::Config::" . $valid_options{$OPTION}->[0]} =
	      $valid_options{$OPTION}->[1];
	}
	else {
	    croak "Invalid language or option specified. \"$option\" is not supported";
	}
    }    
}

#==============================================================================
# Receive the source code from the caller
#==============================================================================
sub receive_code {
    my $o = shift;
    my ($code) = join '', @_;
    
    croak "No code supplied to Inline"
      unless (defined $code and $code);

    if (ref $_[0] eq 'CODE') {
	$o->{code} = &{$_[0]};
    }
    elsif ($code =~ m|[/\\]| and
	   $code =~ m|^[\w/.-]+$|) {
	if (-f $code) {
	    open CODE, "< $code" 
	      or croak "Couldn't open Inline code file $code:$!\n";
	    $o->{code} = join '', <CODE>;
	    close CODE;
	}
	else {
	    croak "Inline assumes \"$code\" is a filename, and that file does not exist\n";
	}
    } 
    else {
	$o->{code} = $code;
    }
}

#==============================================================================
# Check to see if code has already been compiled
#==============================================================================
sub check_module {
    my ($pkg, $id);
    my $o = shift;

    $pkg = $o->{pkg};
    if ($pkg eq 'main') {
	$id = $o->{script};
	$id =~ s|^.*/(.*)$|$1|g;
	$id =~ s|\W|_|g;
	$id .= '_';
    }
    else {
	no strict 'refs';
	$id = $ {$pkg . '::VERSION'} || '';
	use strict 'refs';
	$id = '' unless $id =~ m|^\d\.\d\d$|;
	$id =~ s|\.|_|;
	croak "Inline.pm Error. \$VERSION is missing or invalid for module $pkg\n"
	  if ($Inline::Config::SITE_INSTALL and not $id);
	$id .= '_' if $id;
    }

    $o->{module} = "${pkg}_$o->{language}_$id" . md5_hex($o->{code});

    my @modparts = split(/::/,$o->{module});
    $o->{modfname} = $modparts[-1];
    $o->{modpname} = join('/',@modparts);
    $o->{so} = $Config::Config{so};
    $o->{mod_exists} = 0;

    if ($Inline::Config::SITE_INSTALL) {
	my $cwd = Cwd::cwd();
	my $blib = "$cwd/blib";
	my $blib_I = "$cwd/blib_I/";
	croak "Invalid attempt to do SITE_INSTALL\n"
	  unless (-d $blib and -w $blib);
	if (not -d $blib_I) {
	    mkdir($blib_I, 0777)
	      or croak "Can't mkdir $blib_I to build Inline code.\n";
	}
	$o->{build_dir} = $blib_I;
	$o->{install_lib} = "$blib/arch/";
	$o->{location} = 
	  "$blib/arch/auto/$o->{modpname}/$o->{modfname}.$o->{so}";
	return;
    }

    $o->{location} =
      "$Config::Config{installsitearch}/auto/$o->{modpname}/$o->{modfname}.$o->{so}";
    if (-f $o->{location}) {
	$o->{mod_exists} = 1;
	if ($Inline::Config::FORCE_BUILD or
	    $Inline::Config::REPORTBUG) {
	    $o->{build_dir} = 
	      Inline::Config::_get_build_prefix() . $o->{modpname} . '/';
	    $o->{install_lib} = Inline::Config::_get_install_lib();
	    unshift @::INC, $o->{install_lib};
	    $o->{location} =
	      "$o->{install_lib}/auto/$o->{modpname}/$o->{modfname}.$o->{so}"; 
	}
    }
    else {
	$o->{build_dir} = 
	  Inline::Config::_get_build_prefix() . $o->{modpname} . '/';
	$o->{install_lib} = Inline::Config::_get_install_lib();
	unshift @::INC, $o->{install_lib};
	$o->{location} = 
	  "$o->{install_lib}/auto/$o->{modpname}/$o->{modfname}.$o->{so}"; 

	if (-f $o->{location}) {
	    $o->{mod_exists} = 1;
	}
    }
}

#==============================================================================
# Dynamically load the object module
#==============================================================================
sub dynaload {
    my $o = shift;
    my ($pkg, $module) = @{$o}{qw(pkg module)};

    eval <<END;
	package $pkg;
	push \@$ {pkg}::ISA, qw($module);

	package $module;
	push \@$ {module}::ISA, qw(Exporter DynaLoader);
	bootstrap $module 
          or croak("Had problems bootstrapping $module");
END
}

1;

__END__

#==============================================================================
# The following subroutines use AutoLoader
# This keeps the runtime overhead down if no compilation is needed.
#==============================================================================

#==============================================================================
# User wants to report a bug
#==============================================================================
sub reportbug {
    use strict;
    use Data::Dumper;
    my $o = shift;
    return if $o->{reportbug_handled}++;
    print STDERR <<END;
<-----------------------REPORTBUG Section------------------------------------->

REPORTBUG mode in effect.

Your Inline $o->{language} code will be processed in the build directory:

$o->{build_dir}

A perl-readable bug report including your perl configuration and run-time
diagnostics will also be generated in the build directory.

When the program finishes please bundle up the above build directory with:

tar czf Inline.REPORTBUG.tar.gz $o->{build_dir}

and send "Inline.REPORTBUG.tar.gz" as an email attachment to INGY\@cpan.org 
with the subject line: "REPORTBUG: Inline.pm"

Include in the email, a description of the problem and anything else that 
you think might be helpful. Patches are welcome! :-\)

<-----------------------End of REPORTBUG Section------------------------------>
END
    my %versions;
    {
	no strict 'refs';
	%versions = map {eval "use $_();"; ($_, $ {$_ . '::VERSION'})}
	qw (Data::Dumper Digest::MD5 Parse::RecDescent 
	    ExtUtils::MakeMaker File::Path FindBin 
	    Inline Inline::Config
	   );
    }

    $o->mkpath($o->{build_dir});
    open REPORTBUG, "> $o->{build_dir}/REPORTBUG"
      or croak "Can't open $o->{build_dir}/REPORTBUG: $!\n";
    %Inline::REPORTBUG_Inline_Object = ();
    %Inline::REPORTBUG_Perl_Config = ();
    %Inline::REPORTBUG_Module_Versions = ();
    my $report = Data::Dumper->new([$o, 
				    \%Config::Config,
				    \%versions,
				   ], 
				   [*Inline::REPORTBUG_Inline_Object,
				    *Inline::REPORTBUG_Perl_Config,
				    *Inline::REPORTBUG_Module_Versions,
				   ],
				  )->Dump;
    my $signature = Digest::MD5::md5_base64($report);
    print REPORTBUG <<END;
$report
\$Inline::REPORTBUG_signature = '$signature';
END
    close REPORTBUG;
}

#==============================================================================
# Print a small report if PRINT_INFO option is set.
#==============================================================================
sub print_info {
    use strict;
    my $o = shift;

    print STDERR <<END;
<-----------------------Information Section----------------------------------->

Information about the processing of your Inline $o->{language} code:

END
    
    print STDERR <<END if ($o->{mod_exists});
Your module is already compiled. It is located at:
$o->{location}

END

    print STDERR <<END if ($o->{mod_exists} and $Inline::Config::FORCE_BUILD);
But the FORCE_BUILD option is set, so your code will be recompiled.
I\'ll use this build directory:
$o->{build_dir}

and I\'ll install the executable as:
$o->{location}

END
    print STDERR <<END if (not $o->{mod_exists});
Your source code needs to be compiled. I\'ll use this build directory:
$o->{build_dir}

and I\'ll install the executable as:
$o->{location}

END

    $o->parse_C unless $o->{parser};
    if (@{$o->{parser}->{data}->{functions}}) {
	print STDERR "The following Inline $o->{language} function(s) have been successfully bound to Perl:\n";
	my $parser = $o->{parser};
	my $data = $parser->{data};
	for my $function (sort @{$data->{functions}}) {
	    my $return_type = $data->{function}->{$function}->{return_type};
	    my @arg_names = @{$data->{function}->{$function}->{arg_names}};
	    my @arg_types = @{$data->{function}->{$function}->{arg_types}};
	    my @args = map {$_ . ' ' . shift @arg_names} @arg_types;
	    print STDERR ("\t$return_type $function(", 
			  join(', ', @args), ")\n");
	}
    }
    else {
	print STDERR "No $o->{language} functions have been successfully bound to Perl.\n\n";
    }

    print STDERR <<END;

<-----------------------End of Information Section---------------------------->
END
}

#==============================================================================
# Parse the function definition information out of the C code
#==============================================================================
my $C_grammar = <<'END_OF_GRAMMAR';

c_code:	part(s) {1}

part:	  comment
	| function_definition
	{
	 my $function = $item[1]->[0];
	 push @{$thisparser->{data}->{functions}}, $function;
	 $thisparser->{data}->{function}->{$function}->{return_type} = 
             $item[1]->[1];
	 $thisparser->{data}->{function}->{$function}->{arg_types} = 
             [map {ref $_ ? $_->[0] : '...'} @{$item[1]->[2]}];
	 $thisparser->{data}->{function}->{$function}->{arg_names} = 
             [map {ref $_ ? $_->[1] : '...'} @{$item[1]->[2]}];
	}
	| anything_else

comment:  m{\s* // [^\n]* \n }x
	| m{\s* /\* (?:[^*]+|\*(?!/))* \*/  ([ \t]*)? }x

function_definition:
	type IDENTIFIER '(' <leftop: arg ',' arg>(s?) ')' '{'
	{[@item[2,1], $item[4]]}

type:	('SV' | 'int' | 'long' | 'double' | 'char' | 'void') star(s?)
	{
         $return = join '',$item[1],@{$item[2]};
         $return = '' unless ($Inline::valid_types{$return});
	}

star: '*'

arg:	  type IDENTIFIER {[@item[1,2]]}
	| '...'

IDENTIFIER: /[a-z]\w*/i

anything_else: /.*/

END_OF_GRAMMAR

sub parse_C {
    use strict;
    use Data::Dumper;
    use Parse::RecDescent;

    my $o = shift;
    return if $o->{parser};

    %Inline::valid_types = map {($_, 1)}
    qw(SV* int long double char* void);

    $::RD_HINT++;
    my $parser = $o->{parser} = Parse::RecDescent->new($C_grammar);

    $parser->c_code($o->{code})
      or croak "Bad C code passed to Inline at @{[caller(2)]}\n";
#    print STDERR Data::Dumper::Dumper $parser->{data};
}

#==============================================================================
# Generate the XS glue code
#==============================================================================
sub write_XS {
    use strict;
    my $o = shift;
    my ($pkg, $module, $modfname) = @{$o}{qw(pkg module modfname)};
    $o->{auto_include} = $Inline::Config::AUTO_INCLUDE_C;

    $o->mkpath($o->{build_dir});
    open XS, "> $o->{build_dir}/$modfname.xs"
      or croak $!;
    print XS <<END;
$o->{auto_include}
$o->{code}

MODULE = $module     	PACKAGE = $pkg

PROTOTYPES: DISABLE
END
    my $parser = $o->{parser};
    my $data = $parser->{data};
    
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
    close XS;
}

#==============================================================================
# Generate the INLINE.h file.
#==============================================================================
sub write_Inline_headers {
    use strict;
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
    use strict;
    use Data::Dumper;

    my $o = shift;
    my %options = (
		   VERSION => '0.00',
		   %Inline::Config::MAKEFILE,
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
    use strict;
    use Cwd;
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
	    system($cmd) and croak <<END;

A problem was encountered while attempting to compile and install your Inline
$o->{language} code. The command that failed was:
  $cmd

The build directory was:
$build_dir

To debug the problem, cd to the build directory, and inspect the output files.

END
	    chdir $cwd;
	}
    }

    if ($Inline::Config::CLEAN_AFTER_BUILD and 
	not $Inline::Config::REPORTBUG
       ) {
	$o->rmpath(Inline::Config::_get_build_prefix(), $modpname);
	unlink "$install_lib/auto/$modpname/.packlist";
	unlink "$install_lib/auto/$modpname/$modfname.bs";
	unlink "$install_lib/auto/$modpname/$modfname.exp"; #MSWin32 VC++
	unlink "$install_lib/auto/$modpname/$modfname.lib"; #MSWin32 VC++
    }
}

#==============================================================================
# This routine fixes problems with the MakeMaker Makefile.
# Yes, it is a kludge, but it is a necessary one.
# 
# ExtUtils::MakeMaker cannot be trusted. It has extremely flaky behaviour
# between releases and platforms. I have been burned several times.
#
# Doing this actually cleans up other code that was trying to guess what
# MM would do. This method will always work.
# And, at least this only needs to happen at build time, when we are taking 
# a performance hit anyway!
#==============================================================================
my %fixes = (
	     INSTALLSITEARCH => 'install_lib',
	     INSTALLDIRS => 'installdirs',
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
	if (/^(\w+)\s*=\s*\S*\s*$/ and
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

#==============================================================================
# Clean the build directory from previous builds
#==============================================================================
sub clean_build {
    use strict;
    my ($prefix, $dir);
    my $o = shift;

    $prefix = Inline::Config::_get_build_prefix();
    opendir(BUILD, $prefix)
      or die "Can't open build directory: $prefix for cleanup $!\n";

    while ($dir = readdir(BUILD)) {
	if ((-d "$prefix$dir") and ($dir =~ /\w{36,}/)) {
	    $o->rmpath($prefix, $dir); 
	}
    }

    close BUILD;
}

#==============================================================================
# Utility subroutines
#==============================================================================

sub mkpath {
    use strict;
    my ($o, $mkpath) = @_;
    my @parts = grep {$_} split(/\//,$mkpath);
    my $path = ($parts[0] =~ /^[A-Z]:$/)
      ? shift(@parts) . '/'  #MSWin32 Drive Letter (ie C:)
	: '/';
    foreach (@parts){
	-d "$path$_" || mkdir("$path$_", 0777);
	$path .= "$_/";
    }
    croak "Couldn't make directory path $mkpath"
      unless -d $mkpath;
}

sub rmpath {
    use strict;
    use File::Path();
    my ($o, $prefix, $rmpath) = @_;
# Nuke the target directory
    File::Path::rmtree("$prefix$rmpath");
# Remove any empty directories underneath the requested one
    my @parts = grep {$_} split(/\//,$rmpath);
    pop @parts;
    while (@parts){
	$rmpath = join '/', @parts;
	rmdir "$prefix$rmpath"
	  or last; # rmdir failed because dir was not empty
	pop @parts;
    }
}
