package Inline;

use strict;
require 5.005;
$Inline::VERSION = '0.31';

use Inline::messages;
use Config;
use Carp;
use Digest::MD5 qw(md5_hex);
use Cwd qw(abs_path cwd);
use FindBin;

my %CONFIG = ();
my @DATA_OBJS = ();
my $INIT = 0;
my $version_printed;

my %shortcuts = 
  (
   CLEAN =>        [CLEAN_BUILD_AREA => 1],
   FORCE =>        [FORCE_BUILD => 1],
   INFO =>         [PRINT_INFO => 1],
   VERSION =>      [PRINT_VERSION => 1],
   NOCLEAN =>      [CLEAN_AFTER_BUILD => 0],
   REPORTBUG =>    [REPORTBUG => 1],
   SITE_INSTALL => [SITE_INSTALL => 1],
  );

my $default_config = 
  {
   DIRECTORY => '',
   WITH => [],
   CLEAN_AFTER_BUILD => 1,
   CLEAN_BUILD_AREA => 0,
   FORCE_BUILD => 0,
   PRINT_INFO => 0,
   PRINT_VERSION => 0,
   REPORTBUG => 0,
   SITE_INSTALL => 0,
  };

#==============================================================================
# This is where everything starts.
#==============================================================================
sub import {
    goto &deprecated_import if $INIT; 

    local $/ = "\n"; local $\; local $" = ' '; local $,;

    my $o;
    my ($pkg, $script) = caller;
    my $class = shift;
    if ($class ne 'Inline') {
	croak usage_use($class) if $class =~ /^Inline::/;
	croak usage;
    }

    $CONFIG{$pkg}{template} ||= $default_config;

    return unless @_;
    my $control = shift;

    if ($control eq 'with') {
	return handle_with($pkg, @_);
    }
    elsif ($control eq 'Config') {
	return handle_config($pkg, @_);
    }
    elsif ($shortcuts{uc($control)}) {
	return handle_shortcuts($pkg, $control, @_);
    }
    elsif ($control =~ /^\S+$/ and $control !~ /\n/) {
	my $language_id = $control;
	my $option = shift || '';
	my %config = @_;
	for (keys %config) {
	    croak usage if /[\s\n]/;
	}
	$o = bless {
		    version => $Inline::VERSION,
		    pkg => $pkg,
		    script => $script,
		    language_id => $language_id,
		   }, $class;
	if ($option eq 'DATA' or not $option) {
	    $o->{config} = {%config};
	    push @DATA_OBJS, $o;
	    return;
	}
	elsif ($option eq 'Config') {
	    $CONFIG{$pkg}{$language_id} = {%config};
	    return;
	}
	else {
	    $o->receive_code($option);
	    $o->{config} = {%config};
	}
    }
    else {
	croak usage;
    }
    $o->glue;
}

#==============================================================================
# Run time version of import (public method)
#==============================================================================
sub bind {
    croak usage_bind_runtime unless $INIT; 

    local $/ = "\n"; local $\; local $" = ' '; local $,;

    my ($code, %config);
    my $o;
    my ($pkg, $script) = caller;
    my $class = shift;
    croak usage_bind unless $class eq 'Inline';

    $CONFIG{$pkg}{template} ||= $default_config;

    my $language_id = shift or croak usage_bind;
    if ($_[-1] ne '_deprecated_import_') {
	croak usage_bind 
	  unless ($language_id =~ /^\S+$/ and $language_id !~ /\n/);
	$code = shift or croak usage_bind;
	%config = @_;
    }
    else {
	pop @_;
	$code = [@_];
    }
	
    for (keys %config) {
	croak usage_bind if /[\s\n]/;
    }
    $o = bless {
		version => $Inline::VERSION,
		pkg => $pkg,
		script => $script,
		language_id => $language_id,
	       }, $class;
    $o->receive_code($code);
    $o->{config} = {%config};

    $o->glue;
}

#==============================================================================
# Process delayed objects that don't have source code yet.
#==============================================================================
# This code is an ugly hack because of the fact that you can't use an 
# INIT block at "run-time proper". So we kill the warning for 5.6+ users
# and tell them to use a Inline->init() call if they run into problems. (rare)
my $lexwarn = ($] >= 5.006) ? 'no warnings;' : '';

eval <<END;
$lexwarn
sub INIT {
    \$INIT++;
    &init;
}
END

sub init {
    local $/ = "\n"; local $\; local $" = ' '; local $,;

    for my $o (@DATA_OBJS) {
	$o->read_DATA;
	$o->glue;
    }
}

#==============================================================================
# Compile the source if needed and then dynaload the object
#==============================================================================
sub glue {
    my $o = shift;
    my ($pkg, $language_id) = @{$o}{qw(pkg language_id)};
    my @config = (%{$CONFIG{$pkg}{template}},
		  %{$CONFIG{$pkg}{$language_id} || {}},
		  %{$o->{config} || {}},
		 );
    @config = $o->check_config(@config);
    $o->check_config_file;
    push @config, $o->with_configs;
    my $language = $o->{language};

    print_version() if $o->{config}{PRINT_VERSION};
    reportbug() if $o->{config}{REPORTBUG};
    croak "No $language_id source code found\n" unless $o->{code};
 	
    $o->check_module;
    
    if ($o->{config}{PRINT_INFO} or
	$o->{config}{FORCE_BUILD} or
	$o->{config}{SITE_INSTALL} or
	$o->{config}{REPORT_BUG} or
	not $o->{mod_exists}) {
	eval "require $o->{ILSM_module}";
	croak $@ if $@;
	bless $o, $o->{ILSM_module};    
	$o->validate(@config);
    }
    else {
	$o->{config} = {(%{$o->{config}}, @config)};
    }
    $o->print_info if $o->{config}{PRINT_INFO};
    if (not $o->{mod_exists} or
	$o->{config}{FORCE_BUILD} or
	$o->{config}{SITE_INSTALL} or
	$o->{config}{REPORTBUG}
       ) {
	$o->build;
    }
    if ($o->{ILSM_suffix} ne 'so' and
	$o->{ILSM_suffix} ne 'dll' and
	ref($o) eq 'Inline'
       ) {
	eval "require $o->{ILSM_module}";
	croak $@ if $@;
	bless $o, $o->{ILSM_module};    
    }

    $o->load;
}

#==============================================================================
# Get the source code
#==============================================================================
sub receive_code {
    my $o = shift;
    my $code = shift;
    
    croak usage unless (defined $code and $code);

    if (ref $code eq 'CODE') {
	$o->{code} = &$code;
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
    elsif (ref $code eq 'ARRAY') {
	$o->{code} = join '', @$code;
    }
    else {
	$o->{code} = $code;
    }
}

#==============================================================================
# Get source from the DATA filehandle
#==============================================================================
my %DATA;
sub read_DATA {
    my $o = shift;
    my ($pkg, $language_id) = @{$o}{qw(pkg language_id)};
    {
	no strict 'refs';
	*Inline::DATA = *{$pkg . '::DATA'};
    }
    $DATA{$pkg} ||= '';
    unless ($DATA{$pkg} eq $language_id) {
	while (<Inline::DATA>) {
	    last if /^__($language_id)__$/;
	}
    }
    while (<Inline::DATA>) {
	last if /^\=\w+/;
	if (/^__(\S+)__$/) {
	    $DATA{$pkg} = $1;
	    last;
	}
	$o->{code} .= $_;
    }
}

#==============================================================================
# Validate and store the non language-specific config options
#==============================================================================
sub check_config {
    my $o = shift;
    my @others;
    while (@_) {
	my ($key, $value) = (shift, shift);
	if (defined $ {$default_config}{$key}) {
	    if ($key eq 'DIRECTORY') {
		if ($value) {
		    croak usage_DIRECTORY($value)
		      unless (-d $value);
		    $value = abs_path($value) . '/';
		}
	    }
	    elsif ($key eq 'WITH') {
		croak usage_WITH
		  if (ref $value and
		      ref $value ne 'ARRAY');
		$value = [$value] unless ref $value;
	    }
	    $o->{config}{$key} = $value;
	}
	else {
	    push @others, $key, $value;
	}
    }
    $o->{config}{DIRECTORY} ||= $o->find_temp_dir;
    return (@others);
}

#==============================================================================
# Read the cached config file from the Inline directory. This will indicate
# whether the Language code is valid or not.
#==============================================================================
sub check_config_file {
    my ($DIRECTORY);
    my $o = shift;
    
    croak usage_Config if exists $main::{Config::};

    # First make sure we have the DIRECTORY
    if ($o->{config}{SITE_INSTALL}) {
	my $cwd = Cwd::cwd();
	$DIRECTORY = $o->{config}{DIRECTORY} = "$cwd/_Inline/";
	if (not -d $DIRECTORY) {
	    mkdir($DIRECTORY, 0777)
	      or croak "Can't mkdir $DIRECTORY to build Inline code.\n";
	}
    }
    else {
	$DIRECTORY = $o->{config}{DIRECTORY} ||= $o->find_temp_dir;
    }

    $o->create_config_file("$DIRECTORY/config") if not -e "$DIRECTORY/config";

    open CONFIG, "< $DIRECTORY/config"
      or croak "Can't open ${DIRECTORY}config for input\n";
    my $config = join '', <CONFIG>;
    close CONFIG;

    delete $main::{Inline::config::};
    eval <<END;
;package Inline::config;
no strict;
$config
END

    croak error_old_version 
      unless (defined $Inline::config::version and
	      $Inline::config::version >= 0.31);
    croak "Unable to parse ${DIRECTORY}config\n$@\n" if $@;
    croak usage_language($o->{language_id})
      unless defined $Inline::config::languages{$o->{language_id}};
    $o->{language} = $Inline::config::languages{$o->{language_id}};

    if ($o->{language} ne $o->{language_id}) {
	if (defined $o->{$o->{language_id}}) {
	    $o->{$o->{language}} = $o->{$o->{language_id}};
	    delete $o->{$o->{language_id}};
	}
    }

    $o->{ILSM_type} = $Inline::config::types{$o->{language}};
    $o->{ILSM_module} = $Inline::config::modules{$o->{language}};
    $o->{ILSM_suffix} = $Inline::config::suffixes{$o->{language}};

#    print Dumper $o;
}

#==============================================================================
# Auto-detect installed Inline language support modules
#==============================================================================
sub create_config_file {
    my ($o, $file) = @_;
    my ($lib, $mod, $register, %checked,
	%languages, %types, %modules, %suffixes);

  LIB:
    for my $lib (@INC) {
	next unless -d "$lib/Inline";
	opendir LIB, "$lib/Inline" 
	  or croak "Can't open directory $lib/Inline";
	while ($mod = readdir(LIB)) {
	    next unless $mod =~ /\.pm$/;
	    $mod =~ s/\.pm$//;
	    next LIB if ($checked{$mod}++);
	    next if $mod eq 'messages'; # Skip Inline::messages
	    if ($mod eq 'Config') {     # Skip Inline::Config
		warn usage_Config if $^W;
		next;
	    }
	    eval "require Inline::$mod;\$register=&Inline::${mod}::register";
	    croak usage_register($mod, $@) if $@;
	    my $language = $register->{language} 
	    or croak usage_register($mod);
	    for (@{$register->{aliases}}) {
		croak usage_alias_used($mod, $_, $languages{$_})
		  if defined $languages{$_};
		$languages{$_} = $language;
	    }
	    $languages{$language} = $language;
	    $types{$language} = $register->{type};
	    croak usage_register($mod, "Bad language type")
	      unless ($types{$language} eq 'compiled' or
		      $types{$language} eq 'interpreted');
	    $modules{$language} = "Inline::$mod";
	    $suffixes{$language} = $register->{suffix};
	}
	closedir LIB;
    }
    
    require Data::Dumper;
    local $Data::Dumper::Terse = 1;
    local $Data::Dumper::Indent = 1;
    my $languages = Data::Dumper::Dumper(\%languages);
    my $types = Data::Dumper::Dumper(\%types);
    my $modules = Data::Dumper::Dumper(\%modules);
    my $suffixes = Data::Dumper::Dumper(\%suffixes);
    
    open CONFIG, "> $file" or croak "Can't open $file for output\n";
    print CONFIG <<END;
\$version = $Inline::VERSION;
%languages = %{$languages};
%types = %{$types};
%modules = %{$modules};
%suffixes = %{$suffixes};
END
    close CONFIG;
}

#==============================================================================
# Get config hints
#==============================================================================
sub with_configs {
    my $o = shift;
    my @configs;
    for my $mod (@{$o->{config}{WITH}}) {
	my $ref = eval {
	    no strict 'refs';
	    &{$mod . "::Inline"}($o->{language});
	};
	croak "Module $mod does not work with Inline\n$@\n" if $@;
	push @configs, %$ref;
    }
    return @configs;
}

#==============================================================================
# Check to see if code has already been compiled
#==============================================================================
sub check_module {
    my ($pkg, $id, $DIRECTORY);
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
	  if ($o->{config}{SITE_INSTALL} and not $id);
	$id .= '_' if $id;
    }

    $o->{module} = "${pkg}_$o->{language}_$id" . md5_hex($o->{code});

    my @modparts = split(/::/,$o->{module});
    $o->{modfname} = $modparts[-1];
    $o->{modpname} = join('/',@modparts);
    $o->{suffix} = $o->{ILSM_suffix};
    $o->{mod_exists} = 0;

    $DIRECTORY = $o->{config}{DIRECTORY};

    if ($o->{config}{SITE_INSTALL}) {
	my $blib = Cwd::cwd() . "/blib";
	croak "Invalid attempt to do SITE_INSTALL\n"
	  unless (-d $blib and -w $blib);
	$o->{build_dir} = $DIRECTORY . 'build/' . $o->{modpname} . '/';
	$o->{install_lib} = "$blib/arch/";
	$o->{location} = 
	  "$blib/arch/auto/$o->{modpname}/$o->{modfname}.$o->{suffix}";
	return;
    }

    $o->{location} =
      "$Config::Config{installsitearch}/auto/" .
	"$o->{modpname}/$o->{modfname}.$o->{suffix}";
    if (-f $o->{location}) {
	$o->{mod_exists} = 1;
	if ($o->{config}{FORCE_BUILD} or
	    $o->{config}{REPORTBUG}) {
	    $o->{build_dir} = $DIRECTORY . 'build/' . $o->{modpname} . '/';
	    $o->{install_lib} = $DIRECTORY . 'lib';
	    unshift @::INC, $o->{install_lib};
	    $o->{location} =
	      "$o->{install_lib}/auto/$o->{modpname}/$o->{modfname}.$o->{suffix}"; 
	}
    }
    else {
	$o->{build_dir} = $DIRECTORY . 'build/' . $o->{modpname} . '/';
	$o->{install_lib} = $DIRECTORY . 'lib';
	unshift @::INC, $o->{install_lib};
	$o->{location} = 
	  "$o->{install_lib}/auto/$o->{modpname}/$o->{modfname}.$o->{suffix}"; 

	if (-f $o->{location}) {
	    $o->{mod_exists} = 1;
	}
    }
}

#==============================================================================
# Dynamically load the object module
#==============================================================================
sub load {
    my $o = shift;
    my ($pkg, $module) = @{$o}{qw(pkg module)};

    croak usage_loader unless $o->{ILSM_type} eq 'compiled';

    require DynaLoader;
    @Inline::ISA = qw(DynaLoader);

    eval <<END;
	package $pkg;
	push \@$ {pkg}::ISA, qw($module);

	package $module;
	push \@$ {module}::ISA, qw(Exporter DynaLoader);
	bootstrap $module;
END
    croak("Had problems bootstrapping Inline module $module\n$@\n") if $@;
}

#==============================================================================
# Handle old syntax
#==============================================================================
sub deprecated_import {
    local $/ = "\n"; local $\; local $" = ' '; local $,;
    
    my ($class, $language, @lines) = @_;
    croak usage_import unless ($class eq 'Inline' and
			       $language eq 'C' and
			       @lines);
    for (@lines) {
	croak usage_import unless /\n/;
    }

    warn usage_deprecated_import if $^W;
    push @_, '_deprecated_import_';
    goto &bind;
}

#==============================================================================
# Process the with command
#==============================================================================
sub handle_with {
    my $pkg = shift;
    croak usage_with unless @_;
    for (@_) {
	croak usage unless /^[\w:]+$/;
	eval "require $_;";
	croak usage_with_bad($_) . $@ if $@;
	push @{$CONFIG{$pkg}{template}{WITH}}, $_;
    }
}

#==============================================================================
# Process the config options
#==============================================================================
sub handle_config {
    my $pkg = shift;
    while (@_) {
	my ($key, $value) = (shift, shift);
	croak usage if $key =~ /[\s\n]/;
	croak "Invalid Config option '$key'\n"
	  unless defined ${$default_config}{$key};
	$CONFIG{$pkg}{template}{$key} = $value;
    }
}

#==============================================================================
# Validate and store shortcut config options
#==============================================================================
sub handle_shortcuts {
    my $pkg = shift;

    for my $option (@_) {
	my $OPTION = uc($option);
	if ($shortcuts{$OPTION}) {
	    my ($method, $arg) = @{$shortcuts{$OPTION}};
	    $CONFIG{$pkg}{template}{$method} = $arg;
	}
	else {
	    croak usage_shortcuts($option);
	}
    }    
}

#==============================================================================
# Perform cleanup duties
#==============================================================================
sub DESTROY {
    my $o = shift;
    $o->clean_build if $o->{config}{CLEAN_BUILD_AREA};
}

#==============================================================================
# Clean the build directory from previous builds
#==============================================================================
sub clean_build {
    use strict;
    my ($prefix, $dir);
    my $o = shift;

    $prefix = $o->{config}{DIRECTORY};
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
# 
#==============================================================================
sub error_copy {
    require File::Copy;
    require File::Path;
    my ($src_file, $new_file);
    my $o = shift;
    delete @{$o->{parser}}{grep {!/^data$/} keys %{$o->{parser}}};
    my $src_dir = $o->{build_dir};
    my $new_dir = $o->{config}{DIRECTORY} . "errors";

    File::Path::rmtree($new_dir);
    File::Path::mkpath($new_dir);
    opendir DIR, $src_dir;
    while ($src_file = readdir(DIR)) {
	next unless -f "$src_dir/$src_file";
	($new_file = $src_file) =~ s/_?[0-9abcdef]{32}//g;
	File::Copy::copy("$src_dir/$src_file", "$new_dir/$new_file");
    }
}

#==============================================================================
# User wants to report a bug
#==============================================================================
sub reportbug {
    use strict;
    require Data::Dumper;
    my $o = shift;
    return if $o->{reportbug_handled}++;
    print STDERR <<END;
<-----------------------REPORTBUG Section------------------------------------->

REPORTBUG mode in effect.

Your Inline $o->{language_id} code will be processed in the build directory:

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
# Print a small report about the version of Inline
#==============================================================================
sub print_version {
    return if $version_printed++;
    print STDERR <<END;
You are using Inline.pm version $Inline::VERSION

END
}

#==============================================================================
# Print a small report if PRINT_INFO option is set.
#==============================================================================
sub print_info {
    use strict;
    my $o = shift;

    print STDERR <<END;
<-----------------------Information Section----------------------------------->

Information about the processing of your Inline $o->{language_id} code:

END
    
    print STDERR <<END if ($o->{mod_exists});
Your module is already compiled. It is located at:
$o->{location}

END

    print STDERR <<END if ($o->{mod_exists} and $o->{config}{FORCE_BUILD});
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
    
    eval {
	print STDERR $o->info;
    };
    print $@ if $@;

    print STDERR <<END;

<-----------------------End of Information Section---------------------------->
END
}

#==============================================================================
# Utility subroutines
#==============================================================================

#==============================================================================
# Make a path
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

#==============================================================================
# Nuke a path (nicely)
#==============================================================================
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

#==============================================================================
# Find the 'Inline' directory to use.
#==============================================================================
my $TEMP_DIR;
sub find_temp_dir {
    return $TEMP_DIR if $TEMP_DIR;
    
    my ($temp_dir, $home, $bin, $cwd, $env);
    $temp_dir = '';
    $env = $ENV{PERL_INLINE_DIRECTORY} || '';
    $home = $ENV{HOME} ? abs_path($ENV{HOME}) : '';
    
    if ($env and
	-d $env and
	-w $env) {
	$temp_dir = $env;
    }
    elsif ($cwd = abs_path('.') and
	   $cwd ne $home and
	   -d "$cwd/.Inline/" and
	   -w "$cwd/.Inline/") {
	$temp_dir = "$cwd/.Inline/";
    }
    elsif ($bin = $FindBin::Bin and
	   -d "$bin/.Inline/" and
	   -w "$bin/.Inline/") {
	$temp_dir = "$bin/.Inline/";
    } 
    elsif ($home and
	   -d "$home/.Inline/" and
	   -w "$home/.Inline/") {
	$temp_dir = "$home/.Inline/";
    } 
    elsif (defined $cwd and $cwd and
	   -d "$cwd/_Inline/" and
	   -w "$cwd/_Inline/") {
	$temp_dir = "$cwd/_Inline/";
    }
    elsif (defined $bin and $bin and
	   -d "$bin/_Inline/" and
	   -w "$bin/_Inline/") {
	$temp_dir = "$bin/_Inline/";
    } 
    elsif (defined $cwd and $cwd and
	   -d $cwd and
	   -w $cwd and
	   mkdir("$cwd/_Inline/", 0777)) {
	$temp_dir = "$cwd/_Inline/";
    }
    elsif (defined $bin and $bin and
	   -d $bin and
	   -w $bin and
	   mkdir("$bin/_Inline/", 0777)) {
	$temp_dir = "$bin/_Inline/";
    }

    croak "Couldn't find an appropriate DIRECTORY for Inline to use.\n"
      unless $temp_dir;
    return $TEMP_DIR = abs_path($temp_dir) . '/';
}

1;

__END__
