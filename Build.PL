use 5.008;
use Module::Build;
# See perldoc Module::Build for details of how this works

Module::Build->new(
  module_name         => 'Object::LocalVars',
  dist_author         => 'David A Golden <dagolden@cpan.org>', 
  create_makefile_pl  => "traditional",
  create_readme       => 1,
  license             => 'perl',
  requires            => {
    perl                => 5.008,
    'Carp'              => 0,
    'Exporter'          => 0,
    'Scalar::Util'      => 1.09,    # first appearance of refaddr()
    'subs'              => 0,
  },
  build_requires      => { 
    'base'              => 0,
    'Data::Dumper'      => 0,
    'overload'          => 0, 
    'Test::More'        => 0.48,    # thread safe
    'Test::Exception'     => 0,
  },
  meta_add            => { 
    no_index            => { dir => [ qw/examples/ ] } 
  },
)->create_build_script;
