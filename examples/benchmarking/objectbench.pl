#!/usr/bin/perl
use strict;
use warnings;
use Benchmark qw(:all :hireswallclock);

use egObjectLocalVars;
use egClassMethodMaker;
use egHandRoll;

sub create {
    my $o = shift->new;
}

sub crank {
    shift->crunch;
}

sub churn {
    my $obj = shift;
    $obj->set_prop1(rand);
    $obj->set_prop2(rand);
    $obj->set_prop3(rand);
    $obj->set_prop4(rand);
    return $obj->prop1 + $obj->prop2 + $obj->prop3 + $obj->prop4;
}

sub cycle {
    my $obj = shift->new;
    $obj->crunch;
}

my $egObjectLocal = egObjectLocal->new;
my $egClassMethodMaker = egClassMethodMaker->new;
my $egHandRoll = egHandRoll->new;

print "OBJECT CREATE & DESTROY\n";
cmpthese ( 500000, {
    'Class::MethodMaker'    => sub { create("egClassMethodMaker") },
    'Object::LocalVars'         => sub { create("egObjectLocal") },
    'Hand Rolled'           => sub { create("egHandRoll") },
});

print "\nOBJECT PROPERTY ACCESS\n";
cmpthese ( 500000, {
    'Class::MethodMaker'    => sub { churn($egClassMethodMaker) },
    'Object::LocalVars'         => sub { churn($egObjectLocal) },
    'Hand Rolled'           => sub { churn($egHandRoll) },
});

print "\nOBJECT PROPERTY ACCESS INSIDE METHODS\n";
cmpthese ( 500000, {
    'Class::MethodMaker'    => sub { crank($egClassMethodMaker) },
    'Object::LocalVars'         => sub { crank($egObjectLocal) },
    'Hand Rolled'           => sub { crank($egHandRoll) },
});

print "\nFULL CYCLE\n";
cmpthese ( 100000, {
    'Class::MethodMaker'    => sub { cycle("egClassMethodMaker") },
    'Object::LocalVars'         => sub { cycle("egObjectLocal") },
    'Hand Rolled'           => sub { cycle("egHandRoll") },
});

    

