package Object::LocalVars;
use 5.006;
use strict;
use warnings;
our $VERSION = '0.11';

# Required modules
use Carp;
use Scalar::Util qw(refaddr);
# use Sub::Uplevel; # not using for now

# Exporting
use Exporter 'import';
our @EXPORT = qw(   caller give_methods new DESTROY 
                    MODIFY_SCALAR_ATTRIBUTES MODIFY_CODE_ATTRIBUTES );

#--------------------------------------------------------------------------#
# caller
#--------------------------------------------------------------------------#

# custom caller routine ignores this module and keeps looking upwards.
# can't use Sub::Uplevel due to an off-by-one issue in the current version

use subs 'caller';
sub caller {
    my ($uplevel) = @_;
    $uplevel ||= 0;
    $uplevel++ while ( (CORE::caller($uplevel+1))[0] eq __PACKAGE__ );
    my @caller = CORE::caller($uplevel+1);
    return wantarray ? ( @_ ? @caller : @caller[0 .. 2] ) : $caller[0];
}

#--------------------------------------------------------------------------#
# give_methods
#--------------------------------------------------------------------------#

sub give_methods {
    my $caller = caller;
    _install_public_methods($caller);
    _install_protected_methods($caller);
    _install_private_methods($caller);
    return 1;
}

#--------------------------------------------------------------------------#
# new()
#--------------------------------------------------------------------------#

sub new {
    no strict 'refs';
    my $class = shift;
    $class = ref($class) if ref($class);
    my @args = defined *{$class."::PREBUILD"}{CODE} ? 
        &{$class."::PREBUILD"}(@_) : @_;
    my @parents = @{"${class}::ISA"};
    my $self;
    for (@parents) {
        $self = $_->new(@args), last if $_->can("new");
    }
    $self = \(my $scalar) unless $self;
    bless $self, $class;
    $self->BUILD(@_) if defined *{$class."::BUILD"}{CODE};
    return $self;
}

#--------------------------------------------------------------------------#
# DESTROY
#--------------------------------------------------------------------------#

sub DESTROY {
    no strict 'refs';
    my $self = shift;
    my $class = ref $self;
    $self->DEMOLISH if defined *{$class."::DEMOLISH"}{CODE};
    my $addr = refaddr $self;
    for my $p ( keys %{"${class}::DATA::"} ) {
        delete (${"${class}::DATA::$p"}{$addr});
    }
    my @parents = @{"${class}::ISA"};
    bless ($self, $parents[0]) if @parents;
}

#--------------------------------------------------------------------------#
# MODIFY_CODE_ATTRIBUTES
#--------------------------------------------------------------------------#

my (%public_methods, %protected_methods, %private_methods);
sub MODIFY_CODE_ATTRIBUTES {
    my ($package, $referent, @attrs) = @_;
    for my $attr (@attrs) {
        no strict 'refs';
        if ( $attr =~ /^(?:Method|Pub)$/ ) {
            push @{$public_methods{$package}}, $referent;
            undef $attr;
        }
        elsif ($attr eq "Prot") {
            push @{$protected_methods{$package}}, $referent;
            undef $attr;
        }
        elsif ($attr eq "Priv") {
            push @{$private_methods{$package}}, $referent;
            undef $attr;
        }
    }
    return grep {defined} @attrs;    
}

#--------------------------------------------------------------------------#
# MODIFY_SCALAR_ATTRIBUTES
#--------------------------------------------------------------------------#

sub MODIFY_SCALAR_ATTRIBUTES {
    my ($OL_PACKAGE, $referent, @attrs) = @_;
    for my $attr (@attrs) {
        no strict 'refs';
        if ($attr eq "Pub") {
            my $symbol = _findsym($OL_PACKAGE, $referent) or die;
            my $OL_NAME = *{$symbol}{NAME};
            ${$OL_PACKAGE."::DATA::".$OL_NAME} = {}; # make it exist
            *{$OL_PACKAGE."::".$OL_NAME} =
                sub { 
                    my $self = shift;
                    return ${$OL_PACKAGE."::DATA::".$OL_NAME}{refaddr $self};
                };
            *{$OL_PACKAGE."::set_".$OL_NAME} =
                sub { 
                    my ($self, $value) = @_;
                    ${$OL_PACKAGE."::DATA::".$OL_NAME}{refaddr $self} = $value;
                    return $self;
                };
            undef $attr;
        } 
        elsif ($attr eq "Prot") {
            my $symbol = _findsym($OL_PACKAGE, $referent) or die;
            my $OL_NAME = *{$symbol}{NAME};
            ${$OL_PACKAGE."::DATA::".$OL_NAME} = {}; # make it exist
            *{$OL_PACKAGE."::".$OL_NAME} = sub { 
                my $self = shift;
                my ($caller,undef,undef,$fcn) = caller(0);
                croak "$OL_NAME is a protected property and can't be read from $fcn in $caller" 
                    unless UNIVERSAL::isa( $caller, $OL_PACKAGE );
                return ${$OL_PACKAGE."::DATA::".$OL_NAME}{refaddr $self};
            };
            *{$OL_PACKAGE."::set_$OL_NAME"} = sub { 
                my ($self, $value) = @_;
                my ($caller,undef,undef,$fcn) = caller(0);
                croak "$OL_NAME is a protected property and can't be read from $fcn in $caller" 
                    unless UNIVERSAL::isa( $caller, $OL_PACKAGE );
                ${$OL_PACKAGE."::DATA::".$OL_NAME}{refaddr $self} = $value;
                return $self;
            };
            undef $attr;
        }
        elsif ( $attr =~ /^(?:Prop|Priv)$/ ) {
            my $symbol = _findsym($OL_PACKAGE, $referent) or die;
            my $OL_NAME = *{$symbol}{NAME};
            ${$OL_PACKAGE."::DATA::".$OL_NAME} = {}; # make it exist
            # no accessors installed for private 
            undef $attr;
        }
        elsif ($attr =~ /^(?:Class|ClassPriv)$/ ) {
            my $symbol = _findsym($OL_PACKAGE, $referent) or die;
            my $OL_NAME = *{$symbol}{NAME};
            ${$OL_PACKAGE."::CLASSDATA"}{$OL_NAME} = undef; # make it exist
            undef $attr;
        }
        elsif ($attr =~ /^(?:ClassProt)$/ ) {
            my $symbol = _findsym($OL_PACKAGE, $referent) or die;
            my $OL_NAME = *{$symbol}{NAME};
            ${$OL_PACKAGE."::CLASSDATA"}{$OL_NAME} = undef; # make it exist
            *{$OL_PACKAGE."::".$OL_NAME} = sub { 
                my $class = shift;
                my ($caller,undef,undef,$fcn) = caller(0);
                croak "$OL_NAME is a protected property and can't be read from $fcn in $caller" 
                    unless UNIVERSAL::isa( $caller, $OL_PACKAGE );
                return ${$OL_PACKAGE."::CLASSDATA"}{$OL_NAME};
            };
            *{$OL_PACKAGE."::set_$OL_NAME"} = sub { 
                my ($class, $value) = @_;
                my ($caller,undef,undef,$fcn) = caller(0);
                croak "$OL_NAME is a protected property and can't be read from $fcn in $caller" 
                    unless UNIVERSAL::isa( $caller, $OL_PACKAGE );
                ${$OL_PACKAGE."::CLASSDATA"}{$OL_NAME} = $value;
                return $class;
            };
            undef $attr;
        }
        elsif ($attr =~ /^(?:ClassPub)$/ ) {
            my $symbol = _findsym($OL_PACKAGE, $referent) or die;
            my $OL_NAME = *{$symbol}{NAME};
            ${$OL_PACKAGE."::CLASSDATA"}{$OL_NAME} = undef; # make it exist
            *{$OL_PACKAGE."::".$OL_NAME} = sub { 
                my $class = shift;
                return ${$OL_PACKAGE."::CLASSDATA"}{$OL_NAME};
            };
            *{$OL_PACKAGE."::set_$OL_NAME"} = sub { 
                my ($class, $value) = @_;
                ${$OL_PACKAGE."::CLASSDATA"}{$OL_NAME} = $value;
                return $class;
            };
            undef $attr;
        }
    }
    return grep {defined} @attrs;    
}

#--------------------------------------------------------------------------#
# _findsym
#--------------------------------------------------------------------------#

my %symcache;
sub _findsym {
    no strict 'refs';
    my ($pkg, $ref, $type) = @_;
    return $symcache{$pkg,$ref} if $symcache{$pkg,$ref};
    $type ||= ref($ref);
    my $found;
    foreach my $sym ( values %{$pkg."::"} ) {
        return $symcache{$pkg,$ref} = \$sym
            if *{$sym}{$type} && *{$sym}{$type} == $ref;
    }
}

#--------------------------------------------------------------------------#
# _install_private_methods
#--------------------------------------------------------------------------#

sub _install_private_methods {
    no strict 'refs';
    no warnings 'redefine';
    my ($package) = @_;
    for my $coderef ( @{$private_methods{$package}} ) {
        my $symbol = _findsym($package, $coderef) or die;
        my $name = *{$symbol}{NAME};
        *{$package."::METHODS::$name"} = $coderef;
        *{$package."::$name"} = sub { 
            my ($obj, @args) = @_;
            my ($caller) = caller();
            croak "$name is a private method and can't be called from $package"
                unless $caller eq $package;
            local ${$package."::self"} = $obj;
            my $props = [ keys %{$package."::CLASSDATA"} ];
            push @$props, keys %{$package."::DATA::"} if ref($obj);
            my $uplevel = 2;
            if (@$props) {
                _wrap_props($obj, $props, $package, $uplevel, $coderef, \@args);
            } else {
                local $Carp::CarpLevel = $Carp::CarpLevel + $uplevel;
                $coderef->(@args);
            }
        }; # end sub 
    };
}

#--------------------------------------------------------------------------#
# _install_protected_methods
#--------------------------------------------------------------------------#

sub _install_protected_methods {
    no strict 'refs';
    no warnings 'redefine';
    my ($package) = @_;
    for my $coderef ( @{$protected_methods{$package}} ) {
        my $symbol = _findsym($package, $coderef) or die;
        my $name = *{$symbol}{NAME};
        *{$package."::METHODS::$name"} = $coderef;
        *{$package."::$name"} = sub { 
            my ($obj, @args) = @_;
            my ($caller) = caller();
            croak "$name is a protected method and can't be called from $package"
                unless UNIVERSAL::isa( $caller, $package );
            local ${$package."::self"} = $obj;
            my $props = [ keys %{$package."::CLASSDATA"} ];
            push @$props, keys %{$package."::DATA::"} if ref($obj);
            my $uplevel = 2;
            if (@$props) {
                _wrap_props($obj, $props, $package, $uplevel, $coderef, \@args);
            } else {
                local $Carp::CarpLevel = $Carp::CarpLevel + $uplevel;
                $coderef->(@args);
            }
        }; # end sub 
    };
}

#--------------------------------------------------------------------------#
# _install_public_methods
#--------------------------------------------------------------------------#

sub _install_public_methods {
    no strict 'refs';
    no warnings 'redefine';
    my ($package) = @_;
    for my $coderef ( @{$public_methods{$package}} ) {
        my $symbol = _findsym($package, $coderef) or die;
        my $name = *{$symbol}{NAME};
        *{$package."::METHODS::$name"} = $coderef;
        *{$package."::$name"} = sub { 
            my ($obj, @args) = @_;
            local ${$package."::self"} = $obj;
            my $props = [ keys %{$package."::CLASSDATA"} ];
            push @$props, keys %{$package."::DATA::"} if ref($obj);
            my $uplevel = 2;
            if (@$props) {
                _wrap_props($obj, $props, $package, $uplevel, $coderef, \@args);
            } else {
                local $Carp::CarpLevel = $Carp::CarpLevel + $uplevel;
                $coderef->(@args);
            }
        }; # end sub 
    };
}

#--------------------------------------------------------------------------#
# _wrap_props
#--------------------------------------------------------------------------#

sub _wrap_props {
    no strict 'refs';
    my ($obj, $props, $caller, $uplevel, $fcn, $args) = @_;
    my $p = shift @$props;
    my $is_class = exists ${$caller."::CLASSDATA"}{$p};
    local *{$caller."::$p"} =  $is_class ?
        \${$caller."::CLASSDATA"}{$p} :
        \${$caller."::DATA::$p"}{refaddr $obj};
    $uplevel++;
    if (@$props) {
        _wrap_props ($obj, $props, $caller, $uplevel, $fcn, $args);
    } else {
        local $Carp::CarpLevel = $Carp::CarpLevel + $uplevel;
        $fcn->(@$args);
    }
}

1; #this line is important and will help the module return a true value
__END__
#--------------------------------------------------------------------------#
# main pod documentation 
#--------------------------------------------------------------------------#

=head1 NAME

Object::LocalVars - Outside-in objects with local aliasing of $self and object
variables

=head1 SYNOPSIS

  package My::Object;
  use strict;
  use Object::LocalVars;

  give_methods our $self;  # this exact line is required

  our $field1 : Prop;
  our $field2 : Prop;

  sub as_string : Method { 
    return "$self has properties '$field1' and '$field2'";
  }
  
=head1 DESCRIPTION

I<This is an early development release.  Documentation is incomplete and the
API may change.  Do not use for production purposes.  Comments appreciated.>

This module helps developers create "outside-in" objects.  Properties (and
C< $self >) are declared as package globals.  Method calls are wrapped such that 
these globals take on a local value that is correct for the specific calling
object and the duration of the method call.  I.e. C< $self > is locally aliased
to the calling object and properties are locally aliased to the values of the
properties for that object.  The package globals themselves are empty and data
are stored in a separate namespace for each package, keyed off the reference
addresses of the objects.

"Outside-in" objects are similar to "inside-out" objects, which store data in a
single lexical hash closure for each property that is keyed off the reference
addresses of the objects.  Both differ from "traditional" Perl objects, which
store data for the object directly within a blessed reference to a data
structure.  For both "outside-in" and "inside-out" objects, data is stored
centrally and the blessed reference is simply a key to look up the right data
in the central data store.

Unlike with "inside-out" objects, the use of package variables for 
"outside-in" objects allows for the use of local symbol table manipulation.
This allows Object::LocalVars to deliver a variety of features -- though with
some drawbacks.

=head2 Features

=over

=item * 

Provides $self automatically to methods without C< my $self = shift > and the
like

=item * 

Provides dynamic aliasing of properties within methods -- methods can access
properties directly as variables without the overhead of calls to
accessors or mutators, eliminating the overhead of these calls in methods  

=item * 

Array and hash properties may be accessed via direct dereference of a 
simple variable, allowing developers to push, pop, splice, etc. without
the usual tortured syntax to dereference an accessor call

=item *

Properties no longer require accessors to have compile time syntax checking
under C< use strict >

=item * 

Uses attributes to mark properties and methods, but only in the BEGIN phase so
should be mod_perl friendly (though I haven't tested this yet)

=item *

Provides attributes for public, protected and private properties, class
properties and methods

=item *

Does not use source filtering

=item *

Orthogonality -- can subclass just about any other class, regardless of
implementation.  (Also a nice feature of some "inside-out" implementations)

=back

=head2 Drawbacks

=over

=item * 

Method efficiency -- wrappers around methods create extra overhead on method
calls

=item *

Minimal encapsulation -- data is hidden but still publically accessible, unlike
approaches that use lexical closures to create strong encapsulation

=item *

Designed for single inheritance only.  Multiple inheritance may or may not
work depending on the exact circumstances

=back

=head1 USAGE

=head2 Overview

(TODO: discuss general usage, from importing through various pieces that can
be defined)

=head2 Declaring Object Properties

(TODO: Define object properties)

Properties are declared by specifying a package variable using C< our > and an
appropriate attribute.  There are a variety of attributes (and aliases for
attributes) available which result in different degrees of privacy and different
rules for creating accessors and mutators.

(TODO: Discuss aliasing)

Object::LocalVars provides the following attributes for object properties:

  our $prop1 : Prop;
  our $prop2 : Priv;

Either of these attributes declare a private property.  Private properties are
aliased within methods, but no accessors or mutators are created.  This is the
recommended default unless specific alternate functionality is needed. (Of course,
developers are free to write methods that act as accessors or mutators.)

  our $prop3 : Prot;

This attribute declares a protected property.  Protected properties are aliased
within methods, and an accessor and mutator are created.  However, the accessor
and mutator may only be called by the declaring package or a subclass of it.

  our $prop4 : Pub;

This attribute declares a public property.  Public properties are aliased
within methods, and an accessor and mutator are created that may be called from
anywhere.

  our $prop5 : ReadOnly;

(Not yet implemented)  This attribute declares a public property.  Public
properties are aliased within methods, and an accessor and mutator are created.
The accessor may be called from anywhere, but the mutator may only be called
from the declaring package or a subclass of it.

=head2 Declaring Class Properties

Class properties work like object properties, but the value of a class property
is the same value all objects (or when used in a class method).

Object::LocalVars provides the following attributes for class properties:

  our $class1 : Class;
  our $class2 : ClassPriv;

Either of these attributes declare a private class property.  Private class
properties are aliased within methods, but no accessors or mutators are
created.  This is the recommended default unless specific alternate
functionality is needed.

  our $class3 : ClassProt;

This attribute declares a protected class property.  Protected class properties
are aliased within methods, and an accessor and mutator are created.  However,
the accessor and mutator may only be called by the declaring package or a
subclass of it.

  our $class4 : ClassPub;

This attribute declares a public class property.  Public class properties are
aliased within methods, and an accessor and mutator are created that may be
called from anywhere.

  our $class5 : ReadOnly;

(Not yet implemented)  This attribute declares a public class property.  Public
class properties are aliased within methods, and an accessor and mutator are
created.  The accessor may be called from anywhere, but the mutator may only be
called from the declaring package or a subclass of it.


=head2 Declaring Methods

  sub foo : Method {
    my ($arg1, $arg2) = @_;  # no need to shift $self
    # $self and all properties automatically aliased
  }

(TODO: define methods)

(TODO: discuss how $self and properties are made available within methods)

Object::LocalVars provides the following attributes for subroutines:

  sub fcn1 : Method { }
  sub fcn2 : Pub { }

Either of these attributes declare a public method.  Public methods may be
called from anywhere.  This is the recommended default unless specific
alternate functionality is needed.

  :Prot

This attribute declares a protected method.  Protected methods may be called
only from the declaring package or a subclass of it.  

  :Priv

This attribute declares a private method.  Private methods may only be
called only from the declaring package.  Private methods should generally be
called directly, not using method syntax -- the major purpose of this attribute
is to provide a wrapper that prevents the subroutine from being called outside
the declaring package.  See L</Hints and Tips>.

=head2 Accessors and Mutators

  our $foo : Pub;     # :Pub creates an accessor and mutator
  $obj->foo;          # returns value of foo for $obj
  $obj->set_foo($val) # sets foo to $val and returns $obj
  
(TODO: define and describe)

=head2 Constructors and Destructors

(TODO: define)

(TODO: discuss calling pattern and usage of BUILD, PREBUILD, DEMOLISH)

=head2 Hints and Tips

I<Calling private methods on $self>

Good style for private method calling in traditional Perl object-oriented
programming is to call private methods directly, C< foo($self,@args) >, rather
than with method lookup, C<< $self->foo(@args) >>.  With Object::LocalVars, a
private method should be called as C< foo(@args) > as the local aliases for $self
and the properties are already in place.

I<Avoiding hidden internal data>

For a package using Object::LocalVars, e.g. C< My::Package >, object properties
are stored in C< My::Package::DATA >, class properties are stored in 
C< My::Package::CLASSDATA >, and methods are stored in 
C< My::Package::METHODS >. Do not access these areas directly or overwrite 
them with other global data or unexpected results are guaranteed to occur.

=head1 METHODS TO BE WRITTEN BY A DEVELOPER

=head2 C<PREBUILD()>

  # Example
  sub PREBUILD {
    my @args = @_;
    # filter @args in some way
    return @args;
  }

This subroutine may be written to filter arguments given to C<new()> before
passing them to a superclass C<new()>.  I<This must not be tagged with a
C<:Method> attribute> or equivalent as it is called before any object is
available.  The primary purpose of this subroutine is to strip out any
arguments that would cause the superclass constructor to die and/or to add any
default arguments that should always be passed to the superclass constructor.

=head2 C<BUILD()>

  # Example
  # Assuming our $count : Class;
  sub BUILD : Method {
    my %init = @_;
    $prop1 = $init{prop1};
    $count++;
  }

This method may be defined to initialize the object after it is created.  If
available, it is called at the end of the constructor.  The C<@_> array
contains the original array passed to C<new()> -- regardless of any filtering
by C<PREBUILD()>.

=head2 C<DEMOLISH()>

  # Example
  # Assume our $count : Class;
  sub DEMOLISH : Method {
    $count--;
  }

This method may be defined to provide some cleanup actions when the object goes
out of scope and is destroyed.  If available, it is called at the start of
the destructor (i.e C<DESTROY>).

=head1 METHODS AUTOMATICALLY EXPORTED

These methods will be automatically exported for use.  This export can 
be prevented by passing the method name preceded by a "!" in a list 
after the call to "use Object::LocalVars".  E.g.:

  use Object::LocalVars qw( !new );

This is generally not needed or recommended, but is available should
developers need some very customized behavior in C<new()> or C<DESTROY()> 
that can't be achieved with C<BUILD()> and C<DEMOLISH()>.

=head2 C<give_methods()>

  give_methods our $self;

Installs wrappers around all subroutines tagged as methods.  This function
(and the declaration of C<our $self>) I<must> be used in all classes built
with Object::LocalVars.

=head2 C<new()>

The constructor.  This is not used within Object::LocalVars directly but is exported
automatically when Object::LocalVars is imported.  C<new()> calls C<PREBUILD> (if
it exists), blesses a new object either from a superclass (if one exists) or
from scratch, and calls C<BUILD> (if it exists).  Classes built with
Object::LocalVars have this available by default and generally do not need their
own constructor.

=head2 C<DESTROY()>

A destructor.  This is not used within Object::LocalVars directly but is exported
automatically when Object::LocalVars is imported.  C<DESTROY()> calls C<DEMOLISH()>
(if it exists) and reblesses the object into the first package in @ISA that 
can DESTROY (if any) so that destruction chaining will happen automatically.

=head2 C<caller()>

This subroutine is exported automatically and emulates the built-in C<caller()>
with the exception that if the caller is Object::LocalVars (i.e. from the wrapper
functions), it will continue to look up the caller stack until the first
non-Object::LocalVars package is found.

=head1 BENCHMARKING

Forthcoming.  In short, Object::LocalVars is faster than traditional approaches
if the ratio of property access within methods is high relative to number of
method calls.  Slower than traditional approaches if there are many method
calls that individually do little property access. 

=head1 SEE ALSO

These other modules provide similiar functionality and inspired this one.

=over

=item *

L<Class::Std> -- framework for inside-out objects; supports
multiple-inheritance

=item *

L<Lexical::Attributes> -- inside-out objects; provides $self and other 
syntactic sugar via source filtering

=item *

L<Spiffy> -- a "magic foundation class" for object-oriented programming with
lots of syntactic tricks via source filtering

=back

=head1 INSTALLATION

The following commands will build, test, and install this module:

 perl Build.PL
 perl Build
 perl Build test
 perl Build install

=head1 BUGS

Please report bugs using the CPAN Request Tracker at 
http://rt.cpan.org/NoAuth/Bugs.html?Dist=/home/david/projects/Object-LocalVars

=head1 AUTHOR

David A Golden (DAGOLDEN)

dagolden@cpan.org

http://dagolden.com/

=head1 COPYRIGHT

Copyright (c) 2005 by David A Golden

This program is free software; you can redistribute
it and/or modify it under the same terms as Perl itself.

The full text of the license can be found in the
LICENSE file included with this module.

=cut
