use Module::Build;
# See perldoc Module::Build for details of how this works

Module::Build->new(
    module_name     => 'Object::LocalVars',
    dist_author => 'David A Golden <dagolden@cpan.org>', 
    create_makefile_pl => "traditional",
    create_readme => 1,
    license         => 'perl',
    requires => {
        perl => 5.006,
        Test::More => 0.47,
        Test::Exception => 0,   # any version has lives_ok and dies_ok
    },
    build_requires  => { 
    },
    meta_add => { 
        noindex => { directory => [ qw/examples/ ] } 
    },
)->create_build_script;
