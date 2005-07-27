package t::Object::Morbid;
use strict;
use warnings;
use Carp;

use Object::LocalVars;

give_methods our $self;

sub do_die : Method {
    die "Died";
};

sub do_croak : Method {
    croak "Croaked";
};

sub do_confess : Method {
    confess "Confessed";
};

sub do_croak_removed : Method {
    $self->do_croak;
}

sub BUILD {
    # helps us trap inherited BUILD
    my $caller = caller;
    die "not building in the right package" unless ref(shift) eq __PACKAGE__;
}

sub PREBUILD {
    # helps us trap inherited PREBUILD
    die "not the right prebuild" if @_;
    return ("foo"); # if subclass inherits, parent class will die when it
                    # gets this input
}

sub DEMOLISH {
    # helps us trap inherited DEMOLISH
    my $caller = caller;
    die "not cleaning up in the right package" unless ref(shift) eq __PACKAGE__;
}

1;
