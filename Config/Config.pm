package Inline::Config;

use strict;
use vars qw($VERSION
	    %MAKEFILE
	    $AUTO_INCLUDE_C
	    $CLEAN_AFTER_BUILD
	    $CLEAN_BUILD_AREA
	    $FORCE_BUILD
	    $SITE_INSTALL
	    $PRINT_INFO
	    $REPORTBUG
	    $TEMP_DIR
	    $BUILD_PREFIX
	    $INSTALL_PREFIX
	    $INSTALL_LIB
	    $AUTOLOAD
	    $INSTALL_SUFFIX
	   );
$VERSION = '0.26';

use Config;
use Carp;
use Cwd qw(abs_path chdir);
use FindBin;

#==============================================================================
# Global attributes
#==============================================================================
%MAKEFILE = ();

$AUTO_INCLUDE_C = <<'END';
#include "EXTERN.h"
#include "perl.h"
#include "XSUB.h"
#include "INLINE.h"
END

$CLEAN_AFTER_BUILD = 1;
$CLEAN_BUILD_AREA = 0;
$FORCE_BUILD = 0;
$PRINT_INFO = 0;
$REPORTBUG = 0;
$SITE_INSTALL = 0;

$TEMP_DIR = '';
$BUILD_PREFIX = '';
$INSTALL_PREFIX = '';
$INSTALL_LIB = '';

#==============================================================================
# Public methods
#==============================================================================
sub new {
    bless \%Inline::Config::, shift;
}

sub makefile {
    my $o = '';
    $o = shift if ref($_[0]) eq 'Inline::Config';
    while (@_) {
	my $key = shift;
	$MAKEFILE{$key} = shift;
    }
    return $o;
}

AUTOLOAD {
    (my $autoload = $AUTOLOAD) =~ s/.*::(.*)/$1/;
    my $o;
    $o = shift if ref($_[0]) eq 'Inline::Config';
    $o ||= Inline::Config::new;
    my $sub = uc($autoload);
    croak qq{Unknown attribute "$autoload" for Inline::Config}
    unless exists $o->{$sub}; 
    no strict 'refs';
    $ {$sub} = shift;
    return $o;
}

#==============================================================================
# Public methods
#==============================================================================
sub _get_build_prefix {
    if ($BUILD_PREFIX) {
	$BUILD_PREFIX = abs_path($BUILD_PREFIX) . '/';
    }
    else {
	$BUILD_PREFIX ||= _find_temp_dir();
    }
    return $BUILD_PREFIX;
}

sub _get_install_prefix {
    if ($INSTALL_PREFIX) {
	$INSTALL_PREFIX = abs_path($INSTALL_PREFIX) . '/';
    }
    else {
	$INSTALL_PREFIX ||= _find_temp_dir();
    }
    return $INSTALL_PREFIX;
}

sub _get_install_suffix {
    return $INSTALL_SUFFIX if ($INSTALL_SUFFIX && 
			       $INSTALL_SUFFIX =~ m|^/|
			      );
    # MSWin32 needs abs_path
    my $suffix = abs_path($Config::Config{sitearch});
    $suffix =~ s|^.*(/site.*)$|$1| 
      or croak <<'END';
Can\'t parse your perl configuration to find an appropriate install suffix.
Try setting $Inline::Config::INSTALL_SUFFIX yourself.
END
    return $INSTALL_SUFFIX = $suffix;
}

sub _get_install_lib {
    return $INSTALL_LIB = $INSTALL_LIB ||
      _get_install_prefix() . 'lib/perl5' . _get_install_suffix();
}

my $temp_dir_checked = '';
sub _find_temp_dir {
    if ($TEMP_DIR) {
	if ($temp_dir_checked ne $TEMP_DIR) {
	    croak <<END unless (-d $TEMP_DIR and -w $TEMP_DIR);
Invalid temporary directory specified: "$TEMP_DIR"
Either non-existent or unwritable
END
	    $temp_dir_checked = $TEMP_DIR = abs_path($TEMP_DIR) . '/';
	}
	return $TEMP_DIR;
    }
    
    my ($temp_dir, $home, $bin, $cwd, $env);
    $temp_dir = '';
    $env = $ENV{PERL_INLINE_BLIB} || '';
    $home = $ENV{HOME} ? abs_path($ENV{HOME}) : '';
    
    if ($env and
	-d $env and
	-w $env) {
	$temp_dir = $env;
    }
    elsif ($cwd = abs_path('.') and
	   $cwd ne $home and
	   -d "$cwd/blib_I/" and
	   -w "$cwd/blib_I/") {
	$temp_dir = "$cwd/blib_I/";
    }
    elsif ($bin = $FindBin::Bin and
	   -d "$bin/blib_I/" and
	   -w "$bin/blib_I/") {
	$temp_dir = "$bin/blib_I/";
    } 
    elsif (-d "/tmp/blib_I/" and
	   -w "/tmp/blib_I/") {
	$temp_dir = "/tmp/blib_I/";
    } 
    elsif ($home and
	   -d "$home/blib_I/" and
	   -w "$home/blib_I/") {
	$temp_dir = "$home/blib_I/";
    } 
    elsif ($home and
	   -d "$home/.blib_I/" and
	   -w "$home/.blib_I/") {
	$temp_dir = "$home/.blib_I/";
    }
    elsif (-d $bin and
	   -w $bin and
	   mkdir("$bin/blib_I/", 0777)) {
	$temp_dir = "$bin/blib_I/";
    }
    elsif (-d $cwd and
	   -w $cwd and
	   mkdir("$cwd/blib_I/", 0777)) {
	$temp_dir = "$cwd/blib_I/";
    }

    croak "Couldn't find an appropriate temporary directory to build in\n"
      unless $temp_dir;
    return $temp_dir_checked = $TEMP_DIR = abs_path($temp_dir) . '/';
}

1;
__END__
