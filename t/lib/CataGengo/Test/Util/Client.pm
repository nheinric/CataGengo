package CataGengo::Test::Util::Client;

use strict;
use warnings;

use CataGengo;                              # We need some default config values
use WebService::MyGengo::Client;            # The API library
use WebService::MyGengo::Test::Mock::LWP;   # The mock LWP::UserAgent

use Exporter;

use vars qw(@ISA @EXPORT);
use base qw(Exporter);

@EXPORT = qw(client);

# TODO
use feature 'say';
use Data::Dumper;

=head1 NAME

CataGengo::Test::Util::Client - Basic access to a WebService::MyGengo::Client

=head1 SYNOPSIS

    # t/some-test.t
    use CataGengo::Test::Util:Client;

    # use_sandbox = 0 ~ Production API access. Make sure your keys are correct!
    # use_sandbox = 1 ~ Sandbox API access.
    # use_sandbox = 2 ~ No API access at all (uses a mocked LWP::UserAgent)
    my %config = { public_key => 'pub', private_key => 'priv', use_sandbox => 2 };
    my $client = client( \%config );
    my $job = $m->getTranslationJob( $id ); # A mock Job

    # You can use the live version as well, just be careful of throttling
    $config{use_sandbox} = 1;
    $client = client( \%config );
    $job = $m->getTranslationJob( $id ); # A mock Job

    # Create a fresh client object like this.
    # Note that if you're using the mocked version you will
    #   lose any Jobs/etc. that you previously posted
    $config{refresh} = 1;
    $client = client(\%config);

=head1 METHODS

=head2 new( \%args )

Synonym for client. Called by Catalyst to construct the Model.

=cut
sub new { client() }

=head2 client( \%user_args? )

Returns an instance of the myGengo client library.

Supply \%user_args to override defaults, which are pulled from the CataGengo
configuration.

Uses the $ENV{CATAGENGO_TEST_LIVE} environment variable to determine whether
to use the mocked version of the client or the value from the
CataGengo configuration.

The instance is a singleton to allow for testing using the
same library instance from within your tests as well as Catalyst.

If you want a fresh instance you can supply the `refresh => 1` parameter
in \%user_args.

See L<SYNOPSIS> for other usage.

=cut
our $_client;
sub client {
    my ( $user_args ) = ( shift );

    # The user has to explicitly ask for live sandbox testing
    !defined($user_args->{use_sandbox}) and
        $user_args->{use_sandbox} //= $ENV{CATAGENGO_TEST_LIVE} // 2;

    # Merge defaults and user_args
    my %args = %{ CataGengo->config->{'Model::MyGengo'} };
    $user_args and @args{ keys %$user_args } = values %$user_args;

    !$args{use_sandbox} and die "Will not allow live API access from tests.";
    defined($_client) and !exists($args{refresh}) and return $_client;

    my $client;
    if ( $args{use_sandbox} == 2 ) {
        $args{use_sandbox} = 1;
        $client = WebService::MyGengo::Client->new( \%args );

        # A mock LWP to simulate real API access
        my $ua = WebService::MyGengo::Test::Mock::LWP->new( %args );
        $client->_set_user_agent( $ua );

        # Force Catalyst to use us as it's model class
        CataGengo->config->{'Model::MyGengo'}->{class}
            = 'CataGengo::Test::Util::Client';
    }
    else {
        $client = WebService::MyGengo::Client->new( \%args );
    }

    return $_client = $client;
}


1;

=head1 AUTHOR

Nathaniel Heinrichs

=head1 LICENSE

Copyright (c) 2011, Nathaniel Heinrichs <nheinric-at-cpan.org>.
All rights reserved.

This library is free software. You can redistribute it and/or modify
it under the same terms as Perl itself.

=cut
