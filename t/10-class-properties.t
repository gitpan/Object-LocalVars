#!/usr/bin/perl
use strict;
use warnings;
use blib;  

use Test::More;
use t::Common;
# work around win32 console buffering
Test::More->builder->failure_output(*STDOUT) 
    if ($^O eq 'MSWin32' && $ENV{HARNESS_VERBOSE});


my $class = "t::Object::PropAliases";

plan tests => TC() + TN() + 5;

my $o = test_constructor($class);

SKIP: {
    skip "because we don't have a $class object", TN() + 7  
        unless $o;
    ok( $o->set_name("Charlie"), 
        "Naming new object 'Charlie'");
    is( $o->inc_count, 1, "Incrementing counter for Charlie");
    my $p = test_new($class);
    ok( $p->set_name("Curly"), 
        "Naming new object 'Curly'");
    is( $p->inc_count, 2, "Incrementing counter for Curly");
    is( $o->get_count, " () is one of 2", "Getting counter via Charlie");
}




