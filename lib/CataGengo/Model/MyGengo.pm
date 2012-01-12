package CataGengo::Model::MyGengo;

use strict;
use parent qw( Catalyst::Model::WebService::MyGengo );

__PACKAGE__->config({
    class           => 'WebService::MyGengo::Client'
    , public_key    => 'pubkey'
    , private_key   => 'privkey'
    , use_sandbox   => 1
    });

1;
