package egHandRoll;
use strict;
use warnings;

sub new { 
    return bless {}, shift;
}

sub prop1 {
    return $_[0]->{prop1};
}
sub set_prop1 {
    $_[0]->{prop1} = $_[1];
    return $_[0];
}

sub prop2 {
    return $_[0]->{prop2};
}
sub set_prop2 {
    $_[0]->{prop2} = $_[1];
    return $_[0];
}

sub prop3 {
    return $_[0]->{prop3};
}
sub set_prop3 {
    $_[0]->{prop3} = $_[1];
    return $_[0];
}

sub prop4 {
    return $_[0]->{prop4};
}
sub set_prop4 {
    $_[0]->{prop4} = $_[1];
    return $_[0];
}

sub crunch {
    my $self = shift;
    $self->set_prop1(rand);
    $self->set_prop2(rand);
    $self->set_prop3(rand);
    $self->set_prop4(rand);
    return $self->prop1 + $self->prop2 + $self->prop3 + $self->prop4;
}

1;
