package t::Object::Privacy;
use strict;
use warnings;
use Object::LocalVars;

give_methods our $self;

our $private_prop    : Priv;
our $protected_prop  : Prot;
our $public_prop     : Pub;
our $default_prop    : Prop;

our $class_prop      : Class;
our $class_private_prop  : ClassPriv;
our $class_protected_prop  : ClassProt;
our $class_public_prop  : ClassPub;

sub default_meth     : Method { return __PACKAGE__; }
sub public_meth      : Pub   { return __PACKAGE__; }
sub protected_meth   : Prot  { return __PACKAGE__; }
sub private_meth     : Priv  { return __PACKAGE__; }

sub private_meth_lives : Method { return $self->private_meth };

sub private_prop_lives : Method { 
    $private_prop = 1;
    $default_prop = 2;
    $class_prop = 4;
    $class_private_prop = 8;
    return $private_prop + $default_prop + $class_prop + $class_private_prop;
}


1;
