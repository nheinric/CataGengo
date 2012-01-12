#!/usr/bin/env perl
# IMPORTANT: if you delete this file your app will not work as
# expected.  You have been warned.
use inc::Module::Install;
use Module::Install::Catalyst; # Complain loudly if you don't have
                               # Catalyst::Devel installed or haven't said
                               # 'make dist' to create a standalone tarball.

name 'CataGengo';
all_from 'lib/CataGengo.pm';

requires 'Catalyst::Runtime' => '5.80033';
requires 'Catalyst::Plugin::ConfigLoader';
requires 'Catalyst::Plugin::Static::Simple';
requires 'Catalyst::Action::RenderView';
requires 'Config::General'; # This should reflect the config file format you've chosen
                 # See Catalyst::Plugin::ConfigLoader for supported formats

requires 'Catalyst::View::TT';
requires 'Catalyst::Model::Factory';
requires 'Catalyst::Plugin::Unicode::Encoding';
requires 'Catalyst::Plugin::Session';
requires 'Catalyst::Plugin::Session::Store::Dummy';
requires 'Catalyst::Plugin::Session::State::Cookie';

requires 'Moose';
requires 'MooseX::NonMoose';
requires 'namespace::autoclean';
requires 'DateTime';
requires 'DateTime::Format::Duration';
requires 'FindBin';
requires 'Catalyst::Controller::REST';

# Must be installed by hand. See INSTALL file
#requires 'WebService::MyGengo' => '0.010';
#requires 'Catalyst::Model::WebService::MyGengo' => '0.001';

test_requires 'JSON';
test_requires 'LWP::UserAgent';
test_requires 'URI::Escape';
test_requires 'Getopt::Long';
test_requires 'Test::WWW::Mechanize::Catalyst';
test_requires 'Test::More' => '0.88';
catalyst;

install_script glob('script/*.pl');
auto_install;
manifest_skip;
WriteAll;
