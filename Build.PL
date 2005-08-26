use Module::Build;
# See perldoc Module::Build for details of how this works

Module::Build->new(
    module_name         => 'Object::LocalVars',
    dist_author         => 'David A Golden <dagolden@cpan.org>', 
    create_makefile_pl  => "traditional",
    create_readme       => 1,
    license             => 'perl',
    requires            => {
        perl                => 5.006,
        Scalar::Util        => 1.09,    # first appearance of refaddr()
        Test::More          => 0.48,    # thread safe
        Test::Exception     => 0,       #  Let's hope this works! 
    },
    build_requires      => { 
    },
    meta_add            => { 
        noindex             => { directory => [ qw/examples/ ] } 
    },
)->create_build_script;
