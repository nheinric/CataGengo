package CataGengo::Controller::MyGengo::Account;

use Moose;
use namespace::autoclean;

BEGIN { extends 'CataGengo::Controller::MyGengo' }

use WebService::MyGengo::Account;

=head1 DESCRIPTION

Controller containing Account-related endpoints.

=cut

=head1 ENDPOINTS

=head2 view | /mygengo/account

Display Account information

As there are is current no way to update an account via the API
there are no endpoints to accept POST/PUT

=cut
sub view :PathPart('account') :Chained('../mygengo') :Args(0) {
    my ( $self, $c ) = ( shift, @_ );

    my $acct = $c->session->{ 'WebService::MyGengo::Account' };

    if ( !$acct ) {
        $acct = $c->model('MyGengo')->get_account();
        $c->session->{ ref($acct) } = $acct;
    }
    
    !$acct and Catalyst::Exception->throw("Could not fetch account info."
        . " Check values in catagengo.conf");

    $c->stash(
        account => $c->session->{ ref($acct) }
        );
}

=head1 AUTHOR

Nathaniel Heinrichs

=head1 LICENSE

Copyright (c) 2011, Nathaniel Heinrichs <nheinric-at-cpan.org>.
All rights reserved.

This library is free software. You can redistribute it and/or modify
it under the same terms as Perl itself.

=cut


__PACKAGE__->meta->make_immutable;

1;
