package Config::ENV::Multi;
use 5.008001;
use strict;
use warnings;
use Carp qw/croak/;

our $VERSION = "0.01";

sub import {
    my $class   = shift;
    my $package = caller(0);

    no strict 'refs';
    if (__PACKAGE__ eq $class) {
        my $envs = shift;
        my %opts    = @_;
        #
        # rule => '{ENV}_{REGION}',
        # any => '*',
        # unset => '&';
        #

        push @{"$package\::ISA"}, __PACKAGE__;

        for my $method (qw/common config any unset parent load/) {
            *{"$package\::$method"} = \&{__PACKAGE__ . "::" . $method}
        }

        my %wildcard = (
            any   => '*',
            unset => '!',
        );
        $wildcard{any}   = $opts{any}   if $opts{any};
        $wildcard{unset} = $opts{unset} if $opts{unset};

        $envs = [$envs] unless ref $envs;
        my $mode = $opts{rule} ? 'rule': 'env';

        no warnings 'once';
        ${"$package\::data"} = +{
            specific => {},
            mode     => $mode, # env or rule
            envs     => $envs,
            rule     => $opts{rule},
            wildcard => \%wildcard,
            cache    => {},
            export   => $opts{export},
        };
    } else {
        my %opts    = @_;
        my $data = _data($class);
        if (my $export = $opts{export} || $data->{export}) {
           *{"$package\::$export"} = sub () { $class };
        }
    }
}

# copy from Config::ENV
sub load ($) { ## no critic
    my $filename = shift;
    my $hash = do "$filename";

    croak $@ if $@;
    croak $^E unless defined $hash;
    unless (ref($hash) eq 'HASH') {
        croak "$filename does not return HashRef.";
    }

    wantarray ? %$hash : $hash;
}

sub parent ($) { ## no critic
    my $package = caller(0);
    my $e_or_r = shift;

    my $target;
    my $data = _data($package);
    if ($data->{mode} eq 'env') {
        $target = __envs2key($e_or_r);
    } else {
        $target = __envs2key(__clip_rule($data->{rule}, $e_or_r));
    }
    %{ $data->{specific}->{$target} || {} };
}

sub any {
    my $package = caller(0);
    _data($package)->{wildcard}{any};
}

sub unset {
    my $package = caller(0);
    _data($package)->{wildcard}{unset};
}

# {ENV}_{REGION}
# => ['ENV', 'REGION]
sub __parse_rule {
    my $rule = shift;
    return [
        grep { defined && length }
        map {
            /^\{(.+?)\}$/ ? $1 : undef
        }
        grep { defined && length }
        split /(\{.+?\})/, $rule
    ];
}

# {ENV}_{REGION} + 'prod_jp'
# => ['prod', 'jp']
sub __clip_rule {
    my ($template, $rule) = @_;
    my $spliter = [
        grep { defined && length }
        map {
            /^\{(.+?)\}$/ ? undef : $_
        }
        grep { defined && length }
        split /(\{.+?\})/, $template
    ];
    my $pattern = '(.*)' . ( join '(.*)', @{$spliter} ) . '(.*)';
    my @clip = ( $rule =~ /$pattern/g );
    return \@clip;
}

sub _data {
    my $package = shift;
    no strict 'refs';
    no warnings 'once';
    ${"$package\::data"};
}

sub common {
    my $package = caller(0);
    my $hash = shift;
    my $data = _data($package);
    my $envs = $data->{envs};
    $envs = [$envs] unless ref $envs;
    my $any  = $data->{wildcard}{any};
    my $name = __envs2key([ map { "$any" } @{$envs} ]);

    _config_env($package, $name, $hash);
}

sub config {
    my $package = caller(0);
    if (_data($package)->{mode} eq 'env') {
        return _config_env($package, @_);
    } else {
        return _config_rule($package, @_);
    }
}

sub _config_env {
    my ($package, $envs, $hash) = @_;
    my $data = _data($package);

    my $name = __envs2key($envs);

    $data->{specific}{$name} = $hash;
}

sub _config_rule {
    my ($package, $rule, $hash) = @_;
    my $data = _data($package);

    my $target = __envs2key(__clip_rule($data->{rule}, $rule));

    $data->{specific}{$target} = $hash;
}

sub current {
    my $package = shift;
    my $data = _data($package);
    my $wildcard = $data->{wildcard}->{unset};

    my $cache_key = __envs2key([map { defined $ENV{$_} ? $ENV{$_} : $wildcard  } @{ $data->{envs} }]);
    my $vals = $data->{cache}->{$cache_key} ||= +{
        %{ _value($package) || {} },
    };
}

sub param {
    my ($package, $name) = @_;
    $package->current->{$name};
}

sub __embeded {
    my ($caption, $dataset) = @_;
    for my $key (keys %{$dataset}) {
        next unless $dataset->{$key};
        $caption =~ s/$key/$dataset->{$key}/g;
    }
    return $caption;
}

sub __any_dataset {
    my ($caption, $wildcard) = @_;
    my $anys = [];
    my $envs = __key2envs($caption);
    my @allenvs = ();
    push @allenvs , { map { $_ => $wildcard } @$envs };
    for my $target (@$envs) {
        my $ast = { map { $_ => $wildcard } @$envs };
        push @allenvs, { %$ast, $target => $ENV{$target} };
    }

    return \@allenvs;
}

sub _value_specific {
    my $package = shift;
    my $envs = _data($package)->{specific};
    my $wildcard = _data($package)->{wildcard}->{unset};
    my $target = __envs2key([
        map { defined $ENV{$_} ? $ENV{$_} : $wildcard }
        @{ _data($package)->{envs} }
    ]);
    return $envs->{$target} || {};
}

sub _value_any {
    my $package = shift;
    my $envs = _data($package)->{specific};
    my $wildcard = _data($package)->{wildcard}{any};
    my $key = __envs2key(_data($package)->{envs});
    my %values;
    for my $dataset (@{__any_dataset($key, $wildcard)}) {
        my $compiled = __embeded($key, $dataset);
        %values = ( %values, %{ $envs->{$compiled} || {} } );
    }
    return \%values;
}

sub _value_unset {
    my $package = shift;
    my $envs = _data($package)->{specific};
    my $wildcard = _data($package)->{wildcard}{any};
    my $key = __envs2key(_data($package)->{envs});
    my %values;
    for my $dataset (@{__any_dataset($key, $wildcard)}) {
        my $compiled = __embeded($key, $dataset);
        %values = ( %values, %{ $envs->{$compiled} || {} } );
    }
    return \%values;
}

sub _value {
    my $package = shift;

    my $specific = _value_specific($package);
    my $any      = _value_any($package);

    return {
        %{ $any },
        %{ $specific },
    };
}

sub __envs2key {
    my $v = shift;
    $v = [$v] unless ref $v;
    join '@#%@#', grep { $_ if ($_) } @{$v};
}

sub __key2envs {
    my $f = shift;
    [split '@#%@#', $f];
}

1;
__END__

=encoding utf-8

=head1 NAME

Config::ENV::Multi - Config::ENV supported Multi ENV

=head1 SYNOPSIS

    package Config;
    use Config::ENV::Multi [qw/ENV REGION/], any => ':any:', unset => ':unset:';

    common {
        # alias of [qw/:any: :any:/]
        # alias of [any, any]
        cnf => 'my.cnf',
    };

    config [qw/dev :any:/] => sub {
        debug => 1,
        db    => 'localhost',
    };

    config [qw/prod jp/] => sub {
        db    => 'jp.localhost',
    };

    config [qw/prod us/] => sub {
        db    => 'us.localhost',
    };

    Config->current;
    # $ENV{ENV}=dev, $ENV{REGION}=jp
    # {
    #   cnf    => 'my.cnf',
    #   debug  => 1,
    #   db     => 'localhost',
    # }

=head1 DESCRIPTION

supported multi environment L<Config::ENV>.

=head1 SEE ALSO

L<Config::ENV>

=head1 LICENSE

Copyright (C) Hiroyoshi Houchi.

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=head1 AUTHOR

Hiroyoshi Houchi E<lt>git@hixi-hyi.comE<gt>

=cut

