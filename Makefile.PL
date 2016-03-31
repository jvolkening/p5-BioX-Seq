use strict;
use warnings;

use ExtUtils::MakeMaker;

WriteMakefile(
    NAME                => 'BioX::Seq',
    AUTHOR              => q{Jeremy Volkening <jdv*at*base2bio*dot*com>},
    VERSION_FROM        => 'lib/BioX/Seq.pm',
    ABSTRACT_FROM       => 'lib/BioX/Seq.pm',
    LICENSE             => 'GPL_3',
    PL_FILES            => {},
    CONFIGURE_REQUIRES => {
        'ExtUtils::MakeMaker' => 0,
    },
    BUILD_REQUIRES => {
        'Test::More' => 0,
    },
    PREREQ_PM => {
    },
    EXE_FILES => [qw|
    |],
    META_MERGE => {
        'meta-spec' => { version => 2 },
        resources => {
            repository => {
                type => 'git',
                url => 'https://github.com/jvolkening/p5-BioX-Seq.git',
                web => 'https://github.com/jvolkening/p5-BioX-Seq',
            },
        },
    },
    dist                => { COMPRESS => 'gzip -9f', SUFFIX => 'gz', },
    clean               => { FILES => 'BioX-Seq-*' },
);
