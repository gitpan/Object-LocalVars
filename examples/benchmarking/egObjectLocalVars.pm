package egObjectLocal;
use strict;
use warnings;
use Object::LocalVars;

our $prop1 : Pub;
our $prop2 : Pub;
our $prop3 : Pub;
our $prop4 : Pub;

sub crunch : Method {
    $prop1 = rand;
    $prop2 = rand;
    $prop3 = rand;
    $prop4 = rand;
    return $prop1 + $prop2 + $prop3 + $prop4;
}

1;

