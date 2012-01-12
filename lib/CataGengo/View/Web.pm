package CataGengo::View::Web;

use strict;
use warnings;

use base 'Catalyst::View::TT';

use DateTime::Format::Duration;

__PACKAGE__->config(
    TEMPLATE_EXTENSION => '.tt'
    , DEFAULT_ENCODING => 'utf-8'
    , INCLUDE_PATH => [
        CataGengo->path_to( 'root' )
        , CataGengo->path_to( 'root', 'mygengo' )
        ],
    , render_die => 1
    , expose_methods => [qw/localize loc dhms_for_duration ucfirst/]
#    , DEBUG => 'all'
);

=head1 NAME

CataGengo::View::Web - TT View for CataGengo

=head1 DESCRIPTION

TT View for CataGengo.

=head1 METHODS

=head2 localize( $string, [$locale] ) 

Localize the given string.

Synonym 'loc' is also available.

TODO Currenty a no-op placeholder for a real l10n routine.

=cut
sub loc { return shift->localize(@_); }
sub localize {
    return $_[2];
}

=head2 format_duration( $DateTime::Duration )

Converts a L<DateTime::Duration> into an array of days, hours, minutes and
seconds.

Uses DateTime::Format::Duration because DateTime::Duration on its own does
not convert from, eg, 86400 seconds to 1 day.

=cut
sub dhms_for_duration {
    my ( $self, $c, $duration ) = ( shift, @_ );

    !$duration and return ( 0, 0, 0, 0 );

    my $dfd = DateTime::Format::Duration->new(
        pattern => '%d %H %M %S'
        , normalize => 1
        );
    my $s = $dfd->format_duration( $duration );

    return split('\s+', $s);
}

=head2 ucfirst( $value )

Same as the perl function of the same name.

=cut
sub ucfirst { ucfirst($_[2]) }

=head1 SEE ALSO

L<CataGengo>

=head1 AUTHOR

Nathaniel Heinrichs

=head1 LICENSE

Copyright (c) 2011, Nathaniel Heinrichs <nheinric-at-cpan.org>.
All rights reserved.

This library is free software. You can redistribute it and/or modify
it under the same terms as Perl itself.

=cut

1;
