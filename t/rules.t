package MyConfig;
use strict;
use warnings;
use Config::ENV::Multi [qw/ENV REGION/],
    rule => '{ENV}_{REGION}';

config  => {
    cnf => '/etc/my.cnf',
};
config [qw/prod jp/] => {
    db_host => 'jp.local',
};
config [qw/prod us/] => {
    db_host => 'us.local',
};
config [qw/dev */] => {
    db_host => 'localhost',
};

use Test::More;
use Test::Deep;

undef $ENV{ENV};
undef $ENV{REGION};

cmp_deeply +__PACKAGE__->current, {
    cnf => '/etc/my.cnf',
};

$ENV{ENV}    = 'prod';
$ENV{REGION} = 'jp';

cmp_deeply +__PACKAGE__->current, {
    cnf => '/etc/my.cnf',
    db_host => 'jp.local',
};

$ENV{ENV}    = 'prod';
$ENV{REGION} = 'us';

cmp_deeply +__PACKAGE__->current, {
    cnf => '/etc/my.cnf',
    db_host => 'us.local',
};

$ENV{ENV}    = 'dev';
$ENV{REGION} = 'jp';

cmp_deeply +__PACKAGE__->current, {
    cnf => '/etc/my.cnf',
    db_host => 'localhost',
};

$ENV{ENV}    = 'dev';
$ENV{REGION} = 'us';

cmp_deeply +__PACKAGE__->current, {
    cnf => '/etc/my.cnf',
    db_host => 'localhost',
};


done_testing;

