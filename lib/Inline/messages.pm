#==============================================================================
# Various warnings and errors used by Inline.pm
#==============================================================================
sub usage {
    my $usage = <<END;
Invalid usage of Inline module. Valid usages are:
    use Inline;
    use Inline language => "source-string", config-pair-list;
    use Inline language => "source-file", config-pair-list;
    use Inline language => [source-line-list], config-pair-list;
    use Inline language => 'DATA', config-pair-list;
    use Inline language => 'Config', config-pair-list;
    use Inline Config => config-pair-list;
    use Inline with => module-list;
    use Inline shortcut-list;
END

    $usage .= <<END if defined %Inline::config::languages;

Supported languages:
    ${\ join(', ', sort keys %Inline::config::languages)}

END
    return $usage;
}

sub usage_bind {
    my $usage = <<END;
Invalid usage of the Inline->bind() function. Valid usages are:
    Inline->bind(language => "source-string", config-pair-list);
    Inline->bind(language => "source-file", config-pair-list);
    Inline->bind(language => [source-line-list], config-pair-list);
END

    $usage .= <<END if defined %Inline::config::languages;

Supported languages:
    ${\ join(', ', sort keys %Inline::config::languages)}

END
    return $usage;
}

sub usage_bind_runtime {
    return <<END;
Inline->bind() may only be called at run time.

END
}

sub usage_use {
    my $module = shift;
    return <<END;
It is invalid to use '$module' directly. Please consult the Inline 
documentation for more information.

END
}

sub usage_Config {
    return <<END;
As of Inline v0.30, use of the Inline::Config module is no longer supported
or allowed. If Inline::Config exists on your system, it can be removed. See
the Inline documentation for information on how to configure Inline.
(You should find it much more straightforward than Inline::Config :-)

END
}

sub usage_language {
    my $language = shift;
    return <<END;
Error. You have specified '$language' as an Inline programming language.

I currently only know about the following languages:
    ${\ join(', ', sort keys %Inline::config::languages)}

If you have installed a support module for this language, try deleting the
config file from your BLIB directory, and run again.

END
}

sub usage_register {
    my ($language, $error) = @_;
    return <<END;
The module Inline::$language does not support the Inline API, because it does
properly support the register() method. This module will not work with Inline
and should be uninstalled from your system. Please advise your sysadmin.

The following error was generating from this module:
$error

END
}

sub usage_alias_used {
    my ($new_mod, $alias, $old_mod) = @_;
    return <<END;
The module Inline::$new_mod is attempting to define $alias as an alias.
But $alias is also an alias for Inline::$old_mod.

One of these modules needs to be corrected or removed.
Please notify the system administrator.

END
}

sub usage_with {
    return <<END;
Syntax error detected using 'use Inline with ...'.
Should be specified as:

    use Inline with => 'module1', 'module2', ..., 'moduleN';

END
}

sub usage_with_bad {
    my $mod = shift;
    return <<END;
Syntax error detected using 'use Inline with => "$mod";'.
'$mod' could not be found.

END
}

sub usage_shortcuts {
    my $shortcut = shift;
    return <<END;
Invalid shortcut '$shortcut' specified.

Valid shortcuts are:
    VERSION, INFO, FORCE, NOCLEAN, CLEAN, and REPORTBUG

END
}

sub usage_import {
    return <<END;
Calling Inline::import() directly is invalid. You probably want to use
the Inline->bind() function. Please consult the Inline documentation.

END
}

sub usage_deprecated_import {
    return <<END;
Warning. The use of Inline->import() has been deprecated since Inline v0.30.
It will be removed from the Inline module soon. You probably want to use one 
of the following supported syntaxes:
    use Inline language => 'DATA';
      or
    Inline->bind(language => [source-lines]);
Please consult the Inline documentation for more information.

END
}

sub usage_BLIB {
    my $value = shift;
    return <<END;
Invalid value '$value' for config option BLIB

END
}

sub usage_WITH {
    return <<END;
Config option WITH must be a module name or an array ref of module names

END
}

sub usage_loader {
    return <<END;
ERROR. The loader that was invoked is for compiled languages only.

END
}

1;
