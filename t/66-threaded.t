#!/usr/bin/perl
use strict;
use warnings;
use blib;  
use threads;
use Config;
use Test::More;
use t::Common;
# work around win32 console buffering
Test::More->builder->failure_output(*STDOUT) 
    if ($^O eq 'MSWin32' && $ENV{HARNESS_VERBOSE});

my $class = "t::Object::Complete";

if ( $Config{useithreads} ) {
    if( $] < 5.008 ) {
        plan skip_all => "thread support requires perl 5.8";
    }
    else {
        plan tests => 4;
    }
}
else {
    plan skip_all => "perl ithreads not available";
}

my $o = test_constructor($class, name => "Charlie" );

my $thr = threads->new( 
    sub { 
        is( $o->name, "Charlie", "got right name in thread") 
    } 
);

$thr->join;

