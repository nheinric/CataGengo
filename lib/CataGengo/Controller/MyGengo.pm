package CataGengo::Controller::MyGengo;
use Moose;
use namespace::autoclean;

BEGIN { extends 'Catalyst::Controller' }

=head1 DESCRIPTION

Sparse controller class to anchor the MyGengo URL namespace.

=head1 ENDPOINTS

=head2 mygengo | /mygengo

Anchor for /mygengo URLs.

=cut
sub mygengo :PathPrefix :Chained('/') :CaptureArgs(0) { }

=head2 default

Forward to the Account page.

=cut
sub default :Path {
    my ( $self, $c ) = @_;
    $c->go( $c->controller('MyGengo::Account')->action_for('view') );
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
