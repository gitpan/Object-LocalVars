#!/usr/bin/perl
use strict;
use warnings;
use blib;  
use threads;
use threads::shared;
use Config;
use Test::More;
use t::Common;
# work around win32 console buffering
Test::More->builder->failure_output(*STDOUT) 
    if ($^O eq 'MSWin32' && $ENV{HARNESS_VERBOSE});

my $class = "t::Object::Complete";

if ( $Config{useithreads} ) {
    plan 'no_plan';
}
else {
    plan skip_all => "Perl ithreads not available"
}


my $o = test_constructor($class, name => "Charlie" );

TODO: {
    local $TODO = "thread-safety";

    my $thr = threads->new( sub { 
            is( $o->name, "Charlie", "got right name in thread") 
    } );

    $thr->join;
}

