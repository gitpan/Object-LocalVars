package egClassMethodMaker;
use strict;
use warnings;

use Class::MethodMaker (
    new => "new",
    get_set => [qw( -eiffel
        prop1
        prop2
        prop3
        prop4
    )],
);

sub crunch {
    my $self = shift;
    $self->set_prop1(rand);
    $self->set_prop2(rand);
    $self->set_prop3(rand);
    $self->set_prop4(rand);
    return $self->prop1 + $self->prop2 + $self->prop3 + $self->prop4;
}

1;
