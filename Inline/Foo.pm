package Inline::Foo;
$VERSION = '0.01';
require Inline;
@ISA = qw(Inline);
use strict;
use Carp;

sub register {
    return {
	    language => 'Foo',
	    aliases => ['foo'],
	    type => 'interpreted',
	    suffix => 'foo',
	   };
}

sub usage_config { 
    my $key = shift;
    "'$key' is not a valid config option for Inline::Foo\n";
}

sub usage_config_bar { 
    "Invalid value for Inline::Foo config option BAR";
}

sub validate {
    my $o = shift;
    $o->{ILSM}{PATTERN} ||= 'foo-';
    $o->{ILSM}{BAR} ||= 0;
    while (@_) {
	my ($key, $value) = splice @_, 0, 2;
	if ($key eq 'PATTERN') {
	    $o->{ILSM}{PATTERN} = $value;
	    next;
	}
	if ($key eq 'BAR') {
	    croak usage_config_bar
	      unless $value =~ /^[01]$/;
	    $o->{ILSM}{BAR} = $value;
	    next;
	}
	croak usage_config($key);
    }
}

sub build {
    my $o = shift;
    my $code = $o->{code};
    my $pattern = $o->{ILSM}{PATTERN};
    $code =~ s/$pattern//g;
    $code =~ s/bar-//g if $o->{ILSM}{BAR};
    sleep 1 if $o->{config}{FORCE_BUILD};
    {
	package Foo::Tester;
	eval $code;
    }
    croak "Foo build failed:\n$@" if $@;
    my $dir = $o->{location};
    $dir =~ s/(.*[\\\/]).*/$1/;
    $o->mkpath($dir) unless -d $dir;
    open FOO, "> $o->{location}"
      or croak "Can't open $o->{location} for output\n$!";
    print FOO $code;
    close FOO;
}

sub load {
    my $o = shift;
    open FOO, "< $o->{location}"
      or croak "Can't open $o->{location} for output\n$!";
    my $code = join '', <FOO>;
    close FOO;
    eval "package $o->{pkg};\n$code";
    croak "Unable to load Foo module $0->{location}:\n$@" if $@;
}

sub info {
    my $o = shift;
}

1;

__END__
