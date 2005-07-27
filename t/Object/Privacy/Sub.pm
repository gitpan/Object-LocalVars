package t::Object::Privacy::Sub;
use strict;
use warnings;
use base "t::Object::Privacy";
use Object::LocalVars;

give_methods our $self;

sub protected_super_meth : Method { return $self->protected_meth; }

sub private_super_meth   : Method { return $self->private_meth; }

sub protected_super_prop : Method { 
    $self->set_protected_prop( 1 );
    $self->set_class_protected_prop( 2 );
    return $self->protected_prop + $self->class_protected_prop;
}

sub private_super_prop : Method { 
    $self->set_private_prop( 1 );
    $self->private_prop;
}



