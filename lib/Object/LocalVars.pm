package Object::LocalVars;
use 5.006;
use strict;
use warnings;

our $VERSION = "0.13";

#--------------------------------------------------------------------------#
# Required modules
#--------------------------------------------------------------------------#

use Config;
use Carp;
use Scalar::Util qw( weaken );

#--------------------------------------------------------------------------#
# Exporting -- wrap import so we can check for necessary warnings
#--------------------------------------------------------------------------#

use Exporter;

our @EXPORT = qw(   
    caller give_methods new DESTROY CLONE
    MODIFY_SCALAR_ATTRIBUTES MODIFY_CODE_ATTRIBUTES 
);

sub import {

    # check if threads are available
    if( $Config{useithreads} ) {
        my $caller = caller(0);
        
        # Perl < 5.8 doesn't use CLONE, which we need if threads are in use
        if ( $] < 5.008 && $INC{'threads.pm'} ) {
            carp "Warning: Object::LocalVars thread support requires perl 5.8";
        }
        
        # Warn about sharing, but not for Test:: modules which always
        # share if any threads are enabled
        if ( $INC{'threads/shared.pm'} && ! $INC{'Test/Builder.pm'} ) {
            carp   "Warning: threads::shared is enabled, but $caller uses"
                 . " Object::LocalVars (which does not allow shared objects)";
        }
    }
    
    # Hand off the rest of the import
    goto &Exporter::import;
}

#--------------------------------------------------------------------------#
# Declarations
#--------------------------------------------------------------------------#
                    
my (%public_methods, %protected_methods, %private_methods);

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
    my $package = caller;
    for ( @{$public_methods{$package}} ) {
        _install_wrapper($package, $_, "public");
    };
    for ( @{$protected_methods{$package}} ) {
        _install_wrapper($package, $_, "protected");
    };
    for ( @{$private_methods{$package}} ) {
        _install_wrapper($package, $_, "private");
    };
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

    # leftmost superclass creates object if it can
    my $self;
    for (@{"${class}::ISA"}) {
        $self = $_->new(@args), last if $_->can("new");
    }
    $self = \(my $scalar) unless $self;
    bless $self, $class;
    my $addr = Object::LocalVars::_ident $self;
    ${$class . "::TRACKER"}{$addr} = $self;
    weaken ${$class . "::TRACKER"}{$addr}; # don't let this stop destruction
    
    $self->BUILD(@_) if defined *{$class."::BUILD"}{CODE};
    return $self;
}

#--------------------------------------------------------------------------#
# CLONE
#--------------------------------------------------------------------------#

sub CLONE {
    no strict 'refs';
    my $class = shift;
    for my $old_obj_id ( keys %{$class . "::TRACKER"} ) {
        my $new_obj_id = Object::LocalVars::_ident(
            ${$class . "::TRACKER"}{$old_obj_id}
        );
        for my $prop ( keys %{"${class}::DATA::"} ) {
            my $qualified_name = $class . "::DATA::$prop";
            $$qualified_name{ $new_obj_id } = $$qualified_name{ $old_obj_id };
            delete $$qualified_name{ $old_obj_id };
        }
        ${$class . "::TRACKER"}{$new_obj_id} = $new_obj_id;
        delete ${$class . "::TRACKER"}{$old_obj_id};
    }
    return 1;
}

#--------------------------------------------------------------------------#
# DESTROY
#--------------------------------------------------------------------------#

sub DESTROY {
    no strict 'refs';
    my $self = shift;
    my $class = ref $self or return;
    $self->DEMOLISH if defined *{$class."::DEMOLISH"}{CODE};
    my $addr = Object::LocalVars::_ident $self;
    for ( keys %{"${class}::DATA::"} ) {
        delete (${"${class}::DATA::$_"}{$addr});
    }
    delete ${$class . "::TRACKER"}{$addr};
    for ( @{"${class}::ISA"} ) {
        if ( $_->can("DESTROY") ) {
            bless ($self, $_);
            return;
        }
    }
}

#--------------------------------------------------------------------------#
# MODIFY_CODE_ATTRIBUTES
#--------------------------------------------------------------------------#

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
            _install_accessors( $OL_PACKAGE, $referent, "public", 0 );
            undef $attr;
        } 
        elsif ($attr eq "Prot") {
            _install_accessors( $OL_PACKAGE, $referent, "protected", 0 );
            undef $attr;
        }
        elsif ( $attr =~ /^(?:Prop|Priv)$/ ) {
            _install_accessors( $OL_PACKAGE, $referent, "private", 0 );
            undef $attr;
        }
        elsif ($attr =~ /^(?:Class|ClassPriv)$/ ) {
            _install_accessors( $OL_PACKAGE, $referent, "private", 1 );
            undef $attr;
        }
        elsif ($attr =~ /^(?:ClassProt)$/ ) {
            _install_accessors( $OL_PACKAGE, $referent, "protected", 1 );
            undef $attr;
        }
        elsif ($attr =~ /^(?:ClassPub)$/ ) {
            _install_accessors( $OL_PACKAGE, $referent, "public", 1 );
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
# _gen_accessor
#--------------------------------------------------------------------------#

sub _gen_accessor {
    my ($package, $name, $classwide) = @_;
    return $classwide 
        ? "return \$${package}::CLASSDATA{${name}}"
        : "return \$${package}::DATA::${name}" .
          "{Object::LocalVars::_ident( \$_[0] )}" ;
}

#--------------------------------------------------------------------------#
# _gen_class_locals
#--------------------------------------------------------------------------#

sub _gen_class_locals {
    no strict 'refs';
    my $package = shift;
    my $evaltext = "";
    my @props = keys %{$package."::CLASSDATA"};
    return "" unless @props;
    my @globs = map { "*${package}::$_" } @props;
    my @refs = map { "\\\$${package}::CLASSDATA{$_}" } @props;
    $evaltext .= "  local ( " .  join(", ", @globs) .  " ) = ( " .
                   join(", ", @refs) . " );\n";
    return $evaltext;
}

#--------------------------------------------------------------------------#
# _gen_mutator
#--------------------------------------------------------------------------#

sub _gen_mutator {
    my ($package, $name, $classwide) = @_;
    return $classwide
        ? "\$${package}::CLASSDATA{${name}} = \$_[1];\n" .
          "return \$_[0] "
        : "\$${package}::DATA::${name}" .
          "{Object::LocalVars::_ident( \$_[0] )} = \$_[1];\n" .
          "return \$_[0]";
}

#--------------------------------------------------------------------------#
# _gen_object_locals
#--------------------------------------------------------------------------#

sub _gen_object_locals {
    no strict 'refs';
    my $package = shift;
    my @props = keys %{$package."::DATA::"};
    return "" unless @props;
    my $evaltext = "  my \$id;\n"; # need to define it
    $evaltext .= "  \$id = Object::LocalVars::_ident(\$obj) if ref(\$obj);\n";
    my @globs = map { "*${package}::$_" } @props;
    my @refs = map { "\\\$${package}::DATA::$_ {\$id}" } @props;
    $evaltext .= "  local ( " .  join(", ", @globs) .  " ) = ( " .
                   join(", ", @refs) . " ) if \$id;\n";
    return $evaltext;
}

#--------------------------------------------------------------------------#
# _gen_privacy
#--------------------------------------------------------------------------#

sub _gen_privacy {
    my ($package, $name, $privacy) = @_;
    SWITCH: for ($privacy) {
        /public/    && do { return "" };

        /protected/ && do { return 
            "  my (\$caller) = caller();\n" .
            "  croak q/$name is a protected method and can't be called from ${package}/\n".
            "    unless \$caller->isa( '$package' );\n"
        };

        /private/ && do { return
            "  my (\$caller) = caller();\n" .
            "  croak q/$name is a private method and can't be called from ${package}/\n".
            "    unless \$caller eq '$package';\n"
        };
    }
}

#--------------------------------------------------------------------------#
# _ident
#--------------------------------------------------------------------------#

sub _ident {
    return 0 + $_[0];
}

#--------------------------------------------------------------------------#
# _install_accessors
#--------------------------------------------------------------------------#

sub _install_accessors {
    my ($package,$scalarref,$privacy,$classwide) = @_;
    no strict 'refs';

    # find name from reference
    my $symbol = _findsym($package, $scalarref) or die;
    my $name = *{$symbol}{NAME};

    # make the property exist to be found by give_methods()
    if ($classwide) {  
        ${$package."::CLASSDATA"}{$name} = undef;
    }
    else {
        %{$package."::DATA::".$name} = ();
    }

    # install accessors
    return if $privacy eq "private"; # unless private 
    my $evaltext = 
            "*${package}::${name} = sub { \n" .
                _gen_privacy( $package, $name, $privacy ) .
                _gen_accessor( $package, $name, $classwide ) .
            "\n}; \n\n" .
            "*${package}::set_${name} = sub { \n" .
                _gen_privacy( $package, "set_$name", $privacy ) .
                _gen_mutator( $package, $name, $classwide ) .
            "\n}; "
    ; # my
    # XXX print "\n\n$evaltext\n\n";
    eval $evaltext;
    die $@ if $@;
    return;
}    

#--------------------------------------------------------------------------#
# _install_wrapper
#--------------------------------------------------------------------------#

sub _install_wrapper {
    my ($package,$coderef,$privacy) = @_;
    no strict 'refs';
    no warnings 'redefine';
    my $symbol = _findsym($package, $coderef) or die;
    my $name = *{$symbol}{NAME};
    *{$package."::METHODS::$name"} = $coderef;
    my $evaltext = "*${package}::${name} = sub {\n". 
            "  my \$obj = shift;\n" .
            _gen_privacy( $package, $name, $privacy ) .
            "  local \$${package}::self = \$obj;\n" .
            _gen_class_locals($package) .
            _gen_object_locals($package) .
            "  local \$Carp::CarpLevel = \$Carp::CarpLevel + 2;\n".
            "  ${package}::METHODS::${name}(\@_);\n".
        "}\n"
    ; # my
    # XXX print "\n\n$evaltext\n\n";
    eval $evaltext;
    die $@ if $@;
    return;
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
C<$self>) are declared as package globals.  Method calls are wrapped such that 
these globals take on a local value that is correct for the specific calling
object and the duration of the method call.  I.e. C<$self> is locally aliased
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
As a result, Object::LocalVars to deliver a variety of features -- though with
some drawbacks.

=head2 Features

=over

=item * 

Provides $self automatically to methods without 'C<my $self = shift>' and the
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
under C<use strict>

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

=item *

Minimally thread-safe under a recent release of Perl 5.8 -- objects are 
cloned across thread boundaries (or a C<fork> on Win32)

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

=item *

Does not support threads::shared -- objects existing before a new thread is
created will persist into the new thread, but changes in an object cannot be
reflected in the corresponding object in the other thread

=back

=head1 USAGE

=head2 Overview

(TODO: discuss general usage, from importing through various pieces that can
be defined)

=head2 Declaring Object Properties

(TODO: Define object properties)

Properties are declared by specifying a package variable using C<our> and an
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
programming is to call private methods directly, C<< foo($self,@args) >>, rather
than with method lookup, C<< $self->foo(@args) >>.  With Object::LocalVars, a
private method should be called as C<< foo(@args) >> as the local aliases for $self
and the properties are already in place.

I<Avoiding hidden internal data>

For a package using Object::LocalVars, e.g. C<My::Package>, object properties
are stored in C<My::Package::DATA>, class properties are stored in 
C<My::Package::CLASSDATA>, and methods are stored in 
C<My::Package::METHODS>. Do not access these areas directly or overwrite 
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

These other modules provide similiar functionality and/or inspired this one. 
Quotes are from their respective documentations.

=over

=item *

L<Attribute::Property> -- "easy lvalue accessors with validation"; uses
attributes to mark object properties for accessors; validates lvalue usage
with a hidden tie

=item *

L<Class::Std> -- "provides tools that help to implement the 'inside out object'
class structure"; based on the book I<Perl Best Practices>; nice support for
multiple-inheritance and operator overloading

=item *

L<Lexical::Attributes> -- "uses a source filter to hide the details of the
Inside-Out technique from the user"; API based on Perl6 syntax; provides 
$self automatically to methods

=item *

L<Spiffy> -- "combines the best parts of Exporter.pm, base.pm, mixin.pm and
SUPER.pm into one magic foundation class"; "borrows ideas from other OO
languages like Python, Ruby, Java and Perl 6"; optionally uses source filtering
to provide $self automatically to methods

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
