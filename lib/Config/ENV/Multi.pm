package Config::ENV::Multi;
use 5.008001;
use strict;
use warnings;

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
        # wildcard => { any => '*', unset => '&' },
        #

        push @{"$package\::ISA"}, __PACKAGE__;

        for my $method (qw/common config/) {
            *{"$package\::$method"} = \&{__PACKAGE__ . "::" . $method}
        }
        my $mode = $opts{rule} ? 'rule': 'env';
        my $wildcard = {
            any   => '*',
            unset => '!',
        };
        $envs = [$envs] unless ref $envs;

        no warnings 'once';
        ${"$package\::data"} = +{
            specific    => {},
            global_mode => $mode, # env or rule
            global_envs => $envs,
            global_rule => $opts{rule},
            wildcard    => $wildcard,
            cache       => {},
        };
    } else {
        my %opts    = @_;
        my $data = _data($class);
        if (my $export = $opts{export} || $data->{export}) {
           *{"$package\::$export"} = sub () { $class };
        }
    }
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

sub _mode {
    my $package = shift;
    my $data = _data($package);
    return $data->{global_mode};
}

sub common {
    my $package = caller(0);
    my $hash = shift;
    my $data = _data($package);
    my $envs = $data->{global_envs};
    $envs = [$envs] unless ref $envs;
    my $any  = $data->{wildcard}{any};
    my $name = __envs2key([ map { "$any" } @{$envs} ]);

    _config_env($package, $name, $hash);
}

sub config {
    my $package = caller(0);
    if (_mode($package) eq 'env') {
        return _config_env($package, @_);
    } else {
        return _config_rule($package, @_);
    }
}

sub _config_env {
    my ($package, $envs, $hash) = @_;
    my $data = _data($package);

    my $name = __envs2key($envs);
    my $current_env = __envs2key($data->{global_envs});

    $data->{specific}{$current_env}{$name} = $hash;
}

sub _config_rule {
    my ($package, $rule, $hash) = @_;
    my $data = _data($package);

    my $current_env = __envs2key($data->{global_envs});
    my $target = __envs2key(__clip_rule($data->{global_rule}, $rule));

    $data->{specific}{$current_env}{$target} = $hash;
}

sub current {
    my $package = shift;
    my $data = _data($package);

    my $cache_key = __envs2key([map { $ENV{$_} } @{ $data->{global_envs} }]);
    my $vals = $data->{cache}->{$cache_key} ||= +{
        %{ _value($package) || {} },
    };
}

sub __embeded {
    my ($caption, $dataset) = @_;
    for my $key (keys $dataset) {
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
    my ($package) = shift;
    my $envs = _data($package)->{specific};
    my %values;
    for my $key (keys %{$envs})  {
        my $compiled = __envs2key([map { $ENV{$_} } @{ __key2envs($key) }]);
        %values = ( %values, %{ $envs->{$key}{$compiled} || {}} );
    }
    return \%values;
}

sub _value_any {
    my ($package) = shift;
    my $envs = _data($package)->{specific};
    my $wildcard = _data($package)->{wildcard}{any};
    my %values;
    for my $key (keys %{$envs})  {
        for my $dataset (@{__any_dataset($key, $wildcard)}) {
            my $compiled = __embeded($key, $dataset);
            %values = ( %values, %{ $envs->{$key}{$compiled} || {} } );
        }
    }
    return \%values;
}

sub _value {
    my ($package) = shift;
    my $envs = _data($package)->{specific};

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
    join '%%', grep { $_ if ($_) } @{$v};
}

sub __key2envs {
    my $f = shift;
    [split '%%', $f];
}



1;
__END__

=encoding utf-8

=head1 NAME

Config::ENV::Multi - It's new $module

=head1 SYNOPSIS

    use Config::ENV::Multi;

=head1 DESCRIPTION

Config::ENV::Multi is ...

=head1 LICENSE

Copyright (C) Hiroyoshi Houchi.

This library is free software; you can redistribute it and/or modify
it under the same terms as Perl itself.

=head1 AUTHOR

Hiroyoshi Houchi E<lt>git@hixi-hyi.comE<gt>

=cut

