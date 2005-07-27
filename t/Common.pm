package t::Common;
use strict;
use warnings;
use Exporter 'import';
our @EXPORT = qw( 
    test_constructor TC
    test_accessors TA
    test_methods TM
    test_new TN
);

use Test::More;
use Test::Exception;

sub load_fail_msg { return "because $_[0] isn't loaded" }
sub method_fail_msg { return "because $_[0] can't $_[1]" }

sub TC { return 1 + TN() }
sub test_constructor {
    my ($class, @args) = @_;
    my $pass = require_ok( $class );
    my $o;
    SKIP: {
        skip load_fail_msg($class), TC() - 1 unless $pass;
        $o = test_new($class,@args);
    }
    return $o;
}

sub TN { return 2 }
sub test_new {
    my ($class, @args) = @_;
    my $o;
    ok( $o = $class->new(@args), "create a $class");
    isa_ok( $o, $class );
    return $o;
}


sub TA { return TN() + 6 }
sub test_accessors {
    my ($o, $prop) = @_;
    my $class = ref($o);
    my $pass = can_ok( $o, $_, "set_$_" );
    SKIP: {
        skip load_fail_msg($class), TA() - 1  unless $pass;
        my $p = test_new($class);
        my $value1 = "foo";
        my $value2 = "bar";
        my $set = "set_$prop";
        is( $o->$set($value1), $o, 
            "$set(\$value1) returns self for object 1" );
        is( $o->$prop, $value1,
            "$prop() equals \$value1 for object 1" );
        is( $p->$set($value2), $p, 
            "$set(\$value2) returns self for object 2" );
        is( $p->$prop, $value2,
            "$prop() equals \$value2 for object 2" );
        is( $o->$prop, $value1,
            "$prop() still equals \$value1 for object1" );
    }
    return $pass;
}

sub TM { return 2 }
sub test_methods {
    my ($o, $case) = @_;
    my ($method, $args, $result) = @$case;
    my $class = ref($o);
    my $pass = can_ok( $o, $method );
    SKIP: {
        skip method_fail_msg($class, $method), TM() - 1  unless $pass;
        is( $o->$method(@$args), $result, "$method gave correct result" );
    }
    return $pass;
}

1;
